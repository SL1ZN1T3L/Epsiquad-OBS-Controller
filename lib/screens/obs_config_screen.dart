import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/obs_provider.dart';
import '../services/log_service.dart';
import '../models/models.dart';

class OBSConfigScreen extends StatefulWidget {
  const OBSConfigScreen({super.key});

  @override
  State<OBSConfigScreen> createState() => _OBSConfigScreenState();
}

class _OBSConfigScreenState extends State<OBSConfigScreen> {
  // Scene Collections
  List<String> _sceneCollections = [];
  String? _currentCollection;

  // Profiles
  List<String> _profiles = [];
  String? _currentProfile;

  // Transitions
  List<OBSSceneTransition> _transitions = [];
  String? _currentTransition;
  int _transitionDuration = 300;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final provider = Provider.of<OBSProvider>(context, listen: false);
    if (!provider.isConnected) return;

    setState(() => _isLoading = true);

    try {
      // Scene Collections
      final collData = await provider.obsService.getSceneCollectionList();
      _sceneCollections = (collData['sceneCollections'] as List? ?? [])
          .map((e) => e as String)
          .toList();
      _currentCollection = collData['currentSceneCollectionName'] as String?;

      // Profiles
      final profData = await provider.obsService.getProfileList();
      _profiles = (profData['profiles'] as List? ?? [])
          .map((e) => e as String)
          .toList();
      _currentProfile = profData['currentProfileName'] as String?;

      // Transitions
      final transData = await provider.obsService.getSceneTransitionList();
      _transitions = (transData['sceneTransitions'] as List? ?? [])
          .map((e) => OBSSceneTransition.fromJson(e as Map<String, dynamic>))
          .toList();
      _currentTransition = transData['currentSceneTransitionName'] as String?;

      try {
        final currentTrans = await provider.obsService.getCurrentSceneTransition();
        _transitionDuration = currentTrans['transitionDuration'] as int? ?? 300;
      } catch (_) {}
    } catch (e) {
      log.e('Config', 'Error loading config data', e.toString());
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Конфигурация OBS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<OBSProvider>(
              builder: (context, provider, _) {
                if (!provider.isConnected) {
                  return const Center(child: Text('Не подключено к OBS'));
                }

                return RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Scene Collections
                      _buildSectionHeader('Коллекции сцен', Icons.collections),
                      const SizedBox(height: 8),
                      _buildSceneCollectionsCard(provider),

                      const SizedBox(height: 24),

                      // Profiles
                      _buildSectionHeader('Профили OBS', Icons.person),
                      const SizedBox(height: 8),
                      _buildProfilesCard(provider),

                      const SizedBox(height: 24),

                      // Transitions
                      _buildSectionHeader('Переходы', Icons.swap_horiz),
                      const SizedBox(height: 8),
                      _buildTransitionsCard(provider),

                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildSceneCollectionsCard(OBSProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_sceneCollections.isEmpty)
              const Text('Нет доступных коллекций',
                  style: TextStyle(color: Colors.grey))
            else
              ...(_sceneCollections.map((name) {
                final isCurrent = name == _currentCollection;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isCurrent ? Icons.check_circle : Icons.circle_outlined,
                    color: isCurrent ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: isCurrent
                      ? null
                      : () => _switchSceneCollection(provider, name),
                );
              })),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilesCard(OBSProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_profiles.isEmpty)
              const Text('Нет доступных профилей',
                  style: TextStyle(color: Colors.grey))
            else
              ...(_profiles.map((name) {
                final isCurrent = name == _currentProfile;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isCurrent ? Icons.check_circle : Icons.circle_outlined,
                    color: isCurrent ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: isCurrent
                      ? null
                      : () => _switchProfile(provider, name),
                );
              })),
          ],
        ),
      ),
    );
  }

  Widget _buildTransitionsCard(OBSProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Выбор перехода
            const Text('Текущий переход',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            if (_transitions.isEmpty)
              const Text('Нет доступных переходов',
                  style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _transitions.map((t) {
                  final isCurrent = t.name == _currentTransition;
                  return ChoiceChip(
                    label: Text(t.name),
                    selected: isCurrent,
                    selectedColor: Colors.blue.withValues(alpha: 0.3),
                    onSelected: (_) =>
                        _switchTransition(provider, t.name),
                  );
                }).toList(),
              ),

            const SizedBox(height: 20),

            // Длительность перехода
            Row(
              children: [
                const Text('Длительность: ',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                Text(
                  '$_transitionDuration мс',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('50', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Expanded(
                  child: Slider(
                    value: _transitionDuration.toDouble().clamp(50, 5000),
                    min: 50,
                    max: 5000,
                    divisions: 99,
                    label: '$_transitionDuration мс',
                    onChanged: (value) {
                      setState(() => _transitionDuration = value.round());
                    },
                    onChangeEnd: (value) {
                      _setTransitionDuration(provider, value.round());
                    },
                  ),
                ),
                const Text('5000', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),

            // Быстрые пресеты
            Wrap(
              spacing: 8,
              children: [100, 200, 300, 500, 1000, 2000].map((ms) {
                return ActionChip(
                  label: Text('$msмс', style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    setState(() => _transitionDuration = ms);
                    _setTransitionDuration(provider, ms);
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchSceneCollection(OBSProvider provider, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сменить коллекцию?'),
        content: Text(
          'Переключиться на "$name"?\n\nOBS может кратковременно зависнуть при смене коллекции.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Переключить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await provider.obsService.setCurrentSceneCollection(name);
      setState(() => _currentCollection = name);
      HapticFeedback.mediumImpact();

      // Даём OBS время на переключение
      await Future.delayed(const Duration(seconds: 2));
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _switchProfile(OBSProvider provider, String name) async {
    try {
      await provider.obsService.setCurrentProfile(name);
      setState(() => _currentProfile = name);
      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Профиль: $name'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _switchTransition(OBSProvider provider, String name) async {
    try {
      await provider.obsService.setCurrentSceneTransition(name);
      setState(() => _currentTransition = name);
      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _setTransitionDuration(OBSProvider provider, int ms) async {
    try {
      await provider.obsService.setCurrentSceneTransitionDuration(ms);
    } catch (e) {
      log.w('Config', 'Error setting transition duration', e.toString());
    }
  }
}
