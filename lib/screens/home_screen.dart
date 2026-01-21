import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/obs_provider.dart';
import '../services/update_service.dart';
import '../widgets/widgets.dart';
import 'connections_screen.dart';
import 'quick_control_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkForUpdatesOnStart();
  }

  Future<void> _checkForUpdatesOnStart() async {
    if (_updateChecked) return;
    _updateChecked = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final updateService = UpdateService(prefs);

      if (!updateService.shouldAutoCheck()) return;

      final result = await updateService.checkForUpdates();

      if (result.hasUpdate && result.latestRelease != null && mounted) {
        _showUpdateNotification(result, updateService);
      }
    } catch (e) {
      debugPrint('Автопроверка обновлений: $e');
    }
  }

  void _showUpdateNotification(
      UpdateCheckResult result, UpdateService updateService) {
    final release = result.latestRelease!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Доступна версия ${release.version}'),
            ),
          ],
        ),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Подробнее',
          textColor: Colors.white,
          onPressed: () => _showUpdateDialog(result, updateService),
        ),
      ),
    );
  }

  Future<void> _showUpdateDialog(
      UpdateCheckResult result, UpdateService updateService) async {
    final release = result.latestRelease!;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Текущая: ${result.currentVersion}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.new_releases, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Новая: ${release.version}',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (release.body.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Что нового:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Text(release.body,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Пропустить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('Позже'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'open'),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Открыть'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    switch (action) {
      case 'skip':
        await updateService.skipVersion(release.version);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Версия ${release.version} пропущена'),
              backgroundColor: Colors.grey,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;
      case 'open':
        final uri = Uri.parse(release.htmlUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OBSProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Статус подключения
                ConnectionStatusBar(
                  isConnected: provider.isConnected,
                  isConnecting: provider.isConnecting,
                  connection: provider.currentConnection,
                  error: provider.connectionError,
                  onTap: () => _openConnections(context),
                  onReconnect: provider.currentConnection != null
                      ? () => provider.connect(provider.currentConnection!)
                      : null,
                ),

                // Панель управления стримом/записью
                if (provider.isConnected)
                  Flexible(
                    flex: 0,
                    child: ControlPanel(
                      status: provider.status,
                      onStreamToggle: provider.toggleStream,
                      onRecordToggle: provider.toggleRecord,
                      onRecordPause: provider.toggleRecordPause,
                    ),
                  ),

                // Табы
                if (provider.isConnected) ...[
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(icon: Icon(Icons.tv), text: 'Сцены'),
                      Tab(icon: Icon(Icons.layers), text: 'Источники'),
                      Tab(icon: Icon(Icons.volume_up), text: 'Аудио'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Сцены
                        _buildScenesTab(provider),
                        // Источники
                        _buildSourcesTab(provider),
                        // Аудио
                        _buildAudioTab(provider),
                      ],
                    ),
                  ),
                ] else
                  Expanded(
                    child: ConnectionStatusWidget(
                      isConnected: provider.isConnected,
                      status: provider.status,
                    ),
                  ),
              ],
            ),
          ),
          floatingActionButton: provider.isConnected
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'settings',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                      tooltip: 'Настройки',
                      child: const Icon(Icons.settings),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'about',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      ),
                      tooltip: 'О приложении',
                      child: const Icon(Icons.info_outline),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'quick',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const QuickControlScreen()),
                      ),
                      tooltip: 'Быстрое управление',
                      child: const Icon(Icons.grid_view),
                    ),
                  ],
                )
              : null,
          bottomNavigationBar: provider.isConnected
              ? CompactControlPanel(
                  status: provider.status,
                  onStreamToggle: provider.toggleStream,
                  onRecordToggle: provider.toggleRecord,
                  onRecordPause: provider.toggleRecordPause,
                )
              : null,
        );
      },
    );
  }

  Widget _buildScenesTab(OBSProvider provider) {
    return SceneGrid(
      scenes: provider.scenes,
      onSceneTap: (scene) => provider.switchScene(scene.name),
      columns: 3,
    );
  }

  Widget _buildSourcesTab(OBSProvider provider) {
    if (provider.scenes.isEmpty) {
      return const Center(
        child: Text('Загрузка сцен...'),
      );
    }

    // Используем выбранную сцену из провайдера или текущую активную
    final selectedName = provider.selectedSceneForItems ??
        provider.scenes
            .firstWhere((s) => s.isCurrentProgram,
                orElse: () => provider.scenes.first)
            .name;

    return Column(
      children: [
        // Выбор сцены
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: DropdownButtonFormField<String>(
            initialValue: selectedName,
            decoration: InputDecoration(
              labelText: 'Сцена',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            items: provider.scenes.map((scene) {
              return DropdownMenuItem(
                value: scene.name,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (scene.isCurrentProgram)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.play_circle,
                            size: 16, color: Colors.green),
                      ),
                    Flexible(
                      child: Text(
                        scene.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                provider.loadSceneItems(value);
              }
            },
          ),
        ),
        // Список источников - фиксированная высота
        Expanded(
          child: SceneItemList(
            items: provider.currentSceneItems,
            onToggle: (item) => provider.toggleSceneItem(
              selectedName,
              item.sceneItemId,
              !item.isVisible,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioTab(OBSProvider provider) {
    return AudioSourceList(
      sources: provider.audioSources,
      onMuteToggle: (source) => provider.toggleAudioMute(source.name),
      onVolumeChange: (source, volume) =>
          provider.setAudioVolume(source.name, volume),
    );
  }

  void _openConnections(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ConnectionsScreen(),
      ),
    );
  }
}
