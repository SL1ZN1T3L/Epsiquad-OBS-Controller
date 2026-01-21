import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/backup_service.dart';
import '../services/update_service.dart';
import '../providers/obs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  BackupService? _backupService;
  UpdateService? _updateService;
  bool _isLoading = false;
  bool _isCheckingUpdate = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _backupService = BackupService(prefs);
        _updateService = UpdateService(prefs);
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Настройки'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Секция бэкапов
          _buildSectionHeader('Резервное копирование'),
          const SizedBox(height: 8),

          _AnimatedCard(
            child: ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blue),
              title: const Text('Экспорт настроек'),
              subtitle: const Text('Сохранить в файл'),
              trailing: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isLoading ? null : _exportBackup,
            ),
          ),

          const SizedBox(height: 8),

          _AnimatedCard(
            child: ListTile(
              leading: const Icon(Icons.share, color: Colors.green),
              title: const Text('Поделиться настройками'),
              subtitle: const Text('Отправить как текст'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isLoading ? null : _shareBackup,
            ),
          ),

          const SizedBox(height: 8),

          _AnimatedCard(
            child: ListTile(
              leading: const Icon(Icons.download, color: Colors.orange),
              title: const Text('Импорт настроек'),
              subtitle: const Text('Загрузить из файла'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isLoading ? null : _importBackup,
            ),
          ),

          const SizedBox(height: 8),

          _AnimatedCard(
            child: ListTile(
              leading: const Icon(Icons.content_paste, color: Colors.purple),
              title: const Text('Импорт из буфера'),
              subtitle: const Text('Вставить JSON'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isLoading ? null : _importFromClipboard,
            ),
          ),

          const SizedBox(height: 24),

          // Секция скринсейвера
          _buildSectionHeader('Скринсейвер'),
          const SizedBox(height: 8),

          _ScreenSaverSettingsCard(),

          const SizedBox(height: 24),

          // Секция обновлений
          _buildSectionHeader('Обновления'),
          const SizedBox(height: 8),

          _UpdateSettingsCard(
            updateService: _updateService!,
            isCheckingUpdate: _isCheckingUpdate,
            onCheckUpdate: _checkForUpdates,
          ),

          const SizedBox(height: 24),

          // Секция файлов бэкапов
          _buildSectionHeader('Сохранённые бэкапы'),
          const SizedBox(height: 8),

          FutureBuilder<List<File>>(
            future: _backupService!.getBackupFiles(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const _AnimatedCard(
                  child: ListTile(
                    leading: Icon(Icons.folder_open, color: Colors.grey),
                    title: Text('Нет сохранённых бэкапов'),
                    subtitle: Text('Создайте первый бэкап'),
                  ),
                );
              }

              return Column(
                children: snapshot.data!.map((file) {
                  final fileName = file.path.split('/').last;
                  final date = file.lastModifiedSync();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AnimatedCard(
                      child: ListTile(
                        leading:
                            const Icon(Icons.description, color: Colors.blue),
                        title: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(_formatDate(date)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'restore':
                                _restoreFromFile(file.path);
                                break;
                              case 'delete':
                                _deleteBackup(file.path);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'restore',
                              child: Row(
                                children: [
                                  Icon(Icons.restore, size: 20),
                                  SizedBox(width: 8),
                                  Text('Восстановить'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Удалить',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // Информация о бэкапе
          const _AnimatedCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Что сохраняется',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _InfoRow(icon: Icons.link, text: 'Подключения к OBS'),
                  _InfoRow(icon: Icons.settings, text: 'Настройки приложения'),
                  _InfoRow(
                      icon: Icons.grid_view,
                      text: 'Конфигурация Quick Control'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportBackup() async {
    setState(() => _isLoading = true);

    try {
      final path = await _backupService!.exportToFile();
      if (mounted) {
        _showSuccess('Бэкап сохранён:\n${path.split('/').last}');
        setState(() {}); // Обновить список файлов
      }
    } catch (e) {
      if (mounted) {
        _showError('Ошибка экспорта: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _shareBackup() async {
    setState(() => _isLoading = true);

    try {
      final jsonString = await _backupService!.exportToString();
      await Share.share(
        jsonString,
        subject: 'OBS Controller Backup',
      );
    } catch (e) {
      if (mounted) {
        _showError('Ошибка: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        await _restoreFromFile(result.files.single.path!);
      }
    } catch (e) {
      if (mounted) {
        _showError('Ошибка выбора файла: $e');
      }
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text == null || clipboardData!.text!.isEmpty) {
        _showError('Буфер обмена пуст');
        return;
      }

      final backup =
          await _backupService!.importFromString(clipboardData.text!);
      await _showRestoreDialog(backup);
    } catch (e) {
      if (mounted) {
        _showError('Неверный формат: $e');
      }
    }
  }

  Future<void> _restoreFromFile(String path) async {
    try {
      final backup = await _backupService!.importFromFile(path);
      await _showRestoreDialog(backup);
    } catch (e) {
      if (mounted) {
        _showError('Ошибка чтения файла: $e');
      }
    }
  }

  Future<void> _showRestoreDialog(BackupData backup) async {
    bool restoreConnections = true;
    bool restoreSettings = true;
    bool restoreQuickControl = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Восстановить бэкап?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Создан: ${_formatDate(backup.createdAt)}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: Text('Подключения (${backup.connections.length})'),
                value: restoreConnections,
                onChanged: (v) => setDialogState(() => restoreConnections = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('Настройки'),
                value: restoreSettings,
                onChanged: (v) => setDialogState(() => restoreSettings = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: Text(
                    'Quick Control (${backup.quickControlConfigs.length})'),
                value: restoreQuickControl,
                onChanged: (v) =>
                    setDialogState(() => restoreQuickControl = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              const Text(
                '⚠️ Текущие настройки будут заменены',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Восстановить'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      try {
        await _backupService!.restoreBackup(
          backup,
          restoreConnections: restoreConnections,
          restoreSettings: restoreSettings,
          restoreQuickControl: restoreQuickControl,
        );

        // Перезагружаем данные провайдера
        if (mounted) {
          await context.read<OBSProvider>().loadConnections();
          _showSuccess(
              'Настройки восстановлены!\nПерезапустите приложение для полного применения.');
        }
      } catch (e) {
        if (mounted) {
          _showError('Ошибка восстановления: $e');
        }
      }
    }
  }

  Future<void> _deleteBackup(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить бэкап?'),
        content: const Text('Это действие нельзя отменить'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _backupService!.deleteBackup(path);
      if (mounted) {
        setState(() {});
        _showSuccess('Бэкап удалён');
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_updateService == null || _isCheckingUpdate) return;

    setState(() => _isCheckingUpdate = true);

    try {
      final result = await _updateService!.checkForUpdates(force: true);

      if (!mounted) return;

      if (result.error != null) {
        _showError(result.error!);
      } else if (result.hasUpdate && result.latestRelease != null) {
        await _showUpdateDialog(result);
      } else {
        _showSuccess('У вас последняя версия (${result.currentVersion})');
      }
    } catch (e) {
      if (mounted) {
        _showError('Ошибка проверки: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  Future<void> _showUpdateDialog(UpdateCheckResult result) async {
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
                    'Текущая версия: ${result.currentVersion}',
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
                    'Новая версия: ${release.version}',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (release.body.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Что нового:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      release.body,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.security, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ваши настройки будут сохранены',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
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
              onPressed: () => Navigator.pop(context, 'github'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('GitHub'),
            ),
        ],
      ),
    );

    if (!mounted) return;

    switch (action) {
      case 'skip':
        await _updateService!.skipVersion(release.version);
        _showSuccess('Версия ${release.version} пропущена');
        break;
      case 'download':
        await _downloadAndInstallUpdate(release);
        break;
      case 'github':
        await _openGitHubRelease(release.htmlUrl);
        break;
    }
  }

  Future<void> _downloadAndInstallUpdate(ReleaseInfo release) async {
    // Показываем диалог загрузки
    double progress = 0;
    bool cancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
        ),
      ),
    );

    try {
      final filePath = await _updateService!.downloadUpdate(
        release,
        onProgress: (p) {
          progress = p;
          // Обновляем диалог
          if (mounted && !cancelled) {
            setState(() {});
          }
        },
      );

      if (mounted && !cancelled) {
        Navigator.of(context).pop(); // Закрываем диалог загрузки
        await _showInstallDialog(filePath, release.version);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showError('Ошибка загрузки: $e');
      }
    }
  }

  Future<void> _showInstallDialog(String filePath, String version) async {
    final install = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Файл загружен'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('APK успешно скачан'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Файл: ${filePath.split('/').last}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'При установке ваши данные (подключения, настройки, Quick Control) сохранятся.',
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
      try {
        // Открываем APK через файловый менеджер или установщик
        await _openApkFile(filePath);
      } catch (e) {
        _showError('Ошибка: $e');
      }
    }
  }

  Future<void> _openApkFile(String filePath) async {
    // Используем url_launcher для открытия файла
    // На Android нужно использовать FileProvider для доступа к файлу
    final uri = Uri.parse('file://$filePath');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback: показываем путь к файлу
      if (mounted) {
        _showSuccess(
            'APK сохранён: $filePath\nУстановите вручную через файловый менеджер.');
      }
    }
  }

  Future<void> _openGitHubRelease(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('Не удалось открыть ссылку');
    }
  }
}

/// Анимированная карточка с fade и slide эффектом
class _AnimatedCard extends StatefulWidget {
  final Widget child;

  const _AnimatedCard({required this.child});

  @override
  State<_AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<_AnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Card(
          elevation: 2,
          child: widget.child,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _ScreenSaverSettingsCard extends StatefulWidget {
  @override
  State<_ScreenSaverSettingsCard> createState() =>
      _ScreenSaverSettingsCardState();
}

class _ScreenSaverSettingsCardState extends State<_ScreenSaverSettingsCard> {
  bool _fullscreen = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString('app_settings');
    if (settingsJson != null) {
      try {
        final settings = Map<String, dynamic>.from(jsonDecode(settingsJson));
        setState(() {
          _fullscreen = settings['fullscreenMode'] ?? false;
          _isLoading = false;
        });
      } catch (e) {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFullscreen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> settings = {};

    final settingsJson = prefs.getString('app_settings');
    if (settingsJson != null) {
      try {
        settings = Map<String, dynamic>.from(jsonDecode(settingsJson));
      } catch (e) {
        // ignore
      }
    }

    settings['fullscreenMode'] = value;
    await prefs.setString('app_settings', jsonEncode(settings));

    // Применяем режим сразу
    if (value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    }

    setState(() {
      _fullscreen = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _AnimatedCard(
        child: ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Загрузка...'),
        ),
      );
    }

    return _AnimatedCard(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.fullscreen, color: Colors.deepPurple),
            title: const Text('Полноэкранный режим'),
            subtitle: const Text('Скрывать системные панели'),
            value: _fullscreen,
            onChanged: _saveFullscreen,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Скринсейвер активируется через 30 минут неактивности',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateSettingsCard extends StatefulWidget {
  final UpdateService updateService;
  final bool isCheckingUpdate;
  final VoidCallback onCheckUpdate;

  const _UpdateSettingsCard({
    required this.updateService,
    required this.isCheckingUpdate,
    required this.onCheckUpdate,
  });

  @override
  State<_UpdateSettingsCard> createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends State<_UpdateSettingsCard> {
  late bool _autoCheck;
  late UpdateChannel _channel;

  @override
  void initState() {
    super.initState();
    _autoCheck = widget.updateService.autoCheckEnabled;
    _channel = widget.updateService.updateChannel;
  }

  String _formatLastCheck(DateTime? lastCheck) {
    if (lastCheck == null) return 'Никогда';

    final now = DateTime.now();
    final diff = now.difference(lastCheck);

    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
    if (diff.inHours < 24) return '${diff.inHours} ч. назад';
    if (diff.inDays == 1) return 'Вчера';

    return '${lastCheck.day.toString().padLeft(2, '0')}.'
        '${lastCheck.month.toString().padLeft(2, '0')}.'
        '${lastCheck.year}';
  }

  @override
  Widget build(BuildContext context) {
    return _AnimatedCard(
      child: Column(
        children: [
          ListTile(
            leading: widget.isCheckingUpdate
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update, color: Colors.teal),
            title: const Text('Проверить обновления'),
            subtitle: Text(
              'Последняя проверка: ${_formatLastCheck(widget.updateService.lastCheckTime)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.isCheckingUpdate ? null : widget.onCheckUpdate,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew, color: Colors.blue),
            title: const Text('Автопроверка'),
            subtitle: const Text('Проверять раз в день при запуске'),
            value: _autoCheck,
            onChanged: (value) async {
              await widget.updateService.setAutoCheckEnabled(value);
              setState(() => _autoCheck = value);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              _channel == UpdateChannel.prerelease
                  ? Icons.science
                  : Icons.verified,
              color: _channel == UpdateChannel.prerelease
                  ? Colors.orange
                  : Colors.green,
            ),
            title: const Text('Канал обновлений'),
            subtitle: Text(
              _channel == UpdateChannel.prerelease
                  ? 'Pre-release (бета-версии)'
                  : 'Stable (стабильные)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChannelDialog,
          ),
          if (widget.updateService.skippedVersion != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.skip_next, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Пропущена: ${widget.updateService.skippedVersion}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await widget.updateService.clearSkippedVersion();
                      setState(() {});
                    },
                    child:
                        const Text('Сбросить', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showChannelDialog() async {
    final selected = await showDialog<UpdateChannel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Канал обновлений'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<UpdateChannel>(
              value: UpdateChannel.stable,
              groupValue: _channel,
              title: const Text('Stable'),
              subtitle: const Text('Только стабильные релизы'),
              secondary: const Icon(Icons.verified, color: Colors.green),
              onChanged: (value) => Navigator.pop(context, value),
            ),
            RadioListTile<UpdateChannel>(
              value: UpdateChannel.prerelease,
              groupValue: _channel,
              title: const Text('Pre-release'),
              subtitle: const Text('Бета-версии и тестовые сборки'),
              secondary: const Icon(Icons.science, color: Colors.orange),
              onChanged: (value) => Navigator.pop(context, value),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pre-release версии могут содержать баги',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (selected != null && selected != _channel) {
      await widget.updateService.setUpdateChannel(selected);
      setState(() => _channel = selected);
    }
  }
}
