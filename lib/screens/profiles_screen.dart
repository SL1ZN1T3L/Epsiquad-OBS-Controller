import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'dart:convert';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<QuickControlProfile> _profiles = [];
  String? _activeProfileId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Загружаем профили
    final profilesJson = prefs.getString('quickControlProfiles');
    if (profilesJson != null) {
      try {
        final list = json.decode(profilesJson) as List;
        _profiles = list
            .map((p) => QuickControlProfile.fromJson(p as Map<String, dynamic>))
            .toList();
      } catch (e) {
        _profiles = [];
      }
    }
    
    // Загружаем активный профиль
    _activeProfileId = prefs.getString('activeProfileId');
    
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString('quickControlProfiles', json);
  }

  Future<void> _setActiveProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeProfileId', profileId);
    
    // Загружаем конфигурацию профиля в основную конфигурацию
    final profile = _profiles.firstWhere((p) => p.id == profileId);
    final config = QuickControlConfig(
      buttons: profile.buttons,
      columns: profile.columns,
    );
    await prefs.setString('quickControlConfig', config.toJsonString());
    
    setState(() => _activeProfileId = profileId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Профиль "${profile.name}" активирован')),
      );
    }
  }

  Future<void> _createProfile() async {
    final controller = TextEditingController();
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый профиль'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Название профиля',
            hintText: 'Например: Стрим YouTube',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    
    if (name != null && name.isNotEmpty) {
      final profile = QuickControlProfile(
        id: const Uuid().v4(),
        name: name,
        buttons: [],
      );
      
      setState(() => _profiles.add(profile));
      await _saveProfiles();
    }
  }

  Future<void> _saveCurrentAsProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('quickControlConfig');
    
    if (configJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет текущей конфигурации для сохранения')),
      );
      return;
    }
    
    final controller = TextEditingController();
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сохранить текущую конфигурацию'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Название профиля',
            hintText: 'Например: Моя текущая настройка',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    
    if (name != null && name.isNotEmpty) {
      final config = QuickControlConfig.fromJsonString(configJson);
      final profile = QuickControlProfile(
        id: const Uuid().v4(),
        name: name,
        buttons: config.buttons,
        columns: config.columns,
      );
      
      setState(() => _profiles.add(profile));
      await _saveProfiles();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Профиль "$name" сохранён')),
        );
      }
    }
  }

  Future<void> _deleteProfile(QuickControlProfile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить профиль?'),
        content: Text('Вы уверены, что хотите удалить профиль "${profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      setState(() => _profiles.removeWhere((p) => p.id == profile.id));
      await _saveProfiles();
      
      if (_activeProfileId == profile.id) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('activeProfileId');
        setState(() => _activeProfileId = null);
      }
    }
  }

  Future<void> _renameProfile(QuickControlProfile profile) async {
    final controller = TextEditingController(text: profile.name);
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать профиль'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Название профиля',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    
    if (name != null && name.isNotEmpty) {
      final index = _profiles.indexWhere((p) => p.id == profile.id);
      if (index != -1) {
        setState(() {
          _profiles[index] = profile.copyWith(name: name);
        });
        await _saveProfiles();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профили'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Сохранить текущую конфигурацию',
            onPressed: _saveCurrentAsProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_tree, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Нет профилей',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Создайте профиль для сохранения\nнастроек быстрого управления',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _profiles.length,
                  itemBuilder: (context, index) {
                    final profile = _profiles[index];
                    final isActive = profile.id == _activeProfileId;
                    
                    return Card(
                      elevation: isActive ? 4 : 1,
                      color: isActive ? Colors.blue.withOpacity(0.1) : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive ? Colors.blue : Colors.grey,
                          child: Text(
                            profile.name[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(profile.name)),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Активный',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${profile.buttons.length} кнопок • Создан ${_formatDate(profile.createdAt)}',
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            if (!isActive)
                              PopupMenuItem(
                                onTap: () => _setActiveProfile(profile.id),
                                child: const Row(
                                  children: [
                                    Icon(Icons.check_circle, size: 20),
                                    SizedBox(width: 8),
                                    Text('Активировать'),
                                  ],
                                ),
                              ),
                            PopupMenuItem(
                              onTap: () => Future.delayed(
                                Duration.zero,
                                () => _renameProfile(profile),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.edit, size: 20),
                                  SizedBox(width: 8),
                                  Text('Переименовать'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              onTap: () => Future.delayed(
                                Duration.zero,
                                () => _deleteProfile(profile),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Удалить', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _setActiveProfile(profile.id),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProfile,
        icon: const Icon(Icons.add),
        label: const Text('Новый профиль'),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) return 'Сегодня';
    if (diff.inDays == 1) return 'Вчера';
    if (diff.inDays < 7) return '${diff.inDays} дн. назад';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} нед. назад';
    return '${date.day}.${date.month}.${date.year}';
  }
}
