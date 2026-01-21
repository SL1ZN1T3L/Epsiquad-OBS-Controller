import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Модель данных бэкапа
class BackupData {
  final String version;
  final DateTime createdAt;
  final List<OBSConnection> connections;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> quickControlConfigs;

  BackupData({
    required this.version,
    required this.createdAt,
    required this.connections,
    required this.settings,
    required this.quickControlConfigs,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'connections': connections.map((c) => c.toJson()).toList(),
        'settings': settings,
        'quickControlConfigs': quickControlConfigs,
      };

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      version: json['version'] as String? ?? '1.0',
      createdAt: DateTime.parse(json['createdAt'] as String),
      connections: (json['connections'] as List?)
              ?.map((e) => OBSConnection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      settings: json['settings'] as Map<String, dynamic>? ?? {},
      quickControlConfigs: (json['quickControlConfigs'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [],
    );
  }
}

/// Сервис для экспорта/импорта настроек приложения
class BackupService {
  static const _backupVersion = '1.0';
  static const _connectionsKey = 'obs_connections';
  static const _settingsKey = 'app_settings';
  static const _quickControlKey = 'quick_control_buttons';

  final SharedPreferences _prefs;

  BackupService(this._prefs);

  /// Создаёт бэкап всех настроек
  Future<BackupData> createBackup() async {
    // Получаем подключения
    final connectionsJson = _prefs.getString(_connectionsKey);
    final connections = <OBSConnection>[];
    if (connectionsJson != null) {
      try {
        final list = json.decode(connectionsJson) as List;
        connections.addAll(
            list.map((e) => OBSConnection.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('Error parsing connections: $e');
      }
    }

    // Получаем настройки
    final settingsJson = _prefs.getString(_settingsKey);
    final settings = settingsJson != null
        ? json.decode(settingsJson) as Map<String, dynamic>
        : <String, dynamic>{};

    // Получаем Quick Control конфиги
    final quickControlJson = _prefs.getString(_quickControlKey);
    final quickControlConfigs = <Map<String, dynamic>>[];
    if (quickControlJson != null) {
      try {
        final list = json.decode(quickControlJson) as List;
        quickControlConfigs.addAll(list.cast<Map<String, dynamic>>());
      } catch (e) {
        debugPrint('Error parsing quick control: $e');
      }
    }

    return BackupData(
      version: _backupVersion,
      createdAt: DateTime.now(),
      connections: connections,
      settings: settings,
      quickControlConfigs: quickControlConfigs,
    );
  }

  /// Экспортирует бэкап в файл
  Future<String> exportToFile() async {
    final backup = await createBackup();
    final jsonString =
        const JsonEncoder.withIndent('  ').convert(backup.toJson());

    final directory = await _getBackupDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file =
        File('${directory.path}/obs_controller_backup_$timestamp.json');

    await file.writeAsString(jsonString);
    debugPrint('Backup exported to: ${file.path}');

    return file.path;
  }

  /// Получает JSON строку для шаринга
  Future<String> exportToString() async {
    final backup = await createBackup();
    return const JsonEncoder.withIndent('  ').convert(backup.toJson());
  }

  /// Импортирует бэкап из файла
  Future<BackupData> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Файл не найден: $filePath');
    }

    final jsonString = await file.readAsString();
    return importFromString(jsonString);
  }

  /// Импортирует бэкап из JSON строки
  Future<BackupData> importFromString(String jsonString) async {
    try {
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      return BackupData.fromJson(jsonData);
    } catch (e) {
      throw Exception('Неверный формат бэкапа: $e');
    }
  }

  /// Применяет бэкап к текущим настройкам
  Future<void> restoreBackup(
    BackupData backup, {
    bool restoreConnections = true,
    bool restoreSettings = true,
    bool restoreQuickControl = true,
  }) async {
    if (restoreConnections && backup.connections.isNotEmpty) {
      final connectionsJson =
          json.encode(backup.connections.map((c) => c.toJson()).toList());
      await _prefs.setString(_connectionsKey, connectionsJson);
      debugPrint('Restored ${backup.connections.length} connections');
    }

    if (restoreSettings && backup.settings.isNotEmpty) {
      await _prefs.setString(_settingsKey, json.encode(backup.settings));
      debugPrint('Restored settings');
    }

    if (restoreQuickControl && backup.quickControlConfigs.isNotEmpty) {
      await _prefs.setString(
          _quickControlKey, json.encode(backup.quickControlConfigs));
      debugPrint(
          'Restored ${backup.quickControlConfigs.length} quick control configs');
    }
  }

  /// Получает список файлов бэкапов
  Future<List<File>> getBackupFiles() async {
    final directory = await _getBackupDirectory();
    if (!await directory.exists()) {
      return [];
    }

    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    // Сортируем по дате (новые первые)
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    return files;
  }

  /// Удаляет файл бэкапа
  Future<void> deleteBackup(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _getBackupDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${baseDir.path}/OBS_Controller_Backups');

    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    return backupDir;
  }
}
