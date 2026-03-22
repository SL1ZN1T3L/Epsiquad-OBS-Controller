import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import '../providers/obs_provider.dart';
import '../services/update_service.dart';
import '../widgets/widgets.dart';
import 'connections_screen.dart';
import 'quick_control_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _updateChecked = false;
  bool _confirmStopStream = true;
  bool _confirmStopRecord = true;
  int _reminderInterval = 0;
  String _reminderMessage = 'Напоминание';
  bool _isSyncing = false;
  double _syncProgress = 0;
  String _syncStage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkForUpdatesOnStart();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _confirmStopStream =
            prefs.getBool('confirmStopStream') ?? true;
        _confirmStopRecord =
            prefs.getBool('confirmStopRecord') ?? true;
        _reminderInterval = prefs.getInt('reminderInterval') ?? 0;
        _reminderMessage =
            prefs.getString('reminderMessage') ?? 'Напоминание';
      });

      final provider = Provider.of<OBSProvider>(context, listen: false);
      provider.onReminder = _showReminder;
      if (_reminderInterval > 0) {
        provider.startStreamReminders(_reminderInterval, _reminderMessage);
      }
    }
  }

  void _showReminder(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.alarm, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _toggleStreamWithConfirm(OBSProvider provider) async {
    if (provider.status.streamStatus.isActive && _confirmStopStream) {
      final confirmed = await _showConfirmDialog(
        'Остановить стрим?',
        'Стрим идёт ${provider.status.streamStatus.durationString}. Точно остановить?',
      );
      if (!confirmed) return;
    }
    provider.toggleStream();
  }

  Future<void> _toggleRecordWithConfirm(OBSProvider provider) async {
    if (provider.status.recordStatus.isActive && _confirmStopRecord) {
      final confirmed = await _showConfirmDialog(
        'Остановить запись?',
        'Запись идёт ${provider.status.recordStatus.durationString}. Точно остановить?',
      );
      if (!confirmed) return;
    }
    provider.toggleRecord();
  }

  Future<void> _startFullSync(OBSProvider provider) async {
    if (_isSyncing || !provider.isConnected) return;

    setState(() {
      _isSyncing = true;
      _syncProgress = 0;
      _syncStage = '';
    });

    await provider.fullSync((progress, stage) {
      if (mounted) {
        setState(() {
          _syncProgress = progress;
          _syncStage = stage;
        });
      }
    });

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() => _isSyncing = false);
    }
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
                    color: Colors.grey.withValues(alpha:0.1),
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
          if (release.apkDownloadUrl != null)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'download'),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Скачать'),
            )
          else
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'open'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('GitHub'),
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
      case 'download':
        await _downloadAndInstallUpdate(updateService, release);
        break;
      case 'open':
        final uri = Uri.parse(release.htmlUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
    }
  }

  Future<void> _downloadAndInstallUpdate(
      UpdateService updateService, ReleaseInfo release) async {
    double progress = 0;
    bool cancelled = false;
    StateSetter? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          dialogSetState = setDialogState;
          return AlertDialog(
            title: const Text('Загрузка обновления'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 16),
                Text('${(progress * 100).toStringAsFixed(0)}%'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.pop(context);
                },
                child: const Text('Отмена'),
              ),
            ],
          );
        },
      ),
    );

    try {
      final filePath = await updateService.downloadUpdate(
        release,
        onProgress: (p) {
          progress = p;
          if (!cancelled && dialogSetState != null) {
            dialogSetState!(() {});
          }
        },
      );

      if (mounted && !cancelled) {
        Navigator.of(context).pop();

        final install = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Файл загружен'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('APK успешно скачан'),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'При установке ваши данные сохранятся.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Позже'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.install_mobile, size: 18),
                label: const Text('Установить'),
              ),
            ],
          ),
        );

        if (install == true && mounted) {
          await OpenFilex.open(filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        return Stack(
          children: [
            Scaffold(
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
                      onStreamToggle: () => _toggleStreamWithConfirm(provider),
                      onRecordToggle: () => _toggleRecordWithConfirm(provider),
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
                        RefreshIndicator(
                          onRefresh: () => _startFullSync(provider),
                          child: _buildScenesTab(provider),
                        ),
                        RefreshIndicator(
                          onRefresh: () => _startFullSync(provider),
                          child: _buildSourcesTab(provider),
                        ),
                        RefreshIndicator(
                          onRefresh: () => _startFullSync(provider),
                          child: _buildAudioTab(provider),
                        ),
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
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'settings',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  _loadSettings();
                },
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
              if (provider.isConnected) ...[
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'stats',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StatsScreen()),
                  ),
                  tooltip: 'Статистика',
                  child: const Icon(Icons.analytics),
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
            ],
          ),
          bottomNavigationBar: provider.isConnected
              ? CompactControlPanel(
                  status: provider.status,
                  onStreamToggle: () => _toggleStreamWithConfirm(provider),
                  onRecordToggle: () => _toggleRecordWithConfirm(provider),
                  onRecordPause: provider.toggleRecordPause,
                )
              : null,
        ),
            if (_isSyncing)
              _SyncOverlay(
                progress: _syncProgress,
                stage: _syncStage,
              ),
          ],
        );
      },
    );
  }

  Widget _buildScenesTab(OBSProvider provider) {
    return SceneGrid(
      scenes: provider.scenes,
      onSceneTap: (scene) => provider.switchScene(scene.name),
      onSceneLongPress: (scene) => _showScenePreview(provider, scene.name),
      columns: 3,
    );
  }

  void _showScenePreview(OBSProvider provider, String sceneName) {
    showDialog(
      context: context,
      builder: (ctx) => _HomeScenePreviewDialog(
        provider: provider,
        sceneName: sceneName,
      ),
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

class _SyncOverlay extends StatelessWidget {
  final double progress;
  final String stage;

  const _SyncOverlay({
    required this.progress,
    required this.stage,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).toInt();

    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 1.0 ? Colors.green : Colors.blue,
                        ),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Синхронизация...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              if (stage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  stage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }
}

class _HomeScenePreviewDialog extends StatefulWidget {
  final OBSProvider provider;
  final String sceneName;

  const _HomeScenePreviewDialog({
    required this.provider,
    required this.sceneName,
  });

  @override
  State<_HomeScenePreviewDialog> createState() =>
      _HomeScenePreviewDialogState();
}

class _HomeScenePreviewDialogState extends State<_HomeScenePreviewDialog> {
  String? _imageData;
  bool _isLoading = true;
  bool _active = true;
  double _fps = 0;
  static const _frameDuration = Duration(milliseconds: 33); // ~30fps

  @override
  void initState() {
    super.initState();
    _runPreviewLoop();
  }

  @override
  void dispose() {
    _active = false;
    super.dispose();
  }

  Future<void> _runPreviewLoop() async {
    while (_active && mounted) {
      final sw = Stopwatch()..start();
      final data = await widget.provider.getScenePreview(widget.sceneName);
      sw.stop();

      if (!_active || !mounted) break;

      final elapsed = sw.elapsed;
      if (elapsed < _frameDuration) {
        await Future.delayed(_frameDuration - elapsed);
      }

      if (!_active || !mounted) break;

      final totalMs = sw.elapsedMilliseconds > 0
          ? sw.elapsedMilliseconds.clamp(_frameDuration.inMilliseconds, 10000)
          : _frameDuration.inMilliseconds;

      setState(() {
        _imageData = data;
        _isLoading = false;
        _fps = 1000 / totalMs;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.sceneName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${_fps.toStringAsFixed(0)} fps',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            )
          else if (_imageData != null)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Image.memory(
                base64Decode(_imageData!.split(',').last),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(48),
              child: Text('Не удалось загрузить превью'),
            ),
        ],
      ),
    );
  }
}
