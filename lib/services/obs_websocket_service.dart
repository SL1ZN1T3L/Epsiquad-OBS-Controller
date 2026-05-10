import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/models.dart';
import 'log_service.dart';

typedef EventCallback = void Function(
    String eventType, Map<String, dynamic> data);

const _tag = 'WS';

class OBSWebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final _responseCompleters = <String, Completer<Map<String, dynamic>>>{};
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected = false;
  bool _isConnecting = false;

  EventCallback? onEvent;
  void Function()? onConnected;
  void Function(String reason)? onDisconnected;
  void Function(String error)? onError;

  bool get isConnected => _isConnected;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  Future<bool> connect(OBSConnection connection) async {
    if (_isConnecting) return false;
    _isConnecting = true;

    log.i(_tag, 'Connecting to ${connection.host}:${connection.port}...');
    try {
      final uri = Uri.parse('ws://${connection.host}:${connection.port}');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;
      log.d(_tag, 'WebSocket ready');

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          log.e(_tag, 'WebSocket stream error', error.toString());
          _handleError('WebSocket error: $error');
        },
        onDone: () {
          log.w(_tag, 'WebSocket stream closed');
          _handleDisconnect('Connection closed');
        },
        cancelOnError: false,
      );

      final helloCompleter = Completer<Map<String, dynamic>>();
      _responseCompleters['hello'] = helloCompleter;

      final hello = await helloCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      final authRequired = hello['d']?['authentication'] != null;
      String? authString;

      if (authRequired && connection.password != null) {
        final auth = hello['d']['authentication'];
        final challenge = auth['challenge'] as String;
        final salt = auth['salt'] as String;
        authString = _generateAuthString(connection.password!, salt, challenge);
        log.d(_tag, 'Auth required, generated auth string');
      } else if (authRequired && connection.password == null) {
        log.w(_tag, 'Auth required but no password provided');
      }

      final identifyCompleter = Completer<Map<String, dynamic>>();
      _responseCompleters['identify'] = identifyCompleter;

      final identifyMessage = {
        'op': 1,
        'd': {
          'rpcVersion': 1,
          if (authString != null) 'authentication': authString,
          'eventSubscriptions': 511,
        },
      };

      _channel!.sink.add(json.encode(identifyMessage));

      final identifyResponse = await identifyCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Identify timeout'),
      );

      if (identifyResponse['op'] == 2) {
        _isConnected = true;
        log.i(_tag, 'Connected successfully');
        onConnected?.call();
        return true;
      }

      throw Exception('Identify failed: op=${identifyResponse['op']}');
    } on TimeoutException catch (e) {
      log.e(_tag, 'Connection timeout', e.toString());
      _handleError('Connection timeout');
      return false;
    } on WebSocketChannelException catch (e) {
      log.e(_tag, 'WebSocket connection refused', e.toString());
      _handleError('Connection refused: $e');
      return false;
    } catch (e) {
      log.e(_tag, 'Connection failed', e.toString());
      _handleError('Connection failed: $e');
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    if (!_isConnected && _channel == null && !_isConnecting) return;

    log.i(_tag, 'Disconnecting...');

    _isConnected = false;
    _isConnecting = false;

    for (final completer in _responseCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError('Disconnected');
      }
    }
    _responseCompleters.clear();

    await _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close(status.normalClosure);
    } catch (e) {
      log.w(_tag, 'Error closing WebSocket', e.toString());
    }
    _channel = null;

    await Future.delayed(const Duration(milliseconds: 500));
    log.i(_tag, 'Disconnected');
  }

  String _generateAuthString(String password, String salt, String challenge) {
    final secretHash = sha256.convert(utf8.encode(password + salt));
    final secretBase64 = base64.encode(secretHash.bytes);
    final authHash = sha256.convert(utf8.encode(secretBase64 + challenge));
    return base64.encode(authHash.bytes);
  }

  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String) as Map<String, dynamic>;
      final op = data['op'] as int;

      switch (op) {
        case 0: // Hello
          _responseCompleters['hello']?.complete(data);
          _responseCompleters.remove('hello');
          break;
        case 2: // Identified
          _responseCompleters['identify']?.complete(data);
          _responseCompleters.remove('identify');
          break;
        case 5: // Event
          _handleEvent(data);
          break;
        case 7: // RequestResponse
          final requestId = data['d']?['requestId'] as String?;
          if (requestId != null && _responseCompleters.containsKey(requestId)) {
            _responseCompleters[requestId]!.complete(data);
            _responseCompleters.remove(requestId);
          }
          break;
      }
    } catch (e) {
      log.e(_tag, 'Message parse error', e.toString());
      _handleError('Message parse error: $e');
    }
  }

  void _handleEvent(Map<String, dynamic> data) {
    final eventType = data['d']?['eventType'] as String?;
    final eventData = data['d']?['eventData'] as Map<String, dynamic>? ?? {};

    if (eventType != null) {
      _eventController.add({'type': eventType, 'data': eventData});
      onEvent?.call(eventType, eventData);
    }
  }

  void _handleError(String error) {
    onError?.call(error);
  }

  void _handleDisconnect(String reason) {
    final wasConnected = _isConnected;
    _isConnected = false;
    if (wasConnected) {
      onDisconnected?.call(reason);
    }
  }

  Future<Map<String, dynamic>> _sendRequest(
    String requestType,
    Map<String, dynamic>? requestData, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_channel == null || !_isConnected) {
      throw Exception('Not connected');
    }

    final requestId = _generateRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _responseCompleters[requestId] = completer;

    final message = {
      'op': 6,
      'd': {
        'requestType': requestType,
        'requestId': requestId,
        'requestData': requestData ?? {},
      },
    };

    _channel!.sink.add(json.encode(message));

    try {
      final response = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _responseCompleters.remove(requestId);
          throw TimeoutException('Request timeout: $requestType');
        },
      );

      final requestStatus = response['d']?['requestStatus'];
      if (requestStatus != null && requestStatus['result'] == false) {
        final code = requestStatus['code'];
        final comment = requestStatus['comment'] ?? 'Unknown error';
        log.w(_tag, 'Request $requestType failed: $code', comment);
      }

      return response;
    } on TimeoutException {
      log.e(_tag, 'Request timeout', requestType);
      rethrow;
    } catch (e) {
      if (e.toString() != 'Disconnected') {
        log.e(_tag, 'Request error: $requestType', e.toString());
      }
      rethrow;
    }
  }

  String _generateRequestId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(16, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Изменяет подписки на события без переподключения (op=3 Reidentify)
  void reidentify(int eventSubscriptions) {
    if (!_isConnected || _channel == null) return;
    final msg = {
      'op': 3,
      'd': {
        'eventSubscriptions': eventSubscriptions,
      },
    };
    _channel!.sink.add(json.encode(msg));
    log.d(_tag, 'Reidentify with eventSubscriptions: $eventSubscriptions');
  }

  // ==================== API методы ====================

  Future<Map<String, dynamic>> getVersion() async {
    final response = await _sendRequest('GetVersion', null);
    return response['d']?['responseData'] ?? {};
  }

  Future<Map<String, dynamic>> getStats() async {
    final response = await _sendRequest('GetStats', null);
    return response['d']?['responseData'] ?? {};
  }

  // ==================== Сцены ====================

  Future<List<OBSScene>> getSceneList() async {
    final response = await _sendRequest('GetSceneList', null);
    final data = response['d']?['responseData'] ?? {};
    final scenes = (data['scenes'] as List? ?? []);
    final currentProgram = data['currentProgramSceneName'] as String?;
    final currentPreview = data['currentPreviewSceneName'] as String?;

    log.d(_tag, 'Loaded ${scenes.length} scenes, current: $currentProgram');

    return scenes
        .map((s) => OBSScene.fromJson(
              s as Map<String, dynamic>,
              currentProgram: currentProgram,
              currentPreview: currentPreview,
            ))
        .toList()
        .reversed
        .toList();
  }

  Future<String?> getCurrentProgramScene() async {
    final response = await _sendRequest('GetCurrentProgramScene', null);
    return response['d']?['responseData']?['currentProgramSceneName']
        as String?;
  }

  Future<void> setCurrentProgramScene(String sceneName) async {
    log.d(_tag, 'Set scene: $sceneName');
    await _sendRequest('SetCurrentProgramScene', {
      'sceneName': sceneName,
    });
  }

  Future<String?> getCurrentPreviewScene() async {
    final response = await _sendRequest('GetCurrentPreviewScene', null);
    return response['d']?['responseData']?['currentPreviewSceneName']
        as String?;
  }

  Future<void> setCurrentPreviewScene(String sceneName) async {
    await _sendRequest('SetCurrentPreviewScene', {
      'sceneName': sceneName,
    });
  }

  // ==================== Источники сцены ====================

  Future<List<OBSSceneItem>> getSceneItemList(String sceneName) async {
    final response = await _sendRequest('GetSceneItemList', {
      'sceneName': sceneName,
    });
    final items = response['d']?['responseData']?['sceneItems'] as List? ?? [];
    log.d(_tag, 'Scene items for $sceneName: ${items.length}');
    return items
        .map((i) => OBSSceneItem.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  Future<void> setSceneItemEnabled(
      String sceneName, int sceneItemId, bool enabled) async {
    await _sendRequest('SetSceneItemEnabled', {
      'sceneName': sceneName,
      'sceneItemId': sceneItemId,
      'sceneItemEnabled': enabled,
    });
  }

  // ==================== Аудио ====================

  /// Возвращает true, если ответ от OBS содержит requestStatus.result == true.
  bool _isOk(Map<String, dynamic> response) {
    return response['d']?['requestStatus']?['result'] == true;
  }

  /// Быстрая проверка inputKind на принадлежность к аудио-типу.
  /// Покрывает Windows (wasapi, в т.ч. process_output_capture для захвата
  /// звука приложения), Linux (pulse, alsa, jack, pipewire),
  /// macOS (coreaudio), а также медиа-источники (ffmpeg, vlc).
  bool _looksLikeAudioKind(String kind) {
    return kind.contains('wasapi') ||
        kind.contains('pulse') ||
        kind.contains('coreaudio') ||
        kind.contains('alsa') ||
        kind.contains('jack') ||
        kind.contains('pipewire') ||
        kind.contains('audio') ||
        kind.contains('ffmpeg') ||
        kind.contains('vlc');
  }

  Future<List<OBSAudioSource>> getInputList() async {
    final response = await _sendRequest('GetInputList', null);
    final inputs = response['d']?['responseData']?['inputs'] as List? ?? [];

    // Шаг 1. Быстрый kind-фильтр для очевидно аудио-источников.
    // Шаг 2. Для остальных — probe через GetInputMute параллельно: если OBS
    // отвечает успехом, значит у источника есть аудио-выход (это покрывает
    // нестандартные плагины захвата звука приложения, у которых inputKind
    // не попадает в список выше).
    final knownAudio = <Map<String, dynamic>>[];
    final unknown = <Map<String, dynamic>>[];

    for (final input in inputs) {
      final kind = (input['inputKind'] as String? ?? '').toLowerCase();
      if (_looksLikeAudioKind(kind)) {
        knownAudio.add(Map<String, dynamic>.from(input));
      } else {
        unknown.add(Map<String, dynamic>.from(input));
      }
    }

    // Probe непрошедших источников параллельно.
    final probeResults = await Future.wait(unknown.map((input) async {
      final name = input['inputName'] as String;
      try {
        final res = await _sendRequest('GetInputMute', {'inputName': name});
        return _isOk(res) ? input : null;
      } catch (_) {
        return null;
      }
    }));

    final detected = [
      ...knownAudio,
      ...probeResults.whereType<Map<String, dynamic>>(),
    ];

    // Получение mute/volume для всех обнаруженных аудио-источников.
    final audioSources = await Future.wait(detected.map((input) async {
      final name = input['inputName'] as String;
      final kind = input['inputKind'] as String? ?? 'unknown';

      bool isMuted = false;
      double volumeMul = 1.0;

      try {
        final muteResponse =
            await _sendRequest('GetInputMute', {'inputName': name});
        if (_isOk(muteResponse)) {
          isMuted = muteResponse['d']?['responseData']?['inputMuted'] as bool? ??
              false;
        }
      } catch (e) {
        log.w(_tag, 'GetInputMute failed for $name', e.toString());
      }

      try {
        final volumeResponse =
            await _sendRequest('GetInputVolume', {'inputName': name});
        if (_isOk(volumeResponse)) {
          volumeMul =
              (volumeResponse['d']?['responseData']?['inputVolumeMul'] as num?)
                      ?.toDouble() ??
                  1.0;
        }
      } catch (e) {
        log.w(_tag, 'GetInputVolume failed for $name', e.toString());
      }

      return OBSAudioSource(
        name: name,
        kind: kind,
        isMuted: isMuted,
        volume: _mulToSlider(volumeMul),
      );
    }));

    log.d(_tag,
        'Audio sources: ${audioSources.length} (kind-matched: ${knownAudio.length}, probed: ${detected.length - knownAudio.length})');
    return audioSources;
  }

  /// Возвращает имена медиа-источников (ffmpeg_source, vlc_source)
  Future<List<String>> getMediaInputNames() async {
    final response = await _sendRequest('GetInputList', null);
    final inputs = response['d']?['responseData']?['inputs'] as List? ?? [];

    final mediaNames = <String>[];
    for (final input in inputs) {
      final kind = input['inputKind'] as String? ?? '';
      if (kind == 'ffmpeg_source' || kind == 'vlc_source') {
        mediaNames.add(input['inputName'] as String);
      }
    }
    return mediaNames;
  }

  Future<void> setInputMute(String inputName, bool muted) async {
    await _sendRequest('SetInputMute', {
      'inputName': inputName,
      'inputMuted': muted,
    });
  }

  Future<void> toggleInputMute(String inputName) async {
    await _sendRequest('ToggleInputMute', {
      'inputName': inputName,
    });
  }

  Future<void> setInputVolume(String inputName, double sliderValue) async {
    final volumeMul = _sliderToMul(sliderValue);
    await _sendRequest('SetInputVolume', {
      'inputName': inputName,
      'inputVolumeMul': volumeMul,
    });
  }

  /// Возвращает текущее состояние mute. Используется для post-verify.
  Future<bool?> getInputMute(String inputName) async {
    final response = await _sendRequest(
      'GetInputMute',
      {'inputName': inputName},
      timeout: const Duration(seconds: 5),
    );
    if (!_isOk(response)) return null;
    return response['d']?['responseData']?['inputMuted'] as bool?;
  }

  /// Возвращает текущую громкость (slider 0..1). Используется для post-verify.
  Future<double?> getInputVolume(String inputName) async {
    final response = await _sendRequest(
      'GetInputVolume',
      {'inputName': inputName},
      timeout: const Duration(seconds: 5),
    );
    if (!_isOk(response)) return null;
    final mul = (response['d']?['responseData']?['inputVolumeMul'] as num?)
        ?.toDouble();
    if (mul == null) return null;
    return _mulToSlider(mul);
  }

  /// Возвращает текущее состояние видимости элемента сцены. Для post-verify.
  Future<bool?> getSceneItemEnabled(String sceneName, int sceneItemId) async {
    final response = await _sendRequest(
      'GetSceneItemEnabled',
      {'sceneName': sceneName, 'sceneItemId': sceneItemId},
      timeout: const Duration(seconds: 5),
    );
    if (!_isOk(response)) return null;
    return response['d']?['responseData']?['sceneItemEnabled'] as bool?;
  }

  double _sliderToMul(double slider) {
    return slider * slider * slider * slider;
  }

  double _mulToSlider(double mul) {
    if (mul <= 0) return 0;
    return pow(mul, 0.25).toDouble();
  }

  // ==================== Стрим ====================

  Future<OBSOutputStatus> getStreamStatus() async {
    final response = await _sendRequest('GetStreamStatus', null);
    final data = response['d']?['responseData'] ?? {};
    return OBSOutputStatus(
      isActive: data['outputActive'] as bool? ?? false,
      duration: Duration(milliseconds: (data['outputDuration'] as int?) ?? 0),
      bytes: data['outputBytes'] as int?,
    );
  }

  Future<void> startStream() async {
    await _sendRequest('StartStream', null);
  }

  Future<void> stopStream() async {
    await _sendRequest('StopStream', null);
  }

  Future<void> toggleStream() async {
    await _sendRequest('ToggleStream', null);
  }

  // ==================== Запись ====================

  Future<OBSOutputStatus> getRecordStatus() async {
    final response = await _sendRequest('GetRecordStatus', null);
    final data = response['d']?['responseData'] ?? {};
    return OBSOutputStatus(
      isActive: data['outputActive'] as bool? ?? false,
      isPaused: data['outputPaused'] as bool? ?? false,
      duration: Duration(milliseconds: (data['outputDuration'] as int?) ?? 0),
      bytes: data['outputBytes'] as int?,
    );
  }

  Future<void> startRecord() async {
    await _sendRequest('StartRecord', null);
  }

  Future<void> stopRecord() async {
    await _sendRequest('StopRecord', null);
  }

  Future<void> toggleRecord() async {
    await _sendRequest('ToggleRecord', null);
  }

  Future<void> pauseRecord() async {
    await _sendRequest('PauseRecord', null);
  }

  Future<void> resumeRecord() async {
    await _sendRequest('ResumeRecord', null);
  }

  Future<void> toggleRecordPause() async {
    await _sendRequest('ToggleRecordPause', null);
  }

  // ==================== Виртуальная камера ====================

  Future<bool> getVirtualCamStatus() async {
    final response = await _sendRequest('GetVirtualCamStatus', null);
    return response['d']?['responseData']?['outputActive'] as bool? ?? false;
  }

  Future<void> startVirtualCam() async {
    await _sendRequest('StartVirtualCam', null);
  }

  Future<void> stopVirtualCam() async {
    await _sendRequest('StopVirtualCam', null);
  }

  Future<void> toggleVirtualCam() async {
    await _sendRequest('ToggleVirtualCam', null);
  }

  // ==================== Replay Buffer ====================

  Future<bool> getReplayBufferStatus() async {
    final response = await _sendRequest('GetReplayBufferStatus', null);
    return response['d']?['responseData']?['outputActive'] as bool? ?? false;
  }

  Future<void> startReplayBuffer() async {
    await _sendRequest('StartReplayBuffer', null);
  }

  Future<void> stopReplayBuffer() async {
    await _sendRequest('StopReplayBuffer', null);
  }

  Future<void> saveReplayBuffer() async {
    await _sendRequest('SaveReplayBuffer', null);
  }

  // ==================== Studio Mode ====================

  Future<bool> getStudioModeEnabled() async {
    final response = await _sendRequest('GetStudioModeEnabled', null);
    return response['d']?['responseData']?['studioModeEnabled'] as bool? ??
        false;
  }

  Future<void> setStudioModeEnabled(bool enabled) async {
    await _sendRequest('SetStudioModeEnabled', {
      'studioModeEnabled': enabled,
    });
  }

  Future<void> triggerStudioModeTransition() async {
    await _sendRequest('TriggerStudioModeTransition', null);
  }

  // ==================== Горячие клавиши ====================

  Future<List<String>> getHotkeyList() async {
    final response = await _sendRequest('GetHotkeyList', null);
    final hotkeys = response['d']?['responseData']?['hotkeys'] as List? ?? [];
    return hotkeys.map((h) => h as String).toList();
  }

  Future<void> triggerHotkeyByName(String hotkeyName) async {
    await _sendRequest('TriggerHotkeyByName', {
      'hotkeyName': hotkeyName,
    });
  }

  // ==================== Скриншоты ====================

  Future<String> saveSourceScreenshot({
    required String sourceName,
    required String imageFilePath,
    String imageFormat = 'png',
    int? imageWidth,
    int? imageHeight,
    int? imageCompressionQuality,
  }) async {
    await _sendRequest('SaveSourceScreenshot', {
      'sourceName': sourceName,
      'imageFormat': imageFormat,
      'imageFilePath': imageFilePath,
      if (imageWidth != null) 'imageWidth': imageWidth,
      if (imageHeight != null) 'imageHeight': imageHeight,
      if (imageCompressionQuality != null)
        'imageCompressionQuality': imageCompressionQuality,
    });
    return imageFilePath;
  }

  Future<String?> getSourceScreenshotBase64({
    required String sourceName,
    String imageFormat = 'jpg',
    int? imageWidth,
    int? imageHeight,
    int imageCompressionQuality = 60,
  }) async {
    final response = await _sendRequest('GetSourceScreenshot', {
      'sourceName': sourceName,
      'imageFormat': imageFormat,
      if (imageWidth != null) 'imageWidth': imageWidth,
      if (imageHeight != null) 'imageHeight': imageHeight,
      'imageCompressionQuality': imageCompressionQuality,
    });
    return response['d']?['responseData']?['imageData'] as String?;
  }

  // ==================== Scene Collections ====================

  Future<Map<String, dynamic>> getSceneCollectionList() async {
    final response = await _sendRequest('GetSceneCollectionList', null);
    return response['d']?['responseData'] ?? {};
  }

  Future<void> setCurrentSceneCollection(String collectionName) async {
    log.i(_tag, 'Switching scene collection: $collectionName');
    await _sendRequest('SetCurrentSceneCollection', {
      'sceneCollectionName': collectionName,
    });
  }

  // ==================== Профили OBS ====================

  Future<Map<String, dynamic>> getProfileList() async {
    final response = await _sendRequest('GetProfileList', null);
    return response['d']?['responseData'] ?? {};
  }

  Future<void> setCurrentProfile(String profileName) async {
    log.i(_tag, 'Switching profile: $profileName');
    await _sendRequest('SetCurrentProfile', {
      'profileName': profileName,
    });
  }

  // ==================== Переходы ====================

  Future<Map<String, dynamic>> getSceneTransitionList() async {
    final response = await _sendRequest('GetSceneTransitionList', null);
    return response['d']?['responseData'] ?? {};
  }

  Future<Map<String, dynamic>> getCurrentSceneTransition() async {
    final response = await _sendRequest('GetCurrentSceneTransition', null);
    return response['d']?['responseData'] ?? {};
  }

  Future<void> setCurrentSceneTransition(String transitionName) async {
    log.i(_tag, 'Set transition: $transitionName');
    await _sendRequest('SetCurrentSceneTransition', {
      'transitionName': transitionName,
    });
  }

  Future<void> setCurrentSceneTransitionDuration(int durationMs) async {
    await _sendRequest('SetCurrentSceneTransitionDuration', {
      'transitionDuration': durationMs,
    });
  }

  // ==================== Фильтры источников ====================

  Future<List<OBSSourceFilter>> getSourceFilterList(String sourceName) async {
    final response = await _sendRequest('GetSourceFilterList', {
      'sourceName': sourceName,
    });
    final filters = response['d']?['responseData']?['filters'] as List? ?? [];
    return filters
        .map((f) => OBSSourceFilter.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  Future<void> setSourceFilterEnabled(
      String sourceName, String filterName, bool enabled) async {
    await _sendRequest('SetSourceFilterEnabled', {
      'sourceName': sourceName,
      'filterName': filterName,
      'filterEnabled': enabled,
    });
  }

  // ==================== Медиа источники ====================

  Future<OBSMediaStatus> getMediaInputStatus(String inputName) async {
    final response = await _sendRequest('GetMediaInputStatus', {
      'inputName': inputName,
    });
    final data = response['d']?['responseData'] ?? {};
    return OBSMediaStatus(
      inputName: inputName,
      state: data['mediaState'] as String? ?? 'OBS_MEDIA_STATE_NONE',
      duration: data['mediaDuration'] != null
          ? Duration(milliseconds: data['mediaDuration'] as int)
          : null,
      cursor: data['mediaCursor'] != null
          ? Duration(milliseconds: data['mediaCursor'] as int)
          : null,
    );
  }

  Future<void> triggerMediaInputAction(String inputName, String action) async {
    await _sendRequest('TriggerMediaInputAction', {
      'inputName': inputName,
      'mediaAction': action,
    });
  }

  Future<void> playMediaInput(String inputName) async {
    await triggerMediaInputAction(inputName, 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY');
  }

  Future<void> pauseMediaInput(String inputName) async {
    await triggerMediaInputAction(inputName, 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PAUSE');
  }

  Future<void> stopMediaInput(String inputName) async {
    await triggerMediaInputAction(inputName, 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_STOP');
  }

  Future<void> restartMediaInput(String inputName) async {
    await triggerMediaInputAction(inputName, 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART');
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}
