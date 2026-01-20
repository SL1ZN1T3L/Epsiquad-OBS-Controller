import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class StorageService {
  static const _connectionsKey = 'obs_connections';
  static const _settingsKey = 'app_settings';
  
  final SharedPreferences _prefs;
  
  StorageService(this._prefs);
  
  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // ==================== Подключения ====================

  Future<List<OBSConnection>> getConnections() async {
    final data = _prefs.getString(_connectionsKey);
    if (data == null) return [];
    
    try {
      final list = json.decode(data) as List;
      return list
          .map((e) => OBSConnection.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveConnections(List<OBSConnection> connections) async {
    final data = json.encode(connections.map((c) => c.toJson()).toList());
    await _prefs.setString(_connectionsKey, data);
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
      connections[i] = connections[i].copyWith(isDefault: connections[i].id == id);
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
  };
}
