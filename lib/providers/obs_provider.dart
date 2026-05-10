import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

const _tag = 'OBS';

const int _maxReconnectAttempts = 15;
const int _maxSyncFailures = 2;

class OBSProvider extends ChangeNotifier {
  final OBSWebSocketService _obsService = OBSWebSocketService();
  final StorageService _storage;
  final ForegroundServiceManager _foregroundService =
      ForegroundServiceManager();

  OBSConnection? _currentConnection;
  List<OBSConnection> _connections = [];
  bool _isConnecting = false;
  String? _connectionError;

  OBSStatus _status = OBSStatus();
  List<OBSScene> _scenes = [];
  List<OBSSceneItem> _currentSceneItems = [];
  List<OBSAudioSource> _audioSources = [];
  String? _selectedSceneForItems;

  final Map<String, List<OBSSceneItem>> _allSceneItems = {};

  OBSStats _stats = OBSStats();

  // Volume meters: inputName -> [channel levels 0.0-1.0]
  final Map<String, List<double>> _volumeLevels = {};
  late final StreamController<Map<String, List<double>>> _volumeController;
  int _volumeListenerCount = 0;

  Timer? _statusTimer;
  Timer? _localTimeTimer;
  Timer? _debounceTimer;
  Timer? _reminderTimer;
  Timer? _reconnectTimer;
  Timer? _reconnectCountdownTimer;
  Timer? _statsSnapshotTimer;
  int _reconnectAttempt = 0;
  bool _manualDisconnect = false;

  // Health-check: подсчёт подряд идущих неудач периодических запросов.
  // При превышении порога соединение считается мёртвым и форсируется
  // disconnect → автоматический реконнект.
  int _consecutiveSyncFailures = 0;
  bool _forceDisconnectInProgress = false;

  Duration _localStreamDuration = Duration.zero;
  Duration _localRecordDuration = Duration.zero;
  DateTime? _streamStartTime;
  DateTime? _recordStartTime;
  DateTime? _recordPauseTime;
  Duration _recordPausedDuration = Duration.zero;

  DateTime? _lastRecordPauseAction;

  OBSProvider(this._storage) {
    _volumeController = StreamController<Map<String, List<double>>>.broadcast(
      onListen: () {
        _volumeListenerCount++;
        if (_volumeListenerCount == 1) {
          // Первый слушатель — включаем InputVolumeMeters
          _obsService.reidentify(66047); // 511 | 65536
        }
        // Инициализируем моно-канал [0.0] для известных аудио-источников,
        // если их ещё нет в кэше, и сразу пушим state — чтобы виджет
        // получил начальные данные до прихода первого ивента от OBS.
        bool changed = false;
        for (final source in _audioSources) {
          if (!_volumeLevels.containsKey(source.name)) {
            _volumeLevels[source.name] = [0.0];
            changed = true;
          }
        }
        if (changed || _volumeLevels.isNotEmpty) {
          // Микрозадержка чтобы StreamBuilder успел подписаться
          Future.microtask(
              () => _volumeController.add(Map.from(_volumeLevels)));
        }
      },
      onCancel: () {
        _volumeListenerCount--;
        if (_volumeListenerCount <= 0) {
          _volumeListenerCount = 0;
          _volumeLevels.clear();
          // Нет слушателей — отключаем InputVolumeMeters
          _obsService.reidentify(511);
        }
      },
    );
    _init();
  }

  OBSWebSocketService get obsService => _obsService;
  OBSConnection? get currentConnection => _currentConnection;
  List<OBSConnection> get connections => _connections;
  bool get isConnected => _obsService.isConnected;
  bool get isConnecting => _isConnecting;
  String? get connectionError => _connectionError;
  OBSStatus get status => _status;
  List<OBSScene> get scenes => _scenes;
  List<OBSSceneItem> get currentSceneItems => _currentSceneItems;
  List<OBSAudioSource> get audioSources => _audioSources;
  String? get selectedSceneForItems => _selectedSceneForItems;
  Map<String, List<OBSSceneItem>> get allSceneItems => _allSceneItems;
  OBSStats get stats => _stats;
  Map<String, List<double>> get volumeLevels => _volumeLevels;
  Stream<Map<String, List<double>>> get volumeStream => _volumeController.stream;

  void Function(String message)? onReminder;

  Future<void> _init() async {
    await _foregroundService.init();
    _connections = await _storage.getConnections();

    _obsService.onConnected = _onConnected;
    _obsService.onDisconnected = _onDisconnected;
    _obsService.onError = _onError;
    _obsService.onEvent = _handleEvent;

    // При изменении профиля энергосбережения пересоздаём таймеры
    // с актуальными интервалами.
    PowerService.instance.addListener(_onPowerProfileChanged);

    final autoConnect = await _storage.getSetting('autoConnect', true);
    if (autoConnect) {
      final defaultConnection = await _storage.getDefaultConnection();
      if (defaultConnection != null) {
        log.i(_tag, 'Auto-connecting to ${defaultConnection.name}');
        connect(defaultConnection);
      }
    }

    notifyListeners();
  }

  void _onPowerProfileChanged() {
    if (!isConnected) return;
    log.d(_tag,
        'Power profile changed → restarting timers (saving=${PowerService.instance.isPowerSaving})');
    _startStatusTimer();
    if (_statsSnapshotTimer != null) {
      _statsSnapshotTimer?.cancel();
      _statsSnapshotTimer = null;
      _startStatsSnapshotTimer();
    }
  }

