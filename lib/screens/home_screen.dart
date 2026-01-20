import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/obs_provider.dart';
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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
                        MaterialPageRoute(builder: (_) => const QuickControlScreen()),
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
        provider.scenes.firstWhere((s) => s.isCurrentProgram, orElse: () => provider.scenes.first).name;

    return Column(
      children: [
        // Выбор сцены
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: DropdownButtonFormField<String>(
            initialValue: selectedName,
            decoration: InputDecoration(
              labelText: 'Сцена',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                        child: Icon(Icons.play_circle, size: 16, color: Colors.green),
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
      onVolumeChange: (source, volume) => provider.setAudioVolume(source.name, volume),
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

