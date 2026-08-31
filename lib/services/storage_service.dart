import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class StorageService {
  static const _connectionsKey = 'obs_connections';
  static const _settingsKey = 'app_settings';
  static const _pwPrefix = 'conn_pw_';

  /// Флаг однократной миграции паролей из открытого SharedPreferences
  /// в защищённое хранилище. Публичная константа — чтобы сбрасывать её
  /// при восстановлении бэкапа со старым (незашифрованным) форматом.
  static const pwMigrationFlag = 'pw_migrated_v1';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  StorageService(this._prefs, {FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    final service = StorageService(prefs);
    await service._migratePasswordsIfNeeded();
    return service;
  }

  // ==================== Подключения ====================

  Future<List<OBSConnection>> getConnections() async {
    final data = _prefs.getString(_connectionsKey);
    if (data == null) return [];

    try {
      final list = json.decode(data) as List;
      final result = <OBSConnection>[];
      for (final e in list) {
        final map = e as Map<String, dynamic>;
        var conn = OBSConnection.fromJson(map);
        // Пароль хранится отдельно в защищённом хранилище. В JSON он
        // остаётся только как legacy (до миграции) — берём его как fallback.
        if (conn.password == null || conn.password!.isEmpty) {
          final pw = await _readSecurePassword(conn.id);
          if (pw != null && pw.isNotEmpty) {
            conn = conn.copyWith(password: pw);
          }
        }
        result.add(conn);
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<void> saveConnections(List<OBSConnection> connections) async {
    final list = <Map<String, dynamic>>[];
    for (final c in connections) {
      final map = c.toJson();
      final pw = c.password;
      bool storedSecurely = false;
      try {
        final key = _pwPrefix + c.id;
        if (pw != null && pw.isNotEmpty) {
          await _secure.write(key: key, value: pw);
        } else {
          await _secure.delete(key: key);
        }
        storedSecurely = true;
      } catch (_) {
        // Защищённое хранилище недоступно на устройстве — деградируем и
        // оставляем пароль в JSON, чтобы подключение не сломалось.
        storedSecurely = false;
      }
      if (storedSecurely) {
        map.remove('password');
      }
      list.add(map);
    }
    await _prefs.setString(_connectionsKey, json.encode(list));
  }

  Future<String?> _readSecurePassword(String id) async {
    try {
      return await _secure.read(key: _pwPrefix + id);
    } catch (_) {
      return null;
    }
  }

  /// Переносит пароли из открытого JSON в защищённое хранилище один раз.
  Future<void> _migratePasswordsIfNeeded() async {
    if (_prefs.getBool(pwMigrationFlag) ?? false) return;
    try {
      final raw = _prefs.getString(_connectionsKey);
      if (raw != null) {
        final list = json.decode(raw) as List;
        final hasPlain = list.any((e) {
          final pw = (e as Map)['password'];
          return pw is String && pw.isNotEmpty;
        });
        if (hasPlain) {
          final conns = list
              .map((e) => OBSConnection.fromJson(e as Map<String, dynamic>))
              .toList();
          // saveConnections запишет пароли в secure и уберёт их из JSON.
          await saveConnections(conns);
        }
      }
      await _prefs.setBool(pwMigrationFlag, true);
    } catch (_) {
      // Молча — при неудаче getConnections всё равно прочитает legacy-пароль.
    }
  }

  Future<OBSConnection> addConnection(OBSConnection connection) async {
    final connections = await getConnections();

    // Генерируем ID если нет
    final newConnection = connection.id.isEmpty
        ? connection.copyWith(id: const Uuid().v4())
        : connection;

    // Если это первое подключение - делаем его по умолчанию
    if (connections.isEmpty) {
      connections.add(newConnection.copyWith(isDefault: true));
    } else {
      // Если новое подключение по умолчанию - убираем флаг у других
      if (newConnection.isDefault) {
        for (var i = 0; i < connections.length; i++) {
          connections[i] = connections[i].copyWith(isDefault: false);
        }
      }
      connections.add(newConnection);
    }

    await saveConnections(connections);
    return newConnection;
  }

  Future<void> updateConnection(OBSConnection connection) async {
    final connections = await getConnections();
    final index = connections.indexWhere((c) => c.id == connection.id);

    if (index != -1) {
      // Если это подключение по умолчанию - убираем флаг у других
      if (connection.isDefault) {
        for (var i = 0; i < connections.length; i++) {
          if (i != index) {
            connections[i] = connections[i].copyWith(isDefault: false);
          }
        }
      }
      connections[index] = connection;
      await saveConnections(connections);
    }
  }

  Future<void> deleteConnection(String id) async {
    final connections = await getConnections();
    connections.removeWhere((c) => c.id == id);

    // Удаляем связанный пароль из защищённого хранилища.
    try {
      await _secure.delete(key: _pwPrefix + id);
    } catch (_) {}

    // Если удалили подключение по умолчанию - делаем первое по умолчанию
    if (connections.isNotEmpty && !connections.any((c) => c.isDefault)) {
      connections[0] = connections[0].copyWith(isDefault: true);
    }

    await saveConnections(connections);
  }

  Future<OBSConnection?> getDefaultConnection() async {
    final connections = await getConnections();
    try {
      return connections.firstWhere((c) => c.isDefault);
    } catch (e) {
      return connections.isNotEmpty ? connections.first : null;
    }
  }

  Future<void> setDefaultConnection(String id) async {
    final connections = await getConnections();
    for (var i = 0; i < connections.length; i++) {
      connections[i] =
          connections[i].copyWith(isDefault: connections[i].id == id);
    }
    await saveConnections(connections);
  }

  // ==================== Настройки приложения ====================

  Future<Map<String, dynamic>> getSettings() async {
    final data = _prefs.getString(_settingsKey);
    if (data == null) return _defaultSettings;

    try {
      return json.decode(data) as Map<String, dynamic>;
    } catch (e) {
      return _defaultSettings;
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await _prefs.setString(_settingsKey, json.encode(settings));
  }

  Future<T> getSetting<T>(String key, T defaultValue) async {
    final settings = await getSettings();
    return settings[key] as T? ?? defaultValue;
  }

  Future<void> setSetting(String key, dynamic value) async {
    final settings = await getSettings();
    settings[key] = value;
    await saveSettings(settings);
  }

  static final _defaultSettings = <String, dynamic>{
    'gridColumns': 3,
    'showScenePreview': true,
    'autoConnect': true,
    'keepScreenOn': true,
    'darkMode': true,
    'hapticFeedback': true,
    'confirmActions': true,
    'showHiddenScenes': false,
    'fullscreenMode': false,
  };
}
