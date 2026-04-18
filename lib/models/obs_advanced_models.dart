// Переход сцены
class OBSSceneTransition {
  final String name;
  final String kind;
  final bool isFixed;

  OBSSceneTransition({
    required this.name,
    required this.kind,
    this.isFixed = false,
  });

  factory OBSSceneTransition.fromJson(Map<String, dynamic> json) {
    return OBSSceneTransition(
      name: json['transitionName'] as String,
      kind: json['transitionKind'] as String? ?? 'unknown',
      isFixed: json['transitionFixed'] as bool? ?? false,
    );
  }
}

// Фильтр источника
class OBSSourceFilter {
  final String name;
  final String kind;
  final int index;
  final bool enabled;
  final Map<String, dynamic> settings;

  OBSSourceFilter({
    required this.name,
    required this.kind,
    this.index = 0,
    this.enabled = true,
    this.settings = const {},
  });

  factory OBSSourceFilter.fromJson(Map<String, dynamic> json) {
    return OBSSourceFilter(
      name: json['filterName'] as String,
      kind: json['filterKind'] as String? ?? 'unknown',
      index: json['filterIndex'] as int? ?? 0,
      enabled: json['filterEnabled'] as bool? ?? true,
      settings: json['filterSettings'] as Map<String, dynamic>? ?? {},
    );
  }

  OBSSourceFilter copyWith({
    String? name,
    String? kind,
    int? index,
    bool? enabled,
    Map<String, dynamic>? settings,
  }) {
    return OBSSourceFilter(
      name: name ?? this.name,
      kind: kind ?? this.kind,
      index: index ?? this.index,
      enabled: enabled ?? this.enabled,
      settings: settings ?? this.settings,
    );
  }
}

// Статус медиа-источника
class OBSMediaStatus {
  final String inputName;
  final String state;
  final Duration? duration;
  final Duration? cursor;

  OBSMediaStatus({
    required this.inputName,
    required this.state,
    this.duration,
    this.cursor,
  });

  bool get isPlaying => state == 'OBS_MEDIA_STATE_PLAYING';
  bool get isPaused => state == 'OBS_MEDIA_STATE_PAUSED';
  bool get isStopped => state == 'OBS_MEDIA_STATE_STOPPED' ||
      state == 'OBS_MEDIA_STATE_ENDED' ||
      state == 'OBS_MEDIA_STATE_NONE';

  String get stateLabel {
    switch (state) {
      case 'OBS_MEDIA_STATE_PLAYING':
        return 'Воспроизведение';
      case 'OBS_MEDIA_STATE_PAUSED':
        return 'Пауза';
      case 'OBS_MEDIA_STATE_STOPPED':
        return 'Остановлено';
      case 'OBS_MEDIA_STATE_ENDED':
        return 'Завершено';
      case 'OBS_MEDIA_STATE_NONE':
        return 'Нет медиа';
      default:
        return state;
    }
  }

  String get progressString {
    if (cursor == null || duration == null) return '';
    return '${_formatDuration(cursor!)} / ${_formatDuration(duration!)}';
  }

  double get progress {
    if (cursor == null || duration == null || duration!.inMilliseconds == 0) return 0;
    return cursor!.inMilliseconds / duration!.inMilliseconds;
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }
}
