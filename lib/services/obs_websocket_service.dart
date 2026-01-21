import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/models.dart';

typedef EventCallback = void Function(String eventType, Map<String, dynamic> data);

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
    
    debugPrint('OBS WebSocket: Starting connection...');
    try {
      final uri = Uri.parse('ws://${connection.host}:${connection.port}');
      debugPrint('Connecting to $uri');
      _channel = WebSocketChannel.connect(uri);
      
      await _channel!.ready;
      debugPrint('WebSocket ready');
      
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _handleError('WebSocket error: $error');
        },
        onDone: () {
          debugPrint('WebSocket closed');
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
      
      debugPrint('Received Hello: $hello');
      
      final authRequired = hello['d']?['authentication'] != null;
      String? authString;
      
      if (authRequired && connection.password != null) {
        final auth = hello['d']['authentication'];
        final challenge = auth['challenge'] as String;
        final salt = auth['salt'] as String;
        authString = _generateAuthString(connection.password!, salt, challenge);
        debugPrint('Auth required, generated auth string');
      }
      
      final identifyCompleter = Completer<Map<String, dynamic>>();
      _responseCompleters['identify'] = identifyCompleter;
      
      final identifyMessage = {
        'op': 1,
        'd': {
          'rpcVersion': 1,
          if (authString != null) 'authentication': authString,
          'eventSubscriptions': 207,
        },
      };
      
      debugPrint('Sending Identify: $identifyMessage');
      _channel!.sink.add(json.encode(identifyMessage));
      
      final identifyResponse = await identifyCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Identify timeout'),
      );
      
      debugPrint('Identify response: $identifyResponse');
      
      if (identifyResponse['op'] == 2) {
        _isConnected = true;
        onConnected?.call();
        return true;
      }
      
      throw Exception('Identify failed: $identifyResponse');
    } catch (e) {
      debugPrint('Connection error: $e');
      _handleError('Connection failed: $e');
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    if (!_isConnected && _channel == null && !_isConnecting) return;
    
    debugPrint('OBS WebSocket: Disconnecting...');
    
    _isConnected = false;
    _isConnecting = false;
    
    // Complete all pending requests with error
    for (final completer in _responseCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError('Disconnected');
      }
    }
    _responseCompleters.clear();
    
    // Cancel subscription
    await _subscription?.cancel();
    _subscription = null;
    
    // Close channel
    try {
      await _channel?.sink.close(status.normalClosure);
    } catch (e) {
      debugPrint('Error closing WebSocket: $e');
    }
    _channel = null;
    
    // Wait for OBS to process disconnect
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint('OBS WebSocket: Disconnected');
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
      
      // debugPrint('Received message op=$op');
      
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
          // debugPrint('Response for $requestId: ${data['d']?['requestStatus']}');
          if (requestId != null && _responseCompleters.containsKey(requestId)) {
            _responseCompleters[requestId]!.complete(data);
            _responseCompleters.remove(requestId);
          }
          break;
      }
    } catch (e) {
      debugPrint('Message parse error: $e');
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
    Map<String, dynamic>? requestData,
  ) async {
    if (_channel == null || !_isConnected) {
      throw Exception('Not connected');
    }
    
    final requestId = _generateRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _responseCompleters[requestId] = completer;
    
    // ПРАВИЛЬНЫЙ ФОРМАТ: requestData должен быть вложенным объектом
    final message = {
      'op': 6,
      'd': {
        'requestType': requestType,
        'requestId': requestId,
        'requestData': requestData ?? {},
      },
    };
    
    // debugPrint('Sending request: $message');
    _channel!.sink.add(json.encode(message));
    
    final response = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _responseCompleters.remove(requestId);
        throw TimeoutException('Request timeout: $requestType');
      },
    );
    
    // Проверяем успешность
    final requestStatus = response['d']?['requestStatus'];
    if (requestStatus != null && requestStatus['result'] == false) {
      final code = requestStatus['code'];
      final comment = requestStatus['comment'] ?? 'Unknown error';
      debugPrint('Request failed: $code - $comment');
    }
    
    return response;
  }

  String _generateRequestId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(16, (index) => chars[random.nextInt(chars.length)]).join();
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
    
    debugPrint('Scenes: $scenes, current: $currentProgram');
    
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
    return response['d']?['responseData']?['currentProgramSceneName'] as String?;
  }

  Future<void> setCurrentProgramScene(String sceneName) async {
    debugPrint('Setting scene to: $sceneName');
    await _sendRequest('SetCurrentProgramScene', {
      'sceneName': sceneName,
    });
  }

  Future<String?> getCurrentPreviewScene() async {
    final response = await _sendRequest('GetCurrentPreviewScene', null);
    return response['d']?['responseData']?['currentPreviewSceneName'] as String?;
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
    debugPrint('Scene items for $sceneName: ${items.length}');
    return items.map((i) => OBSSceneItem.fromJson(i as Map<String, dynamic>)).toList();
  }

  Future<void> setSceneItemEnabled(String sceneName, int sceneItemId, bool enabled) async {
    await _sendRequest('SetSceneItemEnabled', {
      'sceneName': sceneName,
      'sceneItemId': sceneItemId,
      'sceneItemEnabled': enabled,
    });
  }

  // ==================== Аудио ====================

  Future<List<OBSAudioSource>> getInputList() async {
    final response = await _sendRequest('GetInputList', null);
    final inputs = response['d']?['responseData']?['inputs'] as List? ?? [];
    
    debugPrint('Inputs: ${inputs.length}');
    
    final audioSources = <OBSAudioSource>[];
    for (final input in inputs) {
      final name = input['inputName'] as String;
      final kind = input['inputKind'] as String? ?? 'unknown';
      
      // Только аудио источники
      if (kind.contains('wasapi') || 
          kind.contains('pulse') || 
          kind.contains('coreaudio') ||
          kind.contains('alsa') ||
          kind.contains('jack') ||
          kind.contains('audio')) {
        try {
          final muteResponse = await _sendRequest('GetInputMute', {'inputName': name});
          final isMuted = muteResponse['d']?['responseData']?['inputMuted'] as bool? ?? false;
          
          // Получаем громкость
          final volumeResponse = await _sendRequest('GetInputVolume', {'inputName': name});
          final volumeMul = (volumeResponse['d']?['responseData']?['inputVolumeMul'] as num?)?.toDouble() ?? 1.0;
          
          audioSources.add(OBSAudioSource(
            name: name,
            kind: kind,
            isMuted: isMuted,
            volume: volumeMul,
          ));
        } catch (e) {
          debugPrint('Error getting audio info for $name: $e');
        }
      }
    }
    
    debugPrint('Audio sources: ${audioSources.length}');
    return audioSources;
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

  Future<void> setInputVolume(String inputName, double volumeMul) async {
    await _sendRequest('SetInputVolume', {
      'inputName': inputName,
      'inputVolumeMul': volumeMul,
    });
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
    return response['d']?['responseData']?['studioModeEnabled'] as bool? ?? false;
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
      if (imageCompressionQuality != null) 'imageCompressionQuality': imageCompressionQuality,
    });
    return imageFilePath;
  }
  void dispose() {
    disconnect();
    _eventController.close();
  }
}






