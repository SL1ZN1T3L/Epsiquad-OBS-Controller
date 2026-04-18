import 'dart:collection';
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? details;

  LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    this.details,
  }) : timestamp = DateTime.now();

  String get levelIcon {
    switch (level) {
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  String get timeString {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  String get dateTimeString {
    return '${timestamp.year}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')} '
        '$timeString';
  }

  String toFormattedString() {
    final base = '$dateTimeString [$levelIcon/$tag] $message';
    if (details != null) {
      return '$base\n  $details';
    }
    return base;
  }

  @override
  String toString() => toFormattedString();
}

class LogService {
  static final LogService _instance = LogService._();
  static LogService get instance => _instance;
  LogService._();

  static const int _maxEntries = 2000;

  final _entries = Queue<LogEntry>();
  final _listeners = <VoidCallback>[];

  LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  bool enabled = true;

  UnmodifiableListView<LogEntry> get entries =>
      UnmodifiableListView(_entries.toList());

  int get count => _entries.length;

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final listener in _listeners) {
      listener();
    }
  }

  void _log(LogLevel level, String tag, String message, [String? details]) {
    if (!enabled) return;
    if (level.index < minLevel.index) return;

    final entry = LogEntry(
      level: level,
      tag: tag,
      message: message,
      details: details,
    );

    _entries.addLast(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }

    // Дублируем в debugPrint для консоли
    debugPrint('[${entry.levelIcon}/$tag] $message');
    if (details != null) {
      debugPrint('  $details');
    }

    _notify();
  }

  void d(String tag, String message, [String? details]) =>
      _log(LogLevel.debug, tag, message, details);

  void i(String tag, String message, [String? details]) =>
      _log(LogLevel.info, tag, message, details);

  void w(String tag, String message, [String? details]) =>
      _log(LogLevel.warning, tag, message, details);

  void e(String tag, String message, [String? details]) =>
      _log(LogLevel.error, tag, message, details);

  void clear() {
    _entries.clear();
    _notify();
  }

  List<LogEntry> filter({LogLevel? level, String? tag, String? query}) {
    return _entries.where((entry) {
      if (level != null && entry.level != level) return false;
      if (tag != null && entry.tag != tag) return false;
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        if (!entry.message.toLowerCase().contains(q) &&
            !(entry.details?.toLowerCase().contains(q) ?? false) &&
            !entry.tag.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Set<String> get allTags =>
      _entries.map((e) => e.tag).toSet();

  String exportAsText() {
    final buffer = StringBuffer();
    buffer.writeln('=== OBS Controller Logs ===');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Entries: ${_entries.length}');
    buffer.writeln('');

    for (final entry in _entries) {
      buffer.writeln(entry.toFormattedString());
    }

    return buffer.toString();
  }
}

// Shortcut для удобного доступа
final log = LogService.instance;
