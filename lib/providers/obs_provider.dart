import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

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
  String? _selectedSceneForItems; // Выбранная сцена для просмотра источников

  // Кэш items для всех сцен (для Quick Control)
  final Map<String, List<OBSSceneItem>> _allSceneItems = {};

  Timer? _statusTimer;
  Timer? _localTimeTimer; // Таймер для локального счётчика времени
  Timer? _debounceTimer; // Debounce для группировки частых событий

  // Локальные счётчики времени (обновляются каждую секунду на устройстве)
  Duration _localStreamDuration = Duration.zero;
  Duration _localRecordDuration = Duration.zero;
  DateTime? _streamStartTime;
  DateTime? _recordStartTime;
  DateTime? _recordPauseTime; // Когда была поставлена пауза
  Duration _recordPausedDuration = Duration.zero; // Суммарное время паузы

  // Флаг блокировки от быстрых повторных нажатий
  DateTime? _lastRecordPauseAction;

  OBSProvider(this._storage) {
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

  Future<void> _init() async {
    await _foregroundService.init();
    _connections = await _storage.getConnections();

    _obsService.onConnected = _onConnected;
    _obsService.onDisconnected = _onDisconnected;
    _obsService.onError = _onError;
    _obsService.onEvent = _handleEvent;

    final autoConnect = await _storage.getSetting('autoConnect', true);
    if (autoConnect) {
      final defaultConnection = await _storage.getDefaultConnection();
      if (defaultConnection != null) {
        connect(defaultConnection);
      }
    }

    notifyListeners();
  }

  Future<bool> connect(OBSConnection connection) async {
    debugPrint('=== НАЧАЛО ПОДКЛЮЧЕНИЯ ===');
    debugPrint('Connection: ${connection.host}:${connection.port}');
    debugPrint('Has password: ${connection.password != null}');
    if (_isConnecting) return false;

    _isConnecting = true;
    _connectionError = null;
    _currentConnection = connection;
    notifyListeners();

    try {
      final success = await _obsService.connect(connection);
      if (!success) {
        _connectionError = 'Не удалось подключиться';
      }
      return success;
    } catch (e) {
      _connectionError = e.toString();
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _obsService.disconnect();
    await _foregroundService.stop();
    _statusTimer?.cancel();
    _localTimeTimer?.cancel();
    _status = OBSStatus();
    _scenes = [];
    _currentSceneItems = [];
    _audioSources = [];
    // Сбрасываем локальные счётчики
    _localStreamDuration = Duration.zero;
    _localRecordDuration = Duration.zero;
    _streamStartTime = null;
    _recordStartTime = null;
    _recordPauseTime = null;
    _recordPausedDuration = Duration.zero;
    notifyListeners();
  }

  void _onConnected() async {
    debugPrint('=== ПОДКЛЮЧЕНИЕ УСПЕШНО ===');
    _status = _status.copyWith(isConnected: true);
    _connectionError = null;

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
    _status = _status.copyWith(isConnected: false);
    _connectionError = reason;
    _statusTimer?.cancel();
    _localTimeTimer?.cancel();
    _foregroundService.sendStatus('Отключено');
    notifyListeners();
  }

  void _onError(String error) {
    debugPrint('=== ОШИБКА ПОДКЛЮЧЕНИЯ: $error ===');
    debugPrint('OBS Error: $error');
    _connectionError = error;
    notifyListeners();
  }

  void _handleEvent(String eventType, Map<String, dynamic> data) {
    // Убраны частые debug логи для производительности
    switch (eventType) {
      case 'CurrentProgramSceneChanged':
        final sceneName = data['sceneName'] as String?;
        _updateCurrentScene(sceneName);
        break;
      case 'SceneListChanged':
        _fetchScenes();
        break;
      case 'SceneItemEnableStateChanged':
        final sceneName = data['sceneName'] as String?;
        final sceneItemId = data['sceneItemId'] as int?;
        final enabled = data['sceneItemEnabled'] as bool?;
        if (sceneName != null && sceneItemId != null && enabled != null) {
          // Быстрое локальное обновление без запроса к серверу
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
          // Конвертируем mul в позицию слайдера (mul^0.25)
          final sliderValue = volumeMul > 0 ? pow(volumeMul, 0.25).toDouble() : 0.0;
          _updateAudioVolume(inputName, sliderValue);
        }
        break;
      case 'ReplayBufferStateChanged':
        _handleReplayBufferStateChanged(data);
        break;
    }
  }

  Future<void> _fetchInitialData() async {
    debugPrint('Fetching initial data...');
    try {
      final version = await _obsService.getVersion();
      debugPrint('OBS Version: $version');
      _status = _status.copyWith(
        obsVersion: version['obsVersion'] as String?,
        websocketVersion: version['obsWebSocketVersion'] as String?,
      );

      await _fetchScenes();
      await _syncStatusFromOBS(); // Синхронизируем состояние стрима/записи
      await _fetchAudioSources();

      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching initial data: $e');
    }
  }

  Future<void> _fetchScenes() async {
    try {
      debugPrint('Fetching scenes...');
      _scenes = await _obsService.getSceneList();
      debugPrint('Scenes loaded: ${_scenes.map((s) => s.name).toList()}');
      notifyListeners();

      final currentScene = _scenes.firstWhere(
        (s) => s.isCurrentProgram,
        orElse: () =>
            _scenes.isNotEmpty ? _scenes.first : throw Exception('No scenes'),
      );
      await _fetchSceneItems(currentScene.name);

      // Загружаем items для всех сцен в кэш (для Quick Control)
      await _loadAllSceneItems();
    } catch (e) {
      debugPrint('Error fetching scenes: $e');
    }
  }

  Future<void> _fetchSceneItems(String sceneName) async {
    try {
      debugPrint('Fetching scene items for: $sceneName');
      final items = await _obsService.getSceneItemList(sceneName);
      _currentSceneItems = items;
      _allSceneItems[sceneName] = items; // Обновляем кэш
      debugPrint('Scene items loaded: ${_currentSceneItems.length}');
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching scene items: $e');
    }
  }

  /// Загрузка items для всех сцен в кэш
  Future<void> _loadAllSceneItems() async {
    for (final scene in _scenes) {
      if (!_allSceneItems.containsKey(scene.name)) {
        try {
          final items = await _obsService.getSceneItemList(scene.name);
          _allSceneItems[scene.name] = items;
          debugPrint('Scene items for ${scene.name}: ${items.length}');
        } catch (e) {
          debugPrint('Error loading items for ${scene.name}: $e');
        }
      }
    }
    notifyListeners();
  }

  /// Быстрое локальное обновление состояния item без запроса к серверу
  void _updateSceneItemLocally(
      String sceneName, int sceneItemId, bool enabled) {
    // Обновляем в кэше всех сцен
    final items = _allSceneItems[sceneName];
    if (items != null) {
      final index = items.indexWhere((i) => i.sceneItemId == sceneItemId);
      if (index != -1) {
        _allSceneItems[sceneName]![index] =
            items[index].copyWith(isVisible: enabled);
      }
    }

    // Обновляем в текущих items если это та же сцена
    final currentIndex =
        _currentSceneItems.indexWhere((i) => i.sceneItemId == sceneItemId);
    if (currentIndex != -1) {
      _currentSceneItems[currentIndex] =
          _currentSceneItems[currentIndex].copyWith(isVisible: enabled);
    }

    notifyListeners();
  }

  /// Получить состояние видимости источника в конкретной сцене
  bool? getSceneItemEnabled(String sceneName, int sceneItemId) {
    final items = _allSceneItems[sceneName];
    if (items == null) return null;
    final item = items.cast<OBSSceneItem?>().firstWhere(
          (i) => i?.sceneItemId == sceneItemId,
          orElse: () => null,
        );
    return item?.isVisible;
  }

  /// Публичный метод для загрузки источников выбранной сцены
  Future<void> loadSceneItems(String sceneName) async {
    _selectedSceneForItems = sceneName; // Запоминаем выбранную сцену
    await _fetchSceneItems(sceneName);
  }

  Future<void> _fetchAudioSources() async {
    try {
      debugPrint('Fetching audio sources...');
      _audioSources = await _obsService.getInputList();
      debugPrint('Audio sources loaded: ${_audioSources.length}');
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching audio sources: $e');
    }
  }

  void _updateCurrentScene(String? sceneName) {
    if (sceneName == null) return;
    debugPrint('Current scene changed to: $sceneName');

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

  /// Обработка события изменения состояния стрима
  void _handleStreamStateChanged(Map<String, dynamic> data) {
    final outputState = data['outputState'] as String?;
    debugPrint('Stream state changed: $outputState');

    switch (outputState) {
      case 'OBS_WEBSOCKET_OUTPUT_STARTED':
        _streamStartTime = DateTime.now();
        _localStreamDuration = Duration.zero;
        _status = _status.copyWith(
          streamStatus:
              OBSOutputStatus(isActive: true, duration: Duration.zero),
        );
        break;
      case 'OBS_WEBSOCKET_OUTPUT_STOPPED':
        _streamStartTime = null;
        _localStreamDuration = Duration.zero;
        _status = _status.copyWith(
          streamStatus: OBSOutputStatus(isActive: false),
        );
        break;
    }
    notifyListeners();
    _updateForegroundNotification();
  }

  /// Обработка события изменения состояния записи
  void _handleRecordStateChanged(Map<String, dynamic> data) {
    final outputState = data['outputState'] as String?;
    debugPrint('Record state changed: $outputState');

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
        break;
      case 'OBS_WEBSOCKET_OUTPUT_STOPPED':
        _recordStartTime = null;
        _localRecordDuration = Duration.zero;
        _recordPausedDuration = Duration.zero;
        _recordPauseTime = null;
        _status = _status.copyWith(
          recordStatus: OBSOutputStatus(isActive: false),
        );
        break;
      case 'OBS_WEBSOCKET_OUTPUT_PAUSED':
        // Игнорируем если уже на паузе (optimistic update уже установил)
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
        // Игнорируем если уже не на паузе (optimistic update уже установил)
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

    // Таймер для синхронизации состояния с OBS (каждые 5 сек)
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isConnected) {
        _syncStatusFromOBS();
      }
    });

    // Локальный таймер для обновления времени (каждую секунду)
    _localTimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isConnected) {
        _updateLocalTime();
      }
    });
  }

  /// Обновляет локальные счётчики времени каждую секунду
  void _updateLocalTime() {
    bool changed = false;

    // Обновляем время стрима
    if (_status.streamStatus.isActive && _streamStartTime != null) {
      _localStreamDuration = DateTime.now().difference(_streamStartTime!);
      changed = true;
    }

    // Обновляем время записи (с учётом паузы)
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
      // Обновляем статус с локальным временем
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

  /// Синхронизирует состояние с OBS (активен ли стрим/запись)
  Future<void> _syncStatusFromOBS() async {
    try {
      final streamStatus = await _obsService.getStreamStatus();
      final recordStatus = await _obsService.getRecordStatus();

      // Проверяем изменение состояния стрима
      if (streamStatus.isActive != _status.streamStatus.isActive) {
        if (streamStatus.isActive && !_status.streamStatus.isActive) {
          // Стрим начался
          _streamStartTime =
              DateTime.now().subtract(streamStatus.duration ?? Duration.zero);
          _localStreamDuration = streamStatus.duration ?? Duration.zero;
        } else if (!streamStatus.isActive) {
          // Стрим остановился
          _streamStartTime = null;
          _localStreamDuration = Duration.zero;
        }
      }

      // Проверяем изменение состояния записи
      if (recordStatus.isActive != _status.recordStatus.isActive) {
        if (recordStatus.isActive && !_status.recordStatus.isActive) {
          // Запись началась
          _recordStartTime =
              DateTime.now().subtract(recordStatus.duration ?? Duration.zero);
          _localRecordDuration = recordStatus.duration ?? Duration.zero;
          _recordPausedDuration = Duration.zero;
          _recordPauseTime = null;
        } else if (!recordStatus.isActive) {
          // Запись остановилась
          _recordStartTime = null;
          _localRecordDuration = Duration.zero;
          _recordPausedDuration = Duration.zero;
          _recordPauseTime = null;
        }
      }

      // Проверяем изменение паузы записи
      if (recordStatus.isPaused != _status.recordStatus.isPaused) {
        if (recordStatus.isPaused && !_status.recordStatus.isPaused) {
          // Пауза началась
          _recordPauseTime = DateTime.now();
        } else if (!recordStatus.isPaused && _status.recordStatus.isPaused) {
          // Пауза закончилась
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

      // Синхронизируем состояние Replay Buffer
      try {
        final replayActive = await _obsService.getReplayBufferStatus();
        if (replayActive != _status.replayBufferActive) {
          _status = _status.copyWith(replayBufferActive: replayActive);
        }
      } catch (e) {
        // Replay Buffer может быть не настроен в OBS - это нормально
      }
    } catch (e) {
      debugPrint('Error syncing status: $e');
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
    if (!isConnected) {
      debugPrint('Cannot switch scene: not connected');
      return;
    }
    debugPrint('Switching to scene: $sceneName');

    // Optimistic update — сразу обновляем UI
    _scenes = _scenes
        .map((s) => s.copyWith(
              isCurrentProgram: s.name == sceneName,
            ))
        .toList();
    notifyListeners();

    // Отправляем команду без await
    _obsService.setCurrentProgramScene(sceneName).catchError((e) {
      debugPrint('Error switching scene: $e');
    });
  }

  Future<void> toggleSceneItem(
      String sceneName, int itemId, bool enabled) async {
    if (!isConnected) return;
    debugPrint('Toggling scene item: $itemId in $sceneName to $enabled');

    // Optimistic update — сразу обновляем локально
    _updateSceneItemLocally(sceneName, itemId, enabled);

    // Отправляем команду без await
    _obsService.setSceneItemEnabled(sceneName, itemId, enabled).catchError((e) {
      debugPrint('Error toggling scene item: $e');
      // При ошибке откатываем
      _updateSceneItemLocally(sceneName, itemId, !enabled);
    });
  }

  Future<void> toggleStream() async {
    if (!isConnected) return;

    // Optimistic update
    final wasActive = _status.streamStatus.isActive;
    _status = _status.copyWith(
      streamStatus: OBSOutputStatus(isActive: !wasActive),
    );
    notifyListeners();

    _obsService.toggleStream().catchError((e) {
      debugPrint('Error toggling stream: $e');
    });
  }

  Future<void> startStream() async {
    if (!isConnected) return;

    // Optimistic update
    _status = _status.copyWith(
      streamStatus: OBSOutputStatus(isActive: true),
    );
    notifyListeners();

    _obsService.startStream().catchError((e) {
      debugPrint('Error starting stream: $e');
    });
  }

  Future<void> stopStream() async {
    if (!isConnected) return;

    // Optimistic update
    _status = _status.copyWith(
      streamStatus: OBSOutputStatus(isActive: false),
    );
    notifyListeners();

    _obsService.stopStream().catchError((e) {
      debugPrint('Error stopping stream: $e');
    });
  }

  Future<void> toggleRecord() async {
    if (!isConnected) return;

    // Optimistic update
    final wasActive = _status.recordStatus.isActive;
    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(isActive: !wasActive),
    );
    notifyListeners();

    _obsService.toggleRecord().catchError((e) {
      debugPrint('Error toggling record: $e');
    });
  }

  Future<void> startRecord() async {
    if (!isConnected) return;

    // Optimistic update
    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(isActive: true),
    );
    notifyListeners();

    _obsService.startRecord().catchError((e) {
      debugPrint('Error starting record: $e');
    });
  }

  Future<void> stopRecord() async {
    if (!isConnected) return;

    // Optimistic update
    _status = _status.copyWith(
      recordStatus: OBSOutputStatus(isActive: false),
    );
    notifyListeners();

    _obsService.stopRecord().catchError((e) {
      debugPrint('Error stopping record: $e');
    });
  }

  Future<void> pauseRecord() async {
    if (!isConnected) return;

    // Защита от быстрых повторных нажатий (500мс)
    final now = DateTime.now();
    if (_lastRecordPauseAction != null &&
        now.difference(_lastRecordPauseAction!).inMilliseconds < 500) {
      return;
    }
    _lastRecordPauseAction = now;

    // Optimistic update
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
      debugPrint('Error pausing record: $e');
    });
  }

  Future<void> resumeRecord() async {
    if (!isConnected) return;

    // Защита от быстрых повторных нажатий (500мс)
    final now = DateTime.now();
    if (_lastRecordPauseAction != null &&
        now.difference(_lastRecordPauseAction!).inMilliseconds < 500) {
      return;
    }
    _lastRecordPauseAction = now;

    // Optimistic update - добавляем время паузы
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
      debugPrint('Error resuming record: $e');
    });
  }

  Future<void> toggleRecordPause() async {
    if (!isConnected) return;

    // Защита от быстрых повторных нажатий (500мс)
    final now = DateTime.now();
    if (_lastRecordPauseAction != null &&
        now.difference(_lastRecordPauseAction!).inMilliseconds < 500) {
      return;
    }
    _lastRecordPauseAction = now;

    // Optimistic update
    final wasPaused = _status.recordStatus.isPaused;

    if (wasPaused) {
      // Снимаем паузу - добавляем время паузы
      if (_recordPauseTime != null) {
        _recordPausedDuration += DateTime.now().difference(_recordPauseTime!);
        _recordPauseTime = null;
      }
    } else {
      // Ставим паузу
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
      debugPrint('Error toggling record pause: $e');
    });
  }

  Future<void> toggleAudioMute(String inputName) async {
    if (!isConnected) return;
    debugPrint('Toggling mute for: $inputName');

    // Optimistic update
    final index = _audioSources.indexWhere((s) => s.name == inputName);
    if (index != -1) {
      final wasMuted = _audioSources[index].isMuted;
      _audioSources[index] = _audioSources[index].copyWith(isMuted: !wasMuted);
      notifyListeners();
    }

    _obsService.toggleInputMute(inputName).catchError((e) {
      debugPrint('Error toggling mute: $e');
    });
  }

  Future<void> setAudioVolume(String inputName, double volume) async {
    if (!isConnected) return;
    await _obsService.setInputVolume(inputName, volume);
  }

  Future<void> toggleVirtualCam() async {
    if (!isConnected) return;
    await _obsService.toggleVirtualCam();
  }

  Future<void> toggleStudioMode() async {
    if (!isConnected) return;
    final currentState = _status.studioModeEnabled;
    await _obsService.setStudioModeEnabled(!currentState);
    _status = _status.copyWith(studioModeEnabled: !currentState);
    notifyListeners();
  }

  Future<void> triggerHotkey(String hotkeyName) async {
    if (!isConnected) return;
    debugPrint('Triggering hotkey: $hotkeyName');
    try {
      await _obsService.triggerHotkeyByName(hotkeyName);
    } catch (e) {
      debugPrint('Error triggering hotkey: $e');
    }
  }

  Future<List<String>> getHotkeys() async {
    if (!isConnected) return [];
    try {
      return await _obsService.getHotkeyList();
    } catch (e) {
      debugPrint('Error getting hotkeys: $e');
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

      debugPrint('Screenshot saved: $path');
      return path;
    } catch (e) {
      debugPrint('Error saving screenshot: $e');
      return null;
    }
  }

  Future<void> saveReplayBuffer() async {
    if (!isConnected) return;
    try {
      await _obsService.saveReplayBuffer();
      debugPrint('Replay buffer saved');
    } catch (e) {
      debugPrint('Error saving replay buffer: $e');
    }
  }

  Future<void> startReplayBuffer() async {
    if (!isConnected) return;
    try {
      await _obsService.startReplayBuffer();
      _status = _status.copyWith(replayBufferActive: true);
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting replay buffer: $e');
    }
  }

  Future<void> stopReplayBuffer() async {
    if (!isConnected) return;
    try {
      await _obsService.stopReplayBuffer();
      _status = _status.copyWith(replayBufferActive: false);
      notifyListeners();
    } catch (e) {
      debugPrint('Error stopping replay buffer: $e');
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
      debugPrint('Error toggling replay buffer: $e');
    }
  }

  /// Обработка события изменения состояния Replay Buffer
  void _handleReplayBufferStateChanged(Map<String, dynamic> data) {
    final outputState = data['outputState'] as String?;
    debugPrint('Replay buffer state changed: $outputState');

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

  @override
  void dispose() {
    _statusTimer?.cancel();
    _debounceTimer?.cancel();
    _obsService.dispose();
    super.dispose();
  }
}
