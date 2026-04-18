import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/session_stats.dart';
import 'log_service.dart';

const _tag = 'History';

/// Интервал сбора снимков статистики (секунды)
const int kSnapshotIntervalSeconds = 10;

class StatsHistoryService {
  static final StatsHistoryService _instance = StatsHistoryService._();
  static StatsHistoryService get instance => _instance;
  StatsHistoryService._();

  List<SessionStats> _sessions = [];
  bool _loaded = false;

  // Текущая сессия сбора
  final List<StatsSnapshot> _streamSnapshots = [];
  final List<StatsSnapshot> _recordSnapshots = [];
  DateTime? _streamStart;
  DateTime? _recordStart;

  List<SessionStats> get sessions => List.unmodifiable(_sessions);
  List<SessionStats> get streamSessions =>
      _sessions.where((s) => s.type == SessionType.stream).toList();
  List<SessionStats> get recordSessions =>
      _sessions.where((s) => s.type == SessionType.record).toList();

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        _sessions = list
            .map((e) => SessionStats.fromJson(e as Map<String, dynamic>))
            .toList();
        _sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
      }
      _loaded = true;
      log.i(_tag, 'Loaded ${_sessions.length} sessions');
    } catch (e) {
      log.e(_tag, 'Error loading history', e.toString());
      _sessions = [];
      _loaded = true;
    }
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final json = jsonEncode(_sessions.map((s) => s.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      log.e(_tag, 'Error saving history', e.toString());
    }
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/obs_stats_history.json');
  }

  // ==================== Сбор статистики ====================

  void onStreamStarted() {
    _streamStart = DateTime.now();
    _streamSnapshots.clear();
    log.d(_tag, 'Stream session started');
  }

  void onStreamStopped() {
    if (_streamStart == null) return;

    final session = SessionStats(
      id: const Uuid().v4(),
      type: SessionType.stream,
      startTime: _streamStart!,
      endTime: DateTime.now(),
      durationSeconds: DateTime.now().difference(_streamStart!).inSeconds,
      snapshots: List.from(_streamSnapshots),
    );

    _sessions.insert(0, session);
    _streamSnapshots.clear();
    _streamStart = null;
    _save();
    log.i(_tag, 'Stream session saved: ${session.durationString}');
  }

  void onRecordStarted() {
    _recordStart = DateTime.now();
    _recordSnapshots.clear();
    log.d(_tag, 'Record session started');
  }

  void onRecordStopped() {
    if (_recordStart == null) return;

    final session = SessionStats(
      id: const Uuid().v4(),
      type: SessionType.record,
      startTime: _recordStart!,
      endTime: DateTime.now(),
      durationSeconds: DateTime.now().difference(_recordStart!).inSeconds,
      snapshots: List.from(_recordSnapshots),
    );

    _sessions.insert(0, session);
    _recordSnapshots.clear();
    _recordStart = null;
    _save();
    log.i(_tag, 'Record session saved: ${session.durationString}');
  }

  /// Вызывается периодически для записи снимка статистики
  void addSnapshot({
    required double fps,
    required double cpuUsage,
    required double memoryUsage,
    int renderSkippedFrames = 0,
    int outputSkippedFrames = 0,
    int kbitsPerSec = 0,
  }) {
    if (_streamStart != null) {
      _streamSnapshots.add(StatsSnapshot(
        elapsedSeconds: DateTime.now().difference(_streamStart!).inSeconds,
        fps: fps,
        cpuUsage: cpuUsage,
        memoryUsage: memoryUsage,
        renderSkippedFrames: renderSkippedFrames,
        outputSkippedFrames: outputSkippedFrames,
        kbitsPerSec: kbitsPerSec,
      ));
    }

    if (_recordStart != null) {
      _recordSnapshots.add(StatsSnapshot(
        elapsedSeconds: DateTime.now().difference(_recordStart!).inSeconds,
        fps: fps,
        cpuUsage: cpuUsage,
        memoryUsage: memoryUsage,
        renderSkippedFrames: renderSkippedFrames,
        outputSkippedFrames: outputSkippedFrames,
      ));
    }
  }

  bool get isCollecting => _streamStart != null || _recordStart != null;

  // ==================== Управление ====================

  Future<void> updateSession(SessionStats updated) async {
    final index = _sessions.indexWhere((s) => s.id == updated.id);
    if (index != -1) {
      _sessions[index] = updated;
      await _save();
    }
  }

  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    await _save();
  }

  Future<void> clearAll() async {
    _sessions.clear();
    await _save();
    log.i(_tag, 'All history cleared');
  }
}
