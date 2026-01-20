// Сцена OBS
class OBSScene {
  final String name;
  final int index;
  final bool isCurrentProgram;
  final bool isCurrentPreview;

  OBSScene({
    required this.name,
    required this.index,
    this.isCurrentProgram = false,
    this.isCurrentPreview = false,
  });

  factory OBSScene.fromJson(Map<String, dynamic> json, {
    String? currentProgram,
    String? currentPreview,
  }) {
    final name = json['sceneName'] as String;
    return OBSScene(
      name: name,
      index: json['sceneIndex'] as int? ?? 0,
      isCurrentProgram: name == currentProgram,
      isCurrentPreview: name == currentPreview,
    );
  }

  OBSScene copyWith({
    String? name,
    int? index,
    bool? isCurrentProgram,
    bool? isCurrentPreview,
  }) {
    return OBSScene(
      name: name ?? this.name,
      index: index ?? this.index,
      isCurrentProgram: isCurrentProgram ?? this.isCurrentProgram,
      isCurrentPreview: isCurrentPreview ?? this.isCurrentPreview,
    );
  }
}

// Источник в сцене
class OBSSceneItem {
  final int sceneItemId;
  final String sourceName;
  final String sourceType;
  final bool isVisible;
  final bool isLocked;
  final int index;

  OBSSceneItem({
    required this.sceneItemId,
    required this.sourceName,
    required this.sourceType,
    required this.isVisible,
    this.isLocked = false,
    this.index = 0,
  });

  factory OBSSceneItem.fromJson(Map<String, dynamic> json) {
    return OBSSceneItem(
      sceneItemId: json['sceneItemId'] as int,
      sourceName: json['sourceName'] as String,
      sourceType: json['sourceType'] as String? ?? 'unknown',
      isVisible: json['sceneItemEnabled'] as bool? ?? true,
      isLocked: json['sceneItemLocked'] as bool? ?? false,
      index: json['sceneItemIndex'] as int? ?? 0,
    );
  }

  OBSSceneItem copyWith({
    int? sceneItemId,
    String? sourceName,
    String? sourceType,
    bool? isVisible,
    bool? isLocked,
    int? index,
  }) {
    return OBSSceneItem(
      sceneItemId: sceneItemId ?? this.sceneItemId,
      sourceName: sourceName ?? this.sourceName,
      sourceType: sourceType ?? this.sourceType,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      index: index ?? this.index,
    );
  }
}

// Аудио источник
class OBSAudioSource {
  final String name;
  final String kind;
  final double volume;
  final bool isMuted;

  OBSAudioSource({
    required this.name,
    required this.kind,
    this.volume = 1.0,
    this.isMuted = false,
  });

  factory OBSAudioSource.fromJson(Map<String, dynamic> json) {
    return OBSAudioSource(
      name: json['inputName'] as String,
      kind: json['inputKind'] as String? ?? 'unknown',
      volume: (json['inputVolumeMul'] as num?)?.toDouble() ?? 1.0,
      isMuted: json['inputMuted'] as bool? ?? false,
    );
  }

  OBSAudioSource copyWith({
    String? name,
    String? kind,
    double? volume,
    bool? isMuted,
  }) {
    return OBSAudioSource(
      name: name ?? this.name,
      kind: kind ?? this.kind,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

// Статус стрима/записи
enum OutputState { stopped, starting, started, stopping, paused, resumed }

class OBSOutputStatus {
  final bool isActive;
  final bool isPaused;
  final Duration? duration;
  final int? bytes;
  final int? frames;

  OBSOutputStatus({
    this.isActive = false,
    this.isPaused = false,
    this.duration,
    this.bytes,
    this.frames,
  });

  String get durationString {
    if (duration == null) return '00:00:00';
    final hours = duration!.inHours.toString().padLeft(2, '0');
    final minutes = (duration!.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration!.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OBSOutputStatus &&
          isActive == other.isActive &&
          isPaused == other.isPaused &&
          duration == other.duration;

  @override
  int get hashCode => Object.hash(isActive, isPaused, duration);
}

// Общий статус OBS
class OBSStatus {
  final bool isConnected;
  final String? obsVersion;
  final String? websocketVersion;
  final OBSOutputStatus streamStatus;
  final OBSOutputStatus recordStatus;
  final bool virtualCamActive;
  final bool replayBufferActive;
  final bool studioModeEnabled;
  final double cpuUsage;
  final double memoryUsage;
  final double fps;
  final int renderTotalFrames;
  final int renderSkippedFrames;

  OBSStatus({
    this.isConnected = false,
    this.obsVersion,
    this.websocketVersion,
    OBSOutputStatus? streamStatus,
    OBSOutputStatus? recordStatus,
    this.virtualCamActive = false,
    this.replayBufferActive = false,
    this.studioModeEnabled = false,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.fps = 0,
    this.renderTotalFrames = 0,
    this.renderSkippedFrames = 0,
  })  : streamStatus = streamStatus ?? OBSOutputStatus(),
        recordStatus = recordStatus ?? OBSOutputStatus();

  OBSStatus copyWith({
    bool? isConnected,
    String? obsVersion,
    String? websocketVersion,
    OBSOutputStatus? streamStatus,
    OBSOutputStatus? recordStatus,
    bool? virtualCamActive,
    bool? replayBufferActive,
    bool? studioModeEnabled,
    double? cpuUsage,
    double? memoryUsage,
    double? fps,
    int? renderTotalFrames,
    int? renderSkippedFrames,
  }) {
    return OBSStatus(
      isConnected: isConnected ?? this.isConnected,
      obsVersion: obsVersion ?? this.obsVersion,
      websocketVersion: websocketVersion ?? this.websocketVersion,
      streamStatus: streamStatus ?? this.streamStatus,
      recordStatus: recordStatus ?? this.recordStatus,
      virtualCamActive: virtualCamActive ?? this.virtualCamActive,
      replayBufferActive: replayBufferActive ?? this.replayBufferActive,
      studioModeEnabled: studioModeEnabled ?? this.studioModeEnabled,
      cpuUsage: cpuUsage ?? this.cpuUsage,
      memoryUsage: memoryUsage ?? this.memoryUsage,
      fps: fps ?? this.fps,
      renderTotalFrames: renderTotalFrames ?? this.renderTotalFrames,
      renderSkippedFrames: renderSkippedFrames ?? this.renderSkippedFrames,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OBSStatus &&
          isConnected == other.isConnected &&
          streamStatus == other.streamStatus &&
          recordStatus == other.recordStatus;

  @override
  int get hashCode => Object.hash(isConnected, streamStatus, recordStatus);
}
