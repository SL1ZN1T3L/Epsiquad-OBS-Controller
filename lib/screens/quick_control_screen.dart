import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/models.dart';
import '../providers/obs_provider.dart';
import '../widgets/screen_saver.dart';
import 'profiles_screen.dart';

class QuickControlScreen extends StatefulWidget {
  const QuickControlScreen({super.key});

  @override
  State<QuickControlScreen> createState() => _QuickControlScreenState();
}

class _QuickControlScreenState extends State<QuickControlScreen>
    with WidgetsBindingObserver {
  QuickControlConfig _config = QuickControlConfig.empty();
  bool _isEditMode = false;
  bool _isLoading = true;
  bool _showScreenSaver = false;
  Timer? _inactivityTimer;
  static const _inactivityDuration = Duration(minutes: 30);
  bool _isInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfig();
    WakelockPlus.enable();
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isInForeground = state == AppLifecycleState.resumed;
    });

    if (_isInForeground) {
      WakelockPlus.enable();
      _resetInactivityTimer();
    } else {
      WakelockPlus.disable();
      _inactivityTimer?.cancel();
      _showScreenSaver = false;
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_showScreenSaver) {
      setState(() => _showScreenSaver = false);
    }

    _inactivityTimer = Timer(_inactivityDuration, () {
      if (_isInForeground && mounted) {
        setState(() => _showScreenSaver = true);
      }
    });
  }

  void _onUserInteraction() {
    _resetInactivityTimer();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('quickControlConfig');
    setState(() {
      if (json != null) {
        try {
          _config = QuickControlConfig.fromJsonString(json);
        } catch (e) {
          _config = QuickControlConfig.empty();
        }
      }
      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quickControlConfig', _config.toJsonString());
  }

  void _addButton(QuickButtonConfig button) {
    setState(() {
      _config = QuickControlConfig(
        buttons: [..._config.buttons, button],
        columns: _config.columns,
      );
    });
    _saveConfig();
  }

  void _addButtons(List<QuickButtonConfig> buttons) {
    setState(() {
      _config = QuickControlConfig(
        buttons: [..._config.buttons, ...buttons],
        columns: _config.columns,
      );
    });
    _saveConfig();
  }

  void _removeButton(String id) {
    setState(() {
      _config = QuickControlConfig(
        buttons: _config.buttons.where((b) => b.id != id).toList(),
        columns: _config.columns,
      );
    });
    _saveConfig();
  }

  void _updateButton(QuickButtonConfig button) {
    setState(() {
      final index = _config.buttons.indexWhere((b) => b.id == button.id);
      if (index != -1) {
        final buttons = List<QuickButtonConfig>.from(_config.buttons);
        buttons[index] = button;
        _config = QuickControlConfig(
          buttons: buttons,
          columns: _config.columns,
        );
      }
    });
    _saveConfig();
  }

  void _setColumns(int columns) {
    setState(() {
      _config = QuickControlConfig(
        buttons: _config.buttons,
        columns: columns,
      );
    });
    _saveConfig();
  }

  void _reorderButtons(int oldIndex, int newIndex) {
    setState(() {
      final buttons = List<QuickButtonConfig>.from(_config.buttons);
      if (newIndex > oldIndex) newIndex--;
      final item = buttons.removeAt(oldIndex);
      buttons.insert(newIndex, item);
      _config = QuickControlConfig(
        buttons: buttons,
        columns: _config.columns,
      );
    });
    _saveConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _onUserInteraction(),
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title:
                  Text(_isEditMode ? 'Редактирование' : 'Быстрое управление'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.account_tree),
                  tooltip: 'Профили',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilesScreen()),
                  ),
                ),
                PopupMenuButton<int>(
                  icon: const Icon(Icons.grid_view),
                  tooltip: 'Колонки',
                  onSelected: _setColumns,
                  itemBuilder: (context) => [
                    for (int i = 2; i <= 5; i++)
                      PopupMenuItem(
                        value: i,
                        child: Row(
                          children: [
                            if (i == _config.columns)
                              const Icon(Icons.check, size: 18),
                            SizedBox(width: i == _config.columns ? 8 : 26),
                            Text('$i колонки'),
                          ],
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: Icon(_isEditMode ? Icons.done : Icons.edit),
                  tooltip: _isEditMode ? 'Готово' : 'Редактировать',
                  onPressed: () => setState(() => _isEditMode = !_isEditMode),
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

                      if (_config.buttons.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.dashboard_customize,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('Нет кнопок',
                                  style: TextStyle(
                                      fontSize: 18, color: Colors.grey)),
                              SizedBox(height: 8),
                              Text('Нажмите + чтобы добавить',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      return _isEditMode
                          ? _buildEditableGrid(provider)
                          : _buildGrid(provider);
                    },
                  ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _showAddDialog(context),
              child: const Icon(Icons.add),
            ),
          ),
          // Screen Saver overlay
          if (_showScreenSaver)
            Consumer<OBSProvider>(
              builder: (context, provider, _) => ScreenSaverOverlay(
                onTap: _resetInactivityTimer,
                connectionName: provider.currentConnection?.name,
                isRecording: provider.status.recordStatus.isActive,
                isStreaming: provider.status.streamStatus.isActive,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(OBSProvider provider) {
    // Группируем кнопки по разделителям
    final List<List<QuickButtonConfig>> groups = [];
    List<QuickButtonConfig> currentGroup = [];
    String? currentGroupName;
    final List<String?> groupNames = [];

    for (final button in _config.buttons) {
      if (button.type == QuickButtonType.separator) {
        if (currentGroup.isNotEmpty || groups.isEmpty) {
          groups.add(currentGroup);
          groupNames.add(currentGroupName);
        }
        currentGroup = [];
        currentGroupName = button.groupName;
      } else {
        currentGroup.add(button);
      }
    }
    // Добавляем последнюю группу
    if (currentGroup.isNotEmpty || groups.isNotEmpty) {
      groups.add(currentGroup);
      groupNames.add(currentGroupName);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        final groupName = groupNames[groupIndex];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Разделитель (кроме первой группы без имени)
            if (groupIndex > 0 || groupName != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.grey.shade600,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (groupName != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          groupName,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.grey.shade600,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Сетка кнопок
            if (group.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _config.columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.0,
                ),
                itemCount: group.length,
                itemBuilder: (context, index) {
                  return _buildButton(group[index], provider);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildEditableGrid(OBSProvider provider) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _config.buttons.length,
      onReorder: _reorderButtons,
      itemBuilder: (context, index) {
        final button = _config.buttons[index];
        return Card(
          key: ValueKey(button.id),
          child: ListTile(
            leading: button.type == QuickButtonType.separator
                ? const Icon(Icons.horizontal_rule, color: Colors.grey)
                : Icon(button.icon, color: button.color),
            title: Text(button.type == QuickButtonType.separator
                ? '── ${button.groupName ?? "Разделитель"} ──'
                : button.displayName),
            subtitle: button.groupName != null &&
                    button.type != QuickButtonType.separator
                ? Text('Группа: ${button.groupName}')
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (button.type != QuickButtonType.separator)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Настроить',
                    onPressed: () => _showCustomizeDialog(button),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Удалить',
                  onPressed: () => _removeButton(button.id),
                ),
                const Icon(Icons.drag_handle),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildButton(QuickButtonConfig config, OBSProvider provider) {
    // Разделитель - горизонтальная черта
    if (config.type == QuickButtonType.separator) {
      return Container(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (config.groupName != null) ...[
              Text(
                config.groupName!,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.grey.shade600,
                    Colors.grey.shade600,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.2, 0.8, 1.0],
                ),
              ),
            ),
          ],
        ),
      );
    }

    bool isActive = false;
    bool isPaused = false;
    String? sublabel;
    Color activeColor = config.color ?? Colors.blue;
    VoidCallback? onTap;
    VoidCallback? onLongPress;

    switch (config.type) {
      case QuickButtonType.record:
        isActive = provider.status.recordStatus.isActive;
        isPaused = provider.status.recordStatus.isPaused;
        sublabel =
            isActive ? provider.status.recordStatus.durationString : null;
        activeColor = config.color ?? Colors.red;
        onTap = provider.toggleRecord;
        onLongPress = provider.toggleRecordPause;
        break;

      case QuickButtonType.stream:
        isActive = provider.status.streamStatus.isActive;
        sublabel =
            isActive ? provider.status.streamStatus.durationString : null;
        activeColor = config.color ?? Colors.red;
        onTap = provider.toggleStream;
        break;

      case QuickButtonType.scene:
        if (config.targetName != null) {
          final scene = provider.scenes.cast<OBSScene?>().firstWhere(
                (s) => s?.name == config.targetName,
                orElse: () => null,
              );
          isActive = scene?.isCurrentProgram ?? false;
          onTap = () => provider.switchScene(config.targetName!);
        }
        break;

      case QuickButtonType.audioMute:
        if (config.targetName != null) {
          final source =
              provider.audioSources.cast<OBSAudioSource?>().firstWhere(
                    (s) => s?.name == config.targetName,
                    orElse: () => null,
                  );
          isActive = !(source?.isMuted ?? true);
          activeColor = config.color ?? Colors.orange;
          onTap = () => provider.toggleAudioMute(config.targetName!);
          onLongPress = () => _showVolumeDialog(context, provider, config.targetName!, source);
        }
        break;

      case QuickButtonType.sceneItem:
        if (config.sceneName != null && config.targetId != null) {
          // Используем кэш всех сцен для получения актуального состояния
          isActive = provider.getSceneItemEnabled(
                  config.sceneName!, config.targetId!) ??
              false;
          activeColor = config.color ?? Colors.green;
          onTap = () => provider.toggleSceneItem(
                config.sceneName!,
                config.targetId!,
                !isActive,
              );
        }
        break;

      case QuickButtonType.virtualCam:
        isActive = provider.status.virtualCamActive;
        activeColor = config.color ?? Colors.purple;
        onTap = provider.toggleVirtualCam;
        break;

      case QuickButtonType.replayBuffer:
        isActive = provider.status.replayBufferActive;
        activeColor = config.color ?? Colors.teal;
        onTap = provider.toggleReplayBuffer;
        onLongPress = provider.saveReplayBuffer;
        break;

      case QuickButtonType.screenshot:
        activeColor = config.color ?? Colors.blue;
        onTap = () async {
          HapticFeedback.mediumImpact();
          final path =
              await provider.saveScreenshot(sourceName: config.targetName);
          if (mounted && path != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Скриншот сохранён: $path')),
            );
          }
        };
        break;

      case QuickButtonType.studioMode:
        isActive = provider.status.studioModeEnabled;
        activeColor = config.color ?? Colors.indigo;
        onTap = provider.toggleStudioMode;
        break;

      case QuickButtonType.hotkey:
        if (config.targetName != null) {
          activeColor = config.color ?? Colors.amber;
          onTap = () {
            HapticFeedback.lightImpact();
            provider.triggerHotkey(config.targetName!);
          };
        }
        break;

      case QuickButtonType.separator:
        break;
    }

    return _QuickButton(
      label: config.displayName,
      sublabel: sublabel,
      groupName: config.groupName,
      icon: config.icon,
      isActive: isActive,
      isPaused: isPaused,
      activeColor: activeColor,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  void _showAddDialog(BuildContext context) {
    final provider = Provider.of<OBSProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => _AddButtonDialog(
        provider: provider,
        onAddSingle: (button) {
          _addButton(button);
          Navigator.pop(context);
        },
        onAddMultiple: (buttons) {
          _addButtons(buttons);
          Navigator.pop(context);
        },
        currentButtonCount: _config.buttons.length,
      ),
    );
  }

  void _showCustomizeDialog(QuickButtonConfig button) {
    final labelController =
        TextEditingController(text: button.customLabel ?? '');
    final iconController = TextEditingController(text: button.customIcon ?? '');
    final colorController =
        TextEditingController(text: button.customColor ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настроить кнопку'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: InputDecoration(
                  labelText: 'Название',
                  hintText: button.displayName,
                  prefixIcon: const Icon(Icons.label),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: iconController,
                decoration: const InputDecoration(
                  labelText: 'Иконка',
                  hintText: 'videocam, camera, replay...',
                  prefixIcon: Icon(Icons.insert_emoticon),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: colorController,
                decoration: const InputDecoration(
                  labelText: 'Цвет (HEX)',
                  hintText: '#FF5722',
                  prefixIcon: Icon(Icons.palette),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Доступные иконки: videocam, camera, replay, edit, keyboard, tv, stream, record, volume, layers, play, pause, stop, mic, visibility, settings, star, favorite',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _updateButton(button.copyWith(
                customLabel: null,
                customIcon: null,
                customColor: null,
              ));
              Navigator.pop(context);
            },
            child: const Text('Сбросить'),
          ),
          ElevatedButton(
            onPressed: () {
              _updateButton(button.copyWith(
                customLabel:
                    labelController.text.isEmpty ? null : labelController.text,
                customIcon:
                    iconController.text.isEmpty ? null : iconController.text,
                customColor:
                    colorController.text.isEmpty ? null : colorController.text,
              ));
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showVolumeDialog(BuildContext context, OBSProvider provider, String inputName, OBSAudioSource? source) {
    if (source == null) return;

    showDialog(
      context: context,
      builder: (context) => _VolumeControlDialog(
        inputName: inputName,
        initialVolume: source.volume,
        isMuted: source.isMuted,
        onVolumeChange: (value) => provider.setAudioVolume(inputName, value),
        onMuteToggle: () => provider.toggleAudioMute(inputName),
      ),
    );
  }
}

// ==================== Диалог управления громкостью ====================

class _VolumeControlDialog extends StatefulWidget {
  final String inputName;
  final double initialVolume;
  final bool isMuted;
  final Function(double) onVolumeChange;
  final VoidCallback onMuteToggle;

  const _VolumeControlDialog({
    required this.inputName,
    required this.initialVolume,
    required this.isMuted,
    required this.onVolumeChange,
    required this.onMuteToggle,
  });

  @override
  State<_VolumeControlDialog> createState() => _VolumeControlDialogState();
}

class _VolumeControlDialogState extends State<_VolumeControlDialog> {
  late double _volume;
  late bool _isMuted;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume;
    _isMuted = widget.isMuted;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.inputName,
        style: const TextStyle(fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 160,
        height: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Процент громкости
            Text(
              '${(_volume * 100).round()}%',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: _isMuted ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 20),
            // Вертикальный слайдер
            Expanded(
              child: RotatedBox(
                quarterTurns: -1,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 12,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                    activeTrackColor: _isMuted ? Colors.red : Colors.green,
                    inactiveTrackColor: Colors.grey.shade700,
                    thumbColor: _isMuted ? Colors.red : Colors.green,
                  ),
                  child: Slider(
                    value: _volume.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    onChanged: (value) {
                      setState(() => _volume = value);
                    },
                    onChangeEnd: (value) {
                      widget.onVolumeChange(value);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Кнопка mute
            IconButton.filled(
              onPressed: () {
                setState(() => _isMuted = !_isMuted);
                widget.onMuteToggle();
              },
              icon: Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                size: 32,
              ),
              style: IconButton.styleFrom(
                backgroundColor: _isMuted ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

// ==================== Диалог добавления кнопок ====================

class _AddButtonDialog extends StatefulWidget {
  final OBSProvider provider;
  final Function(QuickButtonConfig) onAddSingle;
  final Function(List<QuickButtonConfig>) onAddMultiple;
  final int currentButtonCount;

  const _AddButtonDialog({
    required this.provider,
    required this.onAddSingle,
    required this.onAddMultiple,
    required this.currentButtonCount,
  });

  @override
  State<_AddButtonDialog> createState() => _AddButtonDialogState();
}

class _AddButtonDialogState extends State<_AddButtonDialog> {
  bool _multiSelectMode = false;
  final Set<_SelectableItem> _selectedItems = {};
  final Set<String> _expandedCategories = {};
  final ScrollController _scrollController = ScrollController();

  // Кеш источников сцен
  final Map<String, List<OBSSceneItem>> _sceneItemsCache = {};
  bool _isLoadingSceneItems = false;

  @override
  void initState() {
    super.initState();
    _loadAllSceneItems();
  }

  Future<void> _loadAllSceneItems() async {
    setState(() => _isLoadingSceneItems = true);
    for (final scene in widget.provider.scenes) {
      try {
        final items =
            await widget.provider.obsService.getSceneItemList(scene.name);
        _sceneItemsCache[scene.name] = items;
      } catch (e) {
        _sceneItemsCache[scene.name] = [];
      }
    }
    if (mounted) {
      setState(() => _isLoadingSceneItems = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(_multiSelectMode
                ? 'Выбрано: ${_selectedItems.length}'
                : 'Добавить кнопку'),
          ),
          IconButton(
            icon: Icon(_multiSelectMode
                ? Icons.check_box
                : Icons.check_box_outline_blank),
            tooltip:
                _multiSelectMode ? 'Одиночный режим' : 'Множественный выбор',
            onPressed: () {
              setState(() {
                _multiSelectMode = !_multiSelectMode;
                if (!_multiSelectMode) _selectedItems.clear();
              });
            },
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.6,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCategory('Основное', Icons.star, [
                _buildSelectableItem(
                  _SelectableItem(QuickButtonType.record, 'Запись', null),
                  Icons.fiber_manual_record,
                  Colors.red,
                  'Старт/стоп записи',
                ),
                _buildSelectableItem(
                  _SelectableItem(QuickButtonType.stream, 'Стрим', null),
                  Icons.stream,
                  Colors.red,
                  'Старт/стоп стрима',
                ),
                _buildSelectableItem(
                  _SelectableItem(
                      QuickButtonType.virtualCam, 'Виртуальная камера', null),
                  Icons.videocam,
                  Colors.purple,
                  'Вкл/выкл виртуальной камеры',
                ),
                _buildSelectableItem(
                  _SelectableItem(
                      QuickButtonType.studioMode, 'Studio Mode', null),
                  Icons.edit,
                  Colors.indigo,
                  'Вкл/выкл режима студии',
                ),
              ]),

              _buildCategory('Инструменты', Icons.build, [
                _buildSelectableItem(
                  _SelectableItem(QuickButtonType.screenshot, 'Скриншот', null),
                  Icons.camera_alt,
                  Colors.blue,
                  'Сохранить скриншот',
                ),
                _buildSelectableItem(
                  _SelectableItem(
                      QuickButtonType.replayBuffer, 'Replay Buffer', null),
                  Icons.replay,
                  Colors.teal,
                  'Сохранить повтор',
                ),
                ListTile(
                  leading: const Icon(Icons.keyboard, color: Colors.amber),
                  title: const Text('Горячая клавиша'),
                  subtitle: const Text('Триггер хоткея OBS'),
                  onTap: () => _showHotkeyDialog(),
                ),
              ]),

              _buildCategory('Сцены', Icons.tv, [
                ...widget.provider.scenes.map((scene) => _buildSelectableItem(
                      _SelectableItem(
                          QuickButtonType.scene, scene.name, scene.name),
                      Icons.tv,
                      scene.isCurrentProgram ? Colors.green : Colors.blue,
                      scene.isCurrentProgram ? 'Текущая сцена' : null,
                    )),
              ]),

              _buildCategory('Аудио', Icons.volume_up, [
                ...widget.provider.audioSources
                    .map((source) => _buildSelectableItem(
                          _SelectableItem(QuickButtonType.audioMute,
                              source.name, source.name),
                          source.isMuted ? Icons.volume_off : Icons.volume_up,
                          source.isMuted ? Colors.red : Colors.green,
                          source.isMuted ? 'Выключен' : 'Включён',
                        )),
              ]),

              // Источники каждой сцены
              ...widget.provider.scenes
                  .map((scene) => _buildSceneSourcesCategory(scene)),

              _buildCategory('Другое', Icons.more_horiz, [
                ListTile(
                  leading:
                      const Icon(Icons.horizontal_rule, color: Colors.grey),
                  title: const Text('Разделитель'),
                  subtitle: const Text('Визуальная группировка'),
                  onTap: () => _showSeparatorDialog(),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: _multiSelectMode && _selectedItems.isNotEmpty
          ? [
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedItems.clear();
                  });
                },
                child: const Text('Очистить'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final buttons = _selectedItems.map((item) {
                    return QuickButtonConfig(
                      id: const Uuid().v4(),
                      type: item.type,
                      targetName: item.targetName,
                      targetId: item.sceneItemId,
                      sceneName: item.sceneName,
                      order: widget.currentButtonCount +
                          _selectedItems.toList().indexOf(item),
                    );
                  }).toList();
                  widget.onAddMultiple(buttons);
                },
                icon: const Icon(Icons.add),
                label: Text('Добавить ${_selectedItems.length}'),
              ),
            ]
          : null,
    );
  }

  Widget _buildCategory(String title, IconData icon, List<Widget> children) {
    return ExpansionTile(
      key: PageStorageKey(title),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      initiallyExpanded: _expandedCategories.contains(title),
      onExpansionChanged: (expanded) {
        if (expanded) {
          _expandedCategories.add(title);
        } else {
          _expandedCategories.remove(title);
        }
      },
      children: children,
    );
  }

  Widget _buildSelectableItem(
    _SelectableItem item,
    IconData icon,
    Color color,
    String? subtitle,
  ) {
    final isSelected = _selectedItems.contains(item);

    return ListTile(
      leading: _multiSelectMode
          ? Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedItems.add(item);
                  } else {
                    _selectedItems.remove(item);
                  }
                });
              },
            )
          : Icon(icon, color: color),
      title: Text(item.name),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: _multiSelectMode ? Icon(icon, color: color) : null,
      onTap: () {
        if (_multiSelectMode) {
          setState(() {
            if (isSelected) {
              _selectedItems.remove(item);
            } else {
              _selectedItems.add(item);
            }
          });
        } else {
          widget.onAddSingle(QuickButtonConfig(
            id: const Uuid().v4(),
            type: item.type,
            targetName: item.targetName,
            order: widget.currentButtonCount,
          ));
        }
      },
    );
  }

  Widget _buildSceneSourcesCategory(OBSScene scene) {
    final items = _sceneItemsCache[scene.name] ?? [];
    final isLoading =
        _isLoadingSceneItems && !_sceneItemsCache.containsKey(scene.name);
    final icon = scene.isCurrentProgram ? Icons.play_circle : Icons.layers;
    final color = scene.isCurrentProgram ? Colors.green : null;
    final categoryKey = '${scene.name}_sources';

    return ExpansionTile(
      key: PageStorageKey(categoryKey),
      leading: Icon(icon, color: color),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${scene.name} (источники)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (items.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Text('${items.length}', style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
      initiallyExpanded: _expandedCategories.contains(categoryKey),
      onExpansionChanged: (expanded) {
        if (expanded) {
          _expandedCategories.add(categoryKey);
        } else {
          _expandedCategories.remove(categoryKey);
        }
      },
      children: isLoading
          ? [
              const ListTile(
                  title: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))))
            ]
          : items.isEmpty
              ? [
                  const ListTile(
                      title: Text('Нет источников',
                          style: TextStyle(color: Colors.grey)))
                ]
              : items.map((item) {
                  final selectableItem = _SelectableItem(
                    QuickButtonType.sceneItem,
                    item.sourceName,
                    item.sourceName,
                    sceneItemId: item.sceneItemId,
                    sceneName: scene.name,
                  );
                  final isSelected = _selectedItems.contains(selectableItem);

                  return ListTile(
                    leading: _multiSelectMode
                        ? Checkbox(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedItems.add(selectableItem);
                                } else {
                                  _selectedItems.remove(selectableItem);
                                }
                              });
                            },
                          )
                        : Icon(
                            item.isVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: item.isVisible ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                    title: Text(item.sourceName),
                    subtitle: Text(item.isVisible ? 'Видимый' : 'Скрытый',
                        style: const TextStyle(fontSize: 11)),
                    dense: true,
                    trailing: _multiSelectMode
                        ? Icon(
                            item.isVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: item.isVisible ? Colors.green : Colors.grey,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      if (_multiSelectMode) {
                        setState(() {
                          if (isSelected) {
                            _selectedItems.remove(selectableItem);
                          } else {
                            _selectedItems.add(selectableItem);
                          }
                        });
                      } else {
                        widget.onAddSingle(QuickButtonConfig(
                          id: const Uuid().v4(),
                          type: QuickButtonType.sceneItem,
                          targetName: item.sourceName,
                          targetId: item.sceneItemId,
                          sceneName: scene.name,
                          order: widget.currentButtonCount,
                        ));
                      }
                    },
                  );
                }).toList(),
    );
  }

  void _showSeparatorDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Например: Основное',
            labelText: 'Название (опционально)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              widget.onAddSingle(QuickButtonConfig(
                id: const Uuid().v4(),
                type: QuickButtonType.separator,
                groupName: controller.text.isEmpty ? null : controller.text,
                order: widget.currentButtonCount,
              ));
              Navigator.pop(ctx);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showHotkeyDialog() async {
    final hotkeys = await widget.provider.getHotkeys();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выберите горячую клавишу'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: hotkeys.isEmpty
              ? const Center(child: Text('Нет доступных горячих клавиш'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: hotkeys.length,
                  itemBuilder: (context, index) {
                    final hotkey = hotkeys[index];
                    return ListTile(
                      leading: const Icon(Icons.keyboard),
                      title: Text(hotkey),
                      onTap: () {
                        widget.onAddSingle(QuickButtonConfig(
                          id: const Uuid().v4(),
                          type: QuickButtonType.hotkey,
                          targetName: hotkey,
                          order: widget.currentButtonCount,
                        ));
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _SelectableItem {
  final QuickButtonType type;
  final String name;
  final String? targetName;
  final int? sceneItemId;
  final String? sceneName;

  _SelectableItem(this.type, this.name, this.targetName,
      {this.sceneItemId, this.sceneName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SelectableItem &&
          type == other.type &&
          name == other.name &&
          targetName == other.targetName &&
          sceneItemId == other.sceneItemId &&
          sceneName == other.sceneName;

  @override
  int get hashCode =>
      Object.hash(type, name, targetName, sceneItemId, sceneName);
}

// ==================== Виджет кнопки ====================

class _QuickButton extends StatelessWidget {
  final String label;
  final String? sublabel;
  final String? groupName;
  final IconData icon;
  final bool isActive;
  final bool isPaused;
  final Color activeColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _QuickButton({
    required this.label,
    this.sublabel,
    this.groupName,
    required this.icon,
    this.isActive = false,
    this.isPaused = false,
    this.activeColor = Colors.blue,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = isPaused ? Colors.orange : activeColor;
    final bgColor = isActive
        ? (isPaused
            ? Colors.orange.withValues(alpha:0.4)
            : activeColor.withValues(alpha:0.3))
        : Colors.grey.shade800;
    final borderColor = isActive ? displayColor : Colors.grey.shade600;

    return RepaintBoundary(
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (groupName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      groupName!,
                      style:
                          TextStyle(fontSize: 9, color: Colors.grey.shade500),
                    ),
                  ),
                Icon(icon,
                    size: 28, color: isActive ? displayColor : Colors.white70),
                if (isPaused)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.pause, size: 12, color: Colors.orange),
                  ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive ? displayColor : Colors.white,
                    ),
                  ),
                ),
                if (sublabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sublabel!,
                        style: TextStyle(
                            fontSize: 9, color: Colors.grey.shade400)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
