class SessionStats {
  final String id;
  final SessionType type;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final String? name;
  final bool starred;
  final String? notes;
  final List<StatsSnapshot> snapshots;

  SessionStats({
    required this.id,
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    this.name,
    this.starred = false,
    this.notes,
    this.snapshots = const [],
  });

  String get durationString {
    final h = (durationSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((durationSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get dateString {
    return '${startTime.day.toString().padLeft(2, '0')}.'
        '${startTime.month.toString().padLeft(2, '0')}.'
        '${startTime.year} '
        '${startTime.hour.toString().padLeft(2, '0')}:'
        '${startTime.minute.toString().padLeft(2, '0')}';
  }

  double get avgFps {
    if (snapshots.isEmpty) return 0;
    return snapshots.map((s) => s.fps).reduce((a, b) => a + b) / snapshots.length;
  }

  double get avgCpu {
    if (snapshots.isEmpty) return 0;
    return snapshots.map((s) => s.cpuUsage).reduce((a, b) => a + b) / snapshots.length;
  }

  double get avgMemory {
    if (snapshots.isEmpty) return 0;
    return snapshots.map((s) => s.memoryUsage).reduce((a, b) => a + b) / snapshots.length;
  }

  double get maxCpu {
    if (snapshots.isEmpty) return 0;
    return snapshots.map((s) => s.cpuUsage).reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'durationSeconds': durationSeconds,
        'name': name,
        'starred': starred,
        'notes': notes,
        'snapshots': snapshots.map((s) => s.toJson()).toList(),
      };

  factory SessionStats.fromJson(Map<String, dynamic> json) {
    return SessionStats(
      id: json['id'] as String,
      type: SessionType.values[json['type'] as int],
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      durationSeconds: json['durationSeconds'] as int,
      name: json['name'] as String?,
      starred: json['starred'] as bool? ?? false,
      notes: json['notes'] as String?,
      snapshots: (json['snapshots'] as List?)
              ?.map((s) => StatsSnapshot.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  SessionStats copyWith({
    String? name,
    bool? starred,
    String? notes,
  }) {
    return SessionStats(
      id: id,
      type: type,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSeconds,
      name: name ?? this.name,
      starred: starred ?? this.starred,
      notes: notes ?? this.notes,
      snapshots: snapshots,
    );
  }
}

class StatsSnapshot {
  final int elapsedSeconds;
  final double fps;
  final double cpuUsage;
  final double memoryUsage;
  final int renderSkippedFrames;
  final int outputSkippedFrames;
  final int kbitsPerSec;

  StatsSnapshot({
    required this.elapsedSeconds,
    required this.fps,
    required this.cpuUsage,
    required this.memoryUsage,
    this.renderSkippedFrames = 0,
    this.outputSkippedFrames = 0,
    this.kbitsPerSec = 0,
  });

  Map<String, dynamic> toJson() => {
        'e': elapsedSeconds,
        'f': fps,
        'c': cpuUsage,
        'm': memoryUsage,
        'rs': renderSkippedFrames,
        'os': outputSkippedFrames,
        'k': kbitsPerSec,
      };

  factory StatsSnapshot.fromJson(Map<String, dynamic> json) {
    return StatsSnapshot(
      elapsedSeconds: json['e'] as int,
      fps: (json['f'] as num).toDouble(),
      cpuUsage: (json['c'] as num).toDouble(),
      memoryUsage: (json['m'] as num).toDouble(),
      renderSkippedFrames: json['rs'] as int? ?? 0,
      outputSkippedFrames: json['os'] as int? ?? 0,
      kbitsPerSec: json['k'] as int? ?? 0,
    );
  }
}

enum SessionType { stream, record }