  Future<bool> connect(OBSConnection connection,
      {bool isReconnect = false}) async {
    log.i(_tag, 'Connecting to ${connection.name} (${connection.host}:${connection.port})');
    if (_isConnecting) return false;

    if (!isReconnect) {
      _reconnectAttempt = 0;
    }
    _manualDisconnect = false;
    _isConnecting = true;
    _connectionError = null;
    _currentConnection = connection;
    notifyListeners();

    try {
      final success = await _obsService.connect(connection);
      if (!success) {
        _connectionError = 'Не удалось подключиться';
        log.w(_tag, 'Connection failed to ${connection.name}');
      }
      return success;
    } catch (e) {
      _connectionError = e.toString();
      log.e(_tag, 'Connection error', e.toString());
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectCountdownTimer?.cancel();
    _reconnectAttempt = 0;
    _consecutiveSyncFailures = 0;
    _forceDisconnectInProgress = false;
    await _obsService.disconnect();
    await _foregroundService.stop();
    _statusTimer?.cancel();
    _localTimeTimer?.cancel();
    _status = OBSStatus();
    _scenes = [];
    _currentSceneItems = [];
    _audioSources = [];
    _localStreamDuration = Duration.zero;
    _localRecordDuration = Duration.zero;
    _streamStartTime = null;
    _recordStartTime = null;
    _recordPauseTime = null;
    _recordPausedDuration = Duration.zero;
    log.i(_tag, 'Disconnected manually');
    notifyListeners();
  }

  void _onConnected() async {
    log.i(_tag, 'Connected successfully');
    _status = _status.copyWith(isConnected: true);
    _connectionError = null;
    _reconnectTimer?.cancel();
    _reconnectCountdownTimer?.cancel();
    _reconnectAttempt = 0;
    _consecutiveSyncFailures = 0;
    _forceDisconnectInProgress = false;

    if (_currentConnection != null) {
      final updated =
          _currentConnection!.copyWith(lastConnected: DateTime.now());
      await _storage.updateConnection(updated);
      _currentConnection = updated;
      _connections = await _storage.getConnections();
    }

    await _fetchInitialData();

    await _foregroundService.start();
    _foregroundService
        .sendStatus('Подключено к ${_currentConnection?.name ?? "OBS"}');

    _startStatusTimer();

    notifyListeners();
  }

  void _onDisconnected(String reason) {
    log.w(_tag, 'Disconnected: $reason');
    _status = _status.copyWith(isConnected: false);
    _connectionError = reason;
    _statusTimer?.cancel();
    _localTimeTimer?.cancel();
    _foregroundService.sendStatus('Отключено');
    notifyListeners();

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _currentConnection == null) return;

    _reconnectTimer?.cancel();
    _reconnectCountdownTimer?.cancel();
    _reconnectAttempt++;

    if (_reconnectAttempt > _maxReconnectAttempts) {
      log.w(_tag,
          'Auto-reconnect: max attempts ($_maxReconnectAttempts) reached, giving up');
      _connectionError =
          'Не удалось переподключиться после $_maxReconnectAttempts попыток. Проверьте OBS и попробуйте снова.';
      _reconnectAttempt = 0;
      _foregroundService.sendStatus('Переподключение остановлено');
      notifyListeners();
      return;
    }

    final delaySec = (3 * (1 << (_reconnectAttempt - 1).clamp(0, 3))).clamp(3, 30);
    log.i(_tag,
        'Auto-reconnect attempt $_reconnectAttempt/$_maxReconnectAttempts in ${delaySec}s');

    int remaining = delaySec;
    _connectionError =
        'Переподключение через $remainingс... (попытка $_reconnectAttempt/$_maxReconnectAttempts)';
    notifyListeners();

    _reconnectCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      if (remaining <= 0 || _manualDisconnect || isConnected) {
        timer.cancel();
        return;
      }
      _connectionError =
          'Переподключение через $remainingс... (попытка $_reconnectAttempt/$_maxReconnectAttempts)';
      notifyListeners();
    });

    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      _reconnectCountdownTimer?.cancel();
      if (_manualDisconnect || isConnected) return;

      _connectionError = 'Подключение...';
      notifyListeners();

      log.i(_tag, 'Auto-reconnect: trying...');
      final success = await connect(_currentConnection!, isReconnect: true);
      if (!success && !_manualDisconnect) {
        _scheduleReconnect();
      }
    });
  }

  void cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectCountdownTimer?.cancel();
    _reconnectAttempt = 0;
  }

  // ==================== Health-check ====================

  /// Регистрирует успешный обмен с OBS — сбрасывает счётчик неудач.
  void _onSyncSuccess() {
    if (_consecutiveSyncFailures > 0) {
      log.d(_tag, 'Sync recovered after $_consecutiveSyncFailures failures');
      _consecutiveSyncFailures = 0;
    }
  }

  /// Регистрирует неудачу обмена с OBS. При $_maxSyncFailures подряд
  /// форсирует disconnect (TCP мог зависнуть, ответов нет).
  void _onSyncFailure(String reason) {
    if (!isConnected || _forceDisconnectInProgress) return;
    _consecutiveSyncFailures++;
    log.w(_tag,
        'Sync failure #$_consecutiveSyncFailures/$_maxSyncFailures: $reason');
    if (_consecutiveSyncFailures >= _maxSyncFailures) {
      _forceDisconnect('OBS не отвечает');
    }
  }

  /// Принудительно закрывает соединение, считая его «фантомным».
  /// Срабатывает onDisconnected → автоматический реконнект.
  void _forceDisconnect(String reason) {
    if (_forceDisconnectInProgress) return;
    _forceDisconnectInProgress = true;
    _consecutiveSyncFailures = 0;
    log.w(_tag, 'Forcing disconnect: $reason');
    _connectionError = reason;
    _obsService.disconnect();
  }

  /// Через [delayMs] выполняет [verify]. Используется для post-action
  /// подтверждения от OBS — если оно не пришло вовремя или не совпало,
  /// откатывает оптимистичное обновление UI и одновременно работает
  /// как health-check.
  void _verifyAfter(
    String tag,
    Future<void> Function() verify, {
    int delayMs = 300,
  }) {
    Timer(Duration(milliseconds: delayMs), () async {
      if (!isConnected || _manualDisconnect || _forceDisconnectInProgress) {
        return;
      }
      try {
        await verify();
        _onSyncSuccess();
      } on TimeoutException {
        _onSyncFailure('verify timeout [$tag]');
      } catch (e) {
        // Ошибки на уровне OBS (result=false) не считаем сетевыми проблемами.
        log.w(_tag, 'Post-action verify [$tag] error', e.toString());
      }
    });
  }

  void _onError(String error) {
    log.e(_tag, 'Error: $error');
    _connectionError = error;
    notifyListeners();
  }

  void _handleEvent(String eventType, Map<String, dynamic> data) {
    switch (eventType) {
      case 'CurrentProgramSceneChanged':
        final sceneName = data['sceneName'] as String?;
        log.d(_tag, 'Scene changed: $sceneName');
        _updateCurrentScene(sceneName);
        break;
      case 'SceneListChanged':
        log.d(_tag, 'Scene list changed');
        _fetchScenes();
        break;
      case 'SceneItemEnableStateChanged':
        final sceneName = data['sceneName'] as String?;
        final sceneItemId = data['sceneItemId'] as int?;
        final enabled = data['sceneItemEnabled'] as bool?;
        if (sceneName != null && sceneItemId != null && enabled != null) {
          _updateSceneItemLocally(sceneName, sceneItemId, enabled);
        }
        break;
      case 'StreamStateChanged':
        _handleStreamStateChanged(data);
        break;
      case 'RecordStateChanged':
        _handleRecordStateChanged(data);
        break;
      case 'InputMuteStateChanged':
        final inputName = data['inputName'] as String?;
        final muted = data['inputMuted'] as bool?;
        if (inputName != null && muted != null) {
          _updateAudioMute(inputName, muted);
        }
        break;
      case 'InputVolumeChanged':
        final inputName = data['inputName'] as String?;
        final volumeMul = (data['inputVolumeMul'] as num?)?.toDouble();
        if (inputName != null && volumeMul != null) {
          final sliderValue = volumeMul > 0 ? pow(volumeMul, 0.25).toDouble() : 0.0;
          _updateAudioVolume(inputName, sliderValue);
        }
        break;
      case 'ReplayBufferStateChanged':
        _handleReplayBufferStateChanged(data);
        break;
      case 'InputVolumeMeters':
        _handleVolumeMeterEvent(data);
        break;
    }
  }

  Future<void> _fetchInitialData() async {
    log.i(_tag, 'Fetching initial data...');
    try {
      final version = await _obsService.getVersion();
      log.i(_tag, 'OBS v${version['obsVersion']}, WS v${version['obsWebSocketVersion']}');
      _status = _status.copyWith(
        obsVersion: version['obsVersion'] as String?,
        websocketVersion: version['obsWebSocketVersion'] as String?,
      );

      await _fetchScenes();
      await _syncStatusFromOBS();
      await _fetchAudioSources();

      notifyListeners();
    } catch (e) {
      log.e(_tag, 'Error fetching initial data', e.toString());
    }
  }

  Future<void> fullSync(void Function(double progress, String stage)? onProgress) async {
    if (!isConnected) return;
    log.i(_tag, 'Starting full sync...');

    onProgress?.call(0.0, 'Версия OBS');
    try {
      final version = await _obsService.getVersion();
      _status = _status.copyWith(
        obsVersion: version['obsVersion'] as String?,
        websocketVersion: version['obsWebSocketVersion'] as String?,
      );
      _onSyncSuccess();
    } on TimeoutException catch (e) {
      // Первый запрос упал с timeout — соединение фантомное.
      // Прерываем синхронизацию и форсируем disconnect.
      log.e(_tag, 'Sync error (version) timeout', e.toString());
      _onSyncFailure('fullSync version timeout');
      _forceDisconnect('OBS не отвечает');
      onProgress?.call(1.0, 'Не удалось синхронизироваться');
      return;
    } catch (e) {
      log.e(_tag, 'Sync error (version)', e.toString());
    }

    onProgress?.call(0.15, 'Сцены');
    await _fetchScenes();

    onProgress?.call(0.35, 'Источники сцен');
    await _loadAllSceneItems();

    onProgress?.call(0.55, 'Аудио');
    await _fetchAudioSources();

    onProgress?.call(0.75, 'Стрим и запись');
    await _syncStatusFromOBS();

    onProgress?.call(0.90, 'Статистика');
    try {
      final statsData = await _obsService.getStats();
      _stats = OBSStats.fromJson(statsData);
    } catch (e) {
      log.e(_tag, 'Sync error (stats)', e.toString());
    }

    onProgress?.call(1.0, 'Готово');
    log.i(_tag, 'Full sync completed');
    notifyListeners();
  }

  Future<void> _fetchScenes() async {
    try {
      _scenes = await _obsService.getSceneList();
      notifyListeners();

      final currentScene = _scenes.firstWhere(
        (s) => s.isCurrentProgram,
        orElse: () =>
            _scenes.isNotEmpty ? _scenes.first : throw Exception('No scenes'),
      );
      await _fetchSceneItems(currentScene.name);

      await _loadAllSceneItems();
    } catch (e) {
      log.e(_tag, 'Error fetching scenes', e.toString());
    }
  }

  Future<void> _fetchSceneItems(String sceneName) async {
    try {
      final items = await _obsService.getSceneItemList(sceneName);
      _currentSceneItems = items;
      _allSceneItems[sceneName] = items;
      notifyListeners();
    } catch (e) {
      log.e(_tag, 'Error fetching scene items for $sceneName', e.toString());
    }
  }

  Future<void> _loadAllSceneItems() async {
    for (final scene in _scenes) {
      if (!_allSceneItems.containsKey(scene.name)) {
        try {
          final items = await _obsService.getSceneItemList(scene.name);
          _allSceneItems[scene.name] = items;
        } catch (e) {
          log.w(_tag, 'Error loading items for ${scene.name}', e.toString());
        }
      }
    }
    notifyListeners();
  }

  void _updateSceneItemLocally(
      String sceneName, int sceneItemId, bool enabled) {
    final items = _allSceneItems[sceneName];
    if (items != null) {
      final index = items.indexWhere((i) => i.sceneItemId == sceneItemId);
      if (index != -1) {
        _allSceneItems[sceneName]![index] =
            items[index].copyWith(isVisible: enabled);
      }
    }

    final currentIndex =
        _currentSceneItems.indexWhere((i) => i.sceneItemId == sceneItemId);
    if (currentIndex != -1) {
      _currentSceneItems[currentIndex] =
          _currentSceneItems[currentIndex].copyWith(isVisible: enabled);
    }

    notifyListeners();
  }

  bool? getSceneItemEnabled(String sceneName, int sceneItemId) {
    final items = _allSceneItems[sceneName];
    if (items == null) return null;
    final item = items.cast<OBSSceneItem?>().firstWhere(
          (i) => i?.sceneItemId == sceneItemId,
          orElse: () => null,
        );
    return item?.isVisible;
  }

  Future<void> loadSceneItems(String sceneName) async {
    _selectedSceneForItems = sceneName;
    await _fetchSceneItems(sceneName);
  }

  Future<void> _fetchAudioSources() async {
    try {
      _audioSources = await _obsService.getInputList();

      // Для каждого аудио-источника инициализируем моно-канал [0.0], если
      // данных ещё нет. Это даёт VolumeMeter виджету «канал есть, уровень 0»
      // — он сразу рисует пустую полоску, а не невидимый SizedBox.
      // OBS не всегда шлёт InputVolumeMeters для неактивных в сцене
      // источников или шлёт пустой inputLevelsMul, и без этой инициализации
      // полоска у таких источников никогда не появилась бы.
      final currentNames = _audioSources.map((s) => s.name).toSet();
      bool changed = false;
      for (final name in currentNames) {
        if (!_volumeLevels.containsKey(name)) {
          _volumeLevels[name] = [0.0];
          changed = true;
        }
      }
      // Чистим мёртвые источники, которых больше нет
      for (final name in _volumeLevels.keys.toList()) {
        if (!currentNames.contains(name)) {
          _volumeLevels.remove(name);
          changed = true;
        }
      }
      if (changed && _volumeListenerCount > 0) {
        _volumeController.add(Map.from(_volumeLevels));
      }

      notifyListeners();
    } catch (e) {
      log.e(_tag, 'Error fetching audio sources', e.toString());
    }
  }

  void _updateCurrentScene(String? sceneName) {
    if (sceneName == null) return;

    _scenes = _scenes
        .map((s) => s.copyWith(
              isCurrentProgram: s.name == sceneName,
            ))
        .toList();

    _fetchSceneItems(sceneName);
    notifyListeners();
  }

  void _updateAudioMute(String inputName, bool muted) {
    final index = _audioSources.indexWhere((s) => s.name == inputName);
    if (index != -1) {
      _audioSources[index] = _audioSources[index].copyWith(isMuted: muted);
      notifyListeners();
    }
  }

  void _updateAudioVolume(String inputName, double volume) {
    final index = _audioSources.indexWhere((s) => s.name == inputName);
    if (index != -1) {
      _audioSources[index] = _audioSources[index].copyWith(volume: volume);
      notifyListeners();
    }
  }

  void _handleStreamStateChanged(Map<String, dynamic> data) {
    final outputState = data['outputState'] as String?;
    log.i(_tag, 'Stream state: $outputState');

    switch (outputState) {
      case 'OBS_WEBSOCKET_OUTPUT_STARTED':
        _streamStartTime = DateTime.now();
        _localStreamDuration = Duration.zero;
        _status = _status.copyWith(
          streamStatus:
              OBSOutputStatus(isActive: true, duration: Duration.zero),
        );
        StatsHistoryService.instance.onStreamStarted();
        _startStatsSnapshotTimer();
        break;
      case 'OBS_WEBSOCKET_OUTPUT_STOPPED':
        _streamStartTime = null;
        _localStreamDuration = Duration.zero;
        _status = _status.copyWith(
          streamStatus: OBSOutputStatus(isActive: false),
        );
        StatsHistoryService.instance.onStreamStopped();
        _stopStatsSnapshotTimerIfIdle();
        break;
    }
    notifyListeners();
    _updateForegroundNotification();
  }

  void _handleRecordStateChanged(Map<String, dynamic> data) {
    final outputState = data['outputState'] as String?;
    log.i(_tag, 'Record state: $outputState');

    switch (outputState) {
      case 'OBS_WEBSOCKET_OUTPUT_STARTED':
        _recordStartTime = DateTime.now();
        _localRecordDuration = Duration.zero;
        _recordPausedDuration = Duration.zero;
        _recordPauseTime = null;
        _status = _status.copyWith(
          recordStatus:
              OBSOutputStatus(isActive: true, duration: Duration.zero),
        );
        StatsHistoryService.instance.onRecordStarted();
        _startStatsSnapshotTimer();
        break;
      case 'OBS_WEBSOCKET_OUTPUT_STOPPED':
        _recordStartTime = null;
        _localRecordDuration = Duration.zero;
        _recordPausedDuration = Duration.zero;
        _recordPauseTime = null;
        _status = _status.copyWith(
          recordStatus: OBSOutputStatus(isActive: false),
        );
        StatsHistoryService.instance.onRecordStopped();
        _stopStatsSnapshotTimerIfIdle();
        break;
      case 'OBS_WEBSOCKET_OUTPUT_PAUSED':
        if (_status.recordStatus.isPaused) return;
        _recordPauseTime = DateTime.now();
        _status = _status.copyWith(
          recordStatus: OBSOutputStatus(
            isActive: true,
            isPaused: true,
            duration: _localRecordDuration,
          ),
        );
        break;
      case 'OBS_WEBSOCKET_OUTPUT_RESUMED':
        if (!_status.recordStatus.isPaused) return;
        if (_recordPauseTime != null) {
          _recordPausedDuration += DateTime.now().difference(_recordPauseTime!);
          _recordPauseTime = null;
        }
        _status = _status.copyWith(
          recordStatus: OBSOutputStatus(
            isActive: true,
            isPaused: false,
            duration: _localRecordDuration,
          ),
        );
        break;
    }
    notifyListeners();
    _updateForegroundNotification();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _localTimeTimer?.cancel();

    // При активном энергосбережении — реже опрашиваем OBS.
    final saving = PowerService.instance.isPowerSaving;
    final statusInterval = Duration(seconds: saving ? 10 : 5);

    _statusTimer = Timer.periodic(statusInterval, (_) {
      if (isConnected) {
        _syncStatusFromOBS();
      }
    });

    _localTimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isConnected) {
        _updateLocalTime();
      }
    });
  }

  void _updateLocalTime() {
    bool changed = false;

    if (_status.streamStatus.isActive && _streamStartTime != null) {
      _localStreamDuration = DateTime.now().difference(_streamStartTime!);
      changed = true;
    }

    if (_status.recordStatus.isActive && _recordStartTime != null) {
      if (_status.recordStatus.isPaused) {
        // На паузе — время не увеличивается
      } else {
        final totalElapsed = DateTime.now().difference(_recordStartTime!);
        _localRecordDuration = totalElapsed - _recordPausedDuration;
        changed = true;
      }
    }

    if (changed) {
      _status = _status.copyWith(
        streamStatus: _status.streamStatus.isActive
            ? OBSOutputStatus(
                isActive: true,
                isPaused: _status.streamStatus.isPaused,
                duration: _localStreamDuration,
              )
            : _status.streamStatus,
        recordStatus: _status.recordStatus.isActive
            ? OBSOutputStatus(
                isActive: true,
                isPaused: _status.recordStatus.isPaused,
                duration: _localRecordDuration,
              )
            : _status.recordStatus,
      );
      notifyListeners();
      _updateForegroundNotification();
    }
  }

  Future<void> _syncStatusFromOBS() async {
    try {
      final streamStatus = await _obsService.getStreamStatus();
      final recordStatus = await _obsService.getRecordStatus();

      if (streamStatus.isActive != _status.streamStatus.isActive) {
        if (streamStatus.isActive && !_status.streamStatus.isActive) {
          _streamStartTime =
              DateTime.now().subtract(streamStatus.duration ?? Duration.zero);
          _localStreamDuration = streamStatus.duration ?? Duration.zero;
        } else if (!streamStatus.isActive) {
          _streamStartTime = null;
          _localStreamDuration = Duration.zero;
        }
      }

      if (recordStatus.isActive != _status.recordStatus.isActive) {
        if (recordStatus.isActive && !_status.recordStatus.isActive) {
          _recordStartTime =
              DateTime.now().subtract(recordStatus.duration ?? Duration.zero);
          _localRecordDuration = recordStatus.duration ?? Duration.zero;
          _recordPausedDuration = Duration.zero;
          _recordPauseTime = null;
        } else if (!recordStatus.isActive) {
          _recordStartTime = null;
          _localRecordDuration = Duration.zero;
          _recordPausedDuration = Duration.zero;
          _recordPauseTime = null;
        }
      }

      if (recordStatus.isPaused != _status.recordStatus.isPaused) {
        if (recordStatus.isPaused && !_status.recordStatus.isPaused) {
          _recordPauseTime = DateTime.now();
        } else if (!recordStatus.isPaused && _status.recordStatus.isPaused) {
          if (_recordPauseTime != null) {
            _recordPausedDuration +=
                DateTime.now().difference(_recordPauseTime!);
            _recordPauseTime = null;
          }
        }
      }

      _status = _status.copyWith(
        streamStatus: OBSOutputStatus(
          isActive: streamStatus.isActive,
          isPaused: streamStatus.isPaused,
          duration: _localStreamDuration,
        ),
        recordStatus: OBSOutputStatus(
          isActive: recordStatus.isActive,
          isPaused: recordStatus.isPaused,
          duration: _localRecordDuration,
        ),
      );

      try {
        final replayActive = await _obsService.getReplayBufferStatus();
        if (replayActive != _status.replayBufferActive) {
          _status = _status.copyWith(replayBufferActive: replayActive);
        }
      } catch (_) {
        // Replay Buffer может быть не настроен
      }

      try {
        final statsData = await _obsService.getStats();
        _stats = OBSStats.fromJson(statsData);
      } catch (e) {
        log.w(_tag, 'Error fetching stats', e.toString());
      }

      // Основные запросы (stream/record status) прошли — соединение живое.
      _onSyncSuccess();
    } on TimeoutException catch (e) {
      log.w(_tag, 'Sync status timeout', e.toString());
      _onSyncFailure('status timeout');
    } catch (e) {
      log.w(_tag, 'Error syncing status', e.toString());
      // Не сетевая ошибка (например, OBS вернул result=false) — не трогаем
      // счётчик, чтобы случайные отказы не приводили к ложному disconnect.
    }
  }

  void _updateForegroundNotification() {
    if (!isConnected) return;

    final parts = <String>[];

    if (_status.streamStatus.isActive) {
      parts.add('🔴 Стрим: ${_status.streamStatus.durationString}');
    }

    if (_status.recordStatus.isActive) {
      final pauseIcon = _status.recordStatus.isPaused ? '⏸' : '⏺';
      parts.add('$pauseIcon Запись: ${_status.recordStatus.durationString}');
    }

    if (parts.isEmpty) {
      parts.add('Подключено к ${_currentConnection?.name ?? "OBS"}');
    }

    _foregroundService.sendStatus(parts.join(' | '));
  }

  // ==================== Действия ====================

  Future<void> switchScene(String sceneName) async {
    if (!isConnected) return;
    log.d(_tag, 'Switching to scene: $sceneName');

    _scenes = _scenes
        .map((s) => s.copyWith(
              isCurrentProgram: s.name == sceneName,
            ))
        .toList();
    notifyListeners();

    _obsService.setCurrentProgramScene(sceneName).catchError((e) {
      log.e(_tag, 'Error switching scene', e.toString());
    });

    // Подтверждение от OBS — корректирует UI, если событие
    // CurrentProgramSceneChanged не пришло.
    _verifyAfter('scene', () async {
      final actual = await _obsService.getCurrentProgramScene();
      if (actual != null && actual != sceneName) {
        log.w(_tag,
            'Scene mismatch: ui=$sceneName, obs=$actual — correcting');
        _updateCurrentScene(actual);
      }
    });
  }

  Future<void> toggleSceneItem(
      String sceneName, int itemId, bool enabled) async {
    if (!isConnected) return;

    _updateSceneItemLocally(sceneName, itemId, enabled);

    _obsService.setSceneItemEnabled(sceneName, itemId, enabled).catchError((e) {
      log.e(_tag, 'Error toggling scene item', e.toString());
      _updateSceneItemLocally(sceneName, itemId, !enabled);
    });

    _verifyAfter('sceneItem:$sceneName/$itemId', () async {
      final actual = await _obsService.getSceneItemEnabled(sceneName, itemId);
      if (actual != null && actual != enabled) {
        log.w(_tag,
            'SceneItem $sceneName/$itemId mismatch: ui=$enabled, obs=$actual — correcting');
        _updateSceneItemLocally(sceneName, itemId, actual);
      }
    });
  }

  Future<void> toggleStream() async {
    if (!isConnected) return;

    final wasActive = _status.streamStatus.isActive;
    log.i(_tag, wasActive ? 'Stopping stream...' : 'Starting stream...');

    _status = _status.copyWith(
      streamStatus: OBSOutputStatus(isActive: !wasActive),
    );
    notifyListeners();

    _obsService.toggleStream().catchError((e) {
      log.e(_tag, 'Error toggling stream, rolling back', e.toString());
      _status = _status.copyWith(
        streamStatus: OBSOutputStatus(isActive: wasActive),
      );
      notifyListeners();
    });
  }

  Future<void> startStream() async {
    if (!isConnected) return;
    log.i(_tag, 'Starting stream...');

    _status = _status.copyWith(
      streamStatus: OBSOutputStatus(isActive: true),
    );
    notifyListeners();

    _obsService.startStream().catchError((e) {
      log.e(_tag, 'Error starting stream, rolling back', e.toString());
      _status = _status.copyWith(
        streamStatus: OBSOutputStatus(isActive: false),
      );
      notifyListeners();
    });
  }

  Future<void> stopStream() async {
    if (!isConnected) return;
    log.i(_tag, 'Stopping stream...');

    _status = _status.copyWith(
      streamStatus: OBSOutputStatus(isActive: false),
    );
    notifyListeners();

    _obsService.stopStream().catchError((e) {
      log.e(_tag, 'Error stopping stream, rolling back', e.toString());
      _status = _status.copyWith(
        streamStatus: OBSOutputStatus(isActive: true),
      );
      notifyListeners();
    });
  }

  Future<void> toggleRecord() async {
    if (!isConnected) return;

    final wasActive = _status.recordStatus.isActive;
    log.i(_tag, wasActive ? 'Stopping record...' : 'Starting record...');

    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(isActive: !wasActive),
    );
    notifyListeners();

    _obsService.toggleRecord().catchError((e) {
      log.e(_tag, 'Error toggling record, rolling back', e.toString());
      _status = _status.copyWith(
        recordStatus: OBSOutputStatus(isActive: wasActive),
      );
      notifyListeners();
    });
  }

  Future<void> startRecord() async {
    if (!isConnected) return;
    log.i(_tag, 'Starting record...');

    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(isActive: true),
    );
    notifyListeners();

    _obsService.startRecord().catchError((e) {
      log.e(_tag, 'Error starting record, rolling back', e.toString());
      _status = _status.copyWith(
        recordStatus: OBSOutputStatus(isActive: false),
      );
      notifyListeners();
    });
  }

  Future<void> stopRecord() async {
    if (!isConnected) return;
    log.i(_tag, 'Stopping record...');

    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(isActive: false),
    );
    notifyListeners();

    _obsService.stopRecord().catchError((e) {
      log.e(_tag, 'Error stopping record, rolling back', e.toString());
      _status = _status.copyWith(
        recordStatus: OBSOutputStatus(isActive: true),
      );
      notifyListeners();
    });
  }

  Future<void> pauseRecord() async {
    if (!isConnected) return;

    final now = DateTime.now();
    if (_lastRecordPauseAction != null &&
        now.difference(_lastRecordPauseAction!).inMilliseconds < 500) {
      return;
    }
    _lastRecordPauseAction = now;

    _recordPauseTime = DateTime.now();
    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(
        isActive: _status.recordStatus.isActive,
        isPaused: true,
        duration: _localRecordDuration,
      ),
    );
    notifyListeners();

    _obsService.pauseRecord().catchError((e) {
      log.e(_tag, 'Error pausing record', e.toString());
    });
  }

  Future<void> resumeRecord() async {
    if (!isConnected) return;

    final now = DateTime.now();
    if (_lastRecordPauseAction != null &&
        now.difference(_lastRecordPauseAction!).inMilliseconds < 500) {
      return;
    }
    _lastRecordPauseAction = now;

    if (_recordPauseTime != null) {
      _recordPausedDuration += DateTime.now().difference(_recordPauseTime!);
      _recordPauseTime = null;
    }
    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(
        isActive: _status.recordStatus.isActive,
        isPaused: false,
        duration: _localRecordDuration,
      ),
    );
    notifyListeners();

    _obsService.resumeRecord().catchError((e) {
      log.e(_tag, 'Error resuming record', e.toString());
    });
  }

  Future<void> toggleRecordPause() async {
    if (!isConnected) return;

    final now = DateTime.now();
    if (_lastRecordPauseAction != null &&
        now.difference(_lastRecordPauseAction!).inMilliseconds < 500) {
      return;
    }
    _lastRecordPauseAction = now;

    final wasPaused = _status.recordStatus.isPaused;

    if (wasPaused) {
      if (_recordPauseTime != null) {
        _recordPausedDuration += DateTime.now().difference(_recordPauseTime!);
        _recordPauseTime = null;
      }
    } else {
      _recordPauseTime = DateTime.now();
    }

    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(
        isActive: _status.recordStatus.isActive,
        isPaused: !wasPaused,
        duration: _localRecordDuration,
      ),
    );
    notifyListeners();

    _obsService.toggleRecordPause().catchError((e) {
      log.e(_tag, 'Error toggling record pause', e.toString());
    });
  }

  Future<void> toggleAudioMute(String inputName) async {
    if (!isConnected) return;

    final index = _audioSources.indexWhere((s) => s.name == inputName);
    if (index != -1) {
      final wasMuted = _audioSources[index].isMuted;
      _audioSources[index] = _audioSources[index].copyWith(isMuted: !wasMuted);
      notifyListeners();
    }

    _obsService.toggleInputMute(inputName).catchError((e) {
      log.e(_tag, 'Error toggling mute for $inputName', e.toString());
    });

    // Подтверждаем у OBS реальное состояние через 300мс — на случай, если
    // событие InputMuteStateChanged не пришло (рассинхрон).
    _verifyAfter('mute:$inputName', () async {
      final actual = await _obsService.getInputMute(inputName);
      if (actual == null) return;
      final i = _audioSources.indexWhere((s) => s.name == inputName);
      if (i != -1 && _audioSources[i].isMuted != actual) {
        log.w(_tag,
            'Mute state mismatch for $inputName: ui=${_audioSources[i].isMuted}, obs=$actual — correcting');
        _updateAudioMute(inputName, actual);
      }
    });
  }

  Future<void> setAudioVolume(String inputName, double volume) async {
    if (!isConnected) return;
    await _obsService.setInputVolume(inputName, volume);
  }

  Future<void> toggleVirtualCam() async {
    if (!isConnected) return;
    log.i(_tag, 'Toggling virtual cam');
    await _obsService.toggleVirtualCam();
  }

  Future<void> toggleStudioMode() async {
    if (!isConnected) return;
    final currentState = _status.studioModeEnabled;
    log.i(_tag, 'Toggling studio mode: ${!currentState}');
    await _obsService.setStudioModeEnabled(!currentState);
    _status = _status.copyWith(studioModeEnabled: !currentState);
    notifyListeners();
  }

  Future<void> triggerHotkey(String hotkeyName) async {
    if (!isConnected) return;
    log.d(_tag, 'Triggering hotkey: $hotkeyName');
    try {
      await _obsService.triggerHotkeyByName(hotkeyName);
    } catch (e) {
      log.e(_tag, 'Error triggering hotkey', e.toString());
    }
  }

  Future<List<String>> getHotkeys() async {
    if (!isConnected) return [];
    try {
      return await _obsService.getHotkeyList();
    } catch (e) {
      log.e(_tag, 'Error getting hotkeys', e.toString());
      return [];
    }
  }

  Future<String?> saveScreenshot({String? sourceName}) async {
    if (!isConnected) return null;
    try {
      final source = sourceName ??
          _scenes
              .firstWhere(
                (s) => s.isCurrentProgram,
                orElse: () => _scenes.first,
              )
              .name;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '/storage/emulated/0/Pictures/OBS_Screenshot_$timestamp.png';

      await _obsService.saveSourceScreenshot(
        sourceName: source,
        imageFilePath: path,
      );

      log.i(_tag, 'Screenshot saved: $path');
      return path;
    } catch (e) {
      log.e(_tag, 'Error saving screenshot', e.toString());
      return null;
    }
  }

  Future<void> saveReplayBuffer() async {
    if (!isConnected) return;
    try {
      await _obsService.saveReplayBuffer();
      log.i(_tag, 'Replay buffer saved');
    } catch (e) {
      log.e(_tag, 'Error saving replay buffer', e.toString());
    }
  }

  Future<void> startReplayBuffer() async {
    if (!isConnected) return;
    try {
      await _obsService.startReplayBuffer();
      _status = _status.copyWith(replayBufferActive: true);
      log.i(_tag, 'Replay buffer started');
      notifyListeners();
    } catch (e) {
      log.e(_tag, 'Error starting replay buffer', e.toString());
    }
  }

  Future<void> stopReplayBuffer() async {
    if (!isConnected) return;
    try {
      await _obsService.stopReplayBuffer();
      _status = _status.copyWith(replayBufferActive: false);
      log.i(_tag, 'Replay buffer stopped');
      notifyListeners();
    } catch (e) {
      log.e(_tag, 'Error stopping replay buffer', e.toString());
    }
  }

  Future<void> toggleReplayBuffer() async {
    if (!isConnected) return;
    try {
      final isActive = await _obsService.getReplayBufferStatus();
      if (isActive) {
        await _obsService.stopReplayBuffer();
      } else {
        await _obsService.startReplayBuffer();
      }
      notifyListeners();
    } catch (e) {
      log.e(_tag, 'Error toggling replay buffer', e.toString());
    }
  }

  void _handleVolumeMeterEvent(Map<String, dynamic> data) {
    if (_volumeListenerCount <= 0) return;

    final inputs = data['inputs'] as List?;
    if (inputs == null) return;

    final activeNames = <String>{};

    for (final input in inputs) {
      final name = input['inputName'] as String?;
      final levels = input['inputLevelsMul'] as List?;
      if (name == null || levels == null) continue;

      activeNames.add(name);
      final channelPeaks = <double>[];
      for (final channel in levels) {
        if (channel is List && channel.length >= 3) {
          // [0]=magnitude, [1]=peak (post-fader), [2]=inputPeak (pre-fader)
          final peak = (channel[1] as num).toDouble();
          channelPeaks.add(peak > 0 ? pow(peak, 0.25).toDouble() : 0.0);
        }
      }
      // Если OBS прислал пустой inputLevelsMul — источник «есть, но молчит»
      // (часто бывает для глобальных аудио или неактивных в сцене).
      // Сохраняем хотя бы моно-канал [0.0], чтобы полоска оставалась видимой.
      if (channelPeaks.isEmpty) {
        _volumeLevels[name] = _volumeLevels[name]?.isNotEmpty == true
            ? List.filled(_volumeLevels[name]!.length, 0.0)
            : [0.0];
      } else {
        _volumeLevels[name] = channelPeaks;
      }
    }

    // Источники, которых не было в этом батче, тоже считаем молчащими, но
    // не убираем — полоска должна оставаться видимой.
    for (final name in _volumeLevels.keys.toList()) {
      if (!activeNames.contains(name)) {
        final existing = _volumeLevels[name];
        if (existing != null && existing.isNotEmpty) {
          _volumeLevels[name] = List.filled(existing.length, 0.0);
        } else {
          _volumeLevels[name] = [0.0];
        }
      }
    }

    _volumeController.add(Map.from(_volumeLevels));
  }

  void _startStatsSnapshotTimer() {
    if (_statsSnapshotTimer != null) return;
    final saving = PowerService.instance.isPowerSaving;
    final interval = Duration(
      seconds: saving ? kSnapshotIntervalSeconds * 3 : kSnapshotIntervalSeconds,
    );
    _statsSnapshotTimer = Timer.periodic(
      interval,
      (_) => _collectStatsSnapshot(),
    );
  }

  void _stopStatsSnapshotTimerIfIdle() {
    if (!StatsHistoryService.instance.isCollecting) {
      _statsSnapshotTimer?.cancel();
      _statsSnapshotTimer = null;
    }
  }

  void _collectStatsSnapshot() {
    if (!isConnected) return;
    StatsHistoryService.instance.addSnapshot(
      fps: _stats.activeFps,
      cpuUsage: _stats.cpuUsage,
      memoryUsage: _stats.memoryUsage,
      renderSkippedFrames: _stats.renderSkippedFrames,
      outputSkippedFrames: _stats.outputSkippedFrames,
    );
  }

  void _handleReplayBufferStateChanged(Map<String, dynamic> data) {
    final outputState = data['outputState'] as String?;
    log.d(_tag, 'Replay buffer state: $outputState');

    switch (outputState) {
      case 'OBS_WEBSOCKET_OUTPUT_STARTED':
        _status = _status.copyWith(replayBufferActive: true);
        break;
      case 'OBS_WEBSOCKET_OUTPUT_STOPPED':
        _status = _status.copyWith(replayBufferActive: false);
        break;
    }
    notifyListeners();
  }

  // ==================== Управление подключениями ====================

  Future<void> loadConnections() async {
    _connections = await _storage.getConnections();
    notifyListeners();
  }

  Future<OBSConnection> addConnection(OBSConnection connection) async {
    final saved = await _storage.addConnection(connection);
    await loadConnections();
    return saved;
  }

  Future<void> updateConnection(OBSConnection connection) async {
    await _storage.updateConnection(connection);
    await loadConnections();
  }

  Future<void> deleteConnection(String id) async {
    await _storage.deleteConnection(id);
    await loadConnections();
  }

  Future<void> setDefaultConnection(String id) async {
    await _storage.setDefaultConnection(id);
    await loadConnections();
  }

  // ==================== Настройки приложения ====================

  Future<bool> getAutoConnect() async {
    return await _storage.getSetting('autoConnect', true);
  }

  Future<void> setAutoConnect(bool value) async {
    await _storage.setSetting('autoConnect', value);
    notifyListeners();
  }

  // ==================== Превью сцены ====================

  Future<String?> getScenePreview(String sceneName, {int? width, int? quality}) async {
    if (!isConnected) return null;
    try {
      return await _obsService.getSourceScreenshotBase64(
        sourceName: sceneName,
        imageWidth: width ?? 480,
        imageCompressionQuality: quality ?? 30,
      );
    } catch (e) {
      // Не логируем — слишком частый вызов (30fps)
      return null;
    }
  }

  // ==================== Напоминания о стриме ====================

  void startStreamReminders(int intervalMinutes, String message) {
    _reminderTimer?.cancel();

    if (intervalMinutes <= 0) return;

    _reminderTimer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) {
        if (_status.streamStatus.isActive) {
          final duration = _status.streamStatus.durationString;
          onReminder?.call('$message (Стрим: $duration)');
        }
      },
    );
  }

  void stopStreamReminders() {
    _reminderTimer?.cancel();
    _reminderTimer = null;
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _localTimeTimer?.cancel();
    _debounceTimer?.cancel();
    _reminderTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectCountdownTimer?.cancel();
    _statsSnapshotTimer?.cancel();
    PowerService.instance.removeListener(_onPowerProfileChanged);
    _volumeController.close();
    _obsService.dispose();
    super.dispose();
  }
}
