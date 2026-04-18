import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/log_service.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  LogLevel? _filterLevel;
  String? _filterTag;
  String _searchQuery = '';
  bool _autoScroll = true;
  bool _showSearch = false;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    LogService.instance.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    LogService.instance.removeListener(_onLogsChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onLogsChanged() {
    if (mounted) {
      setState(() {});
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  List<LogEntry> get _filteredEntries => LogService.instance.filter(
        level: _filterLevel,
        tag: _filterTag,
        query: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;
    final allTags = LogService.instance.allTags.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text('Логи (${entries.length})'),
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: _autoScroll ? Colors.green : null,
            ),
            tooltip: _autoScroll ? 'Автопрокрутка вкл' : 'Автопрокрутка выкл',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
              if (_autoScroll) _scrollToBottom();
            },
          ),
          IconButton(
            icon: Icon(
              Icons.search,
              color: _showSearch ? Colors.blue : null,
            ),
            tooltip: 'Поиск',
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchQuery = '';
                _searchController.clear();
              }
            }),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 20),
                    SizedBox(width: 12),
                    Text('Копировать'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'save',
                child: Row(
                  children: [
                    Icon(Icons.save, size: 20),
                    SizedBox(width: 12),
                    Text('Сохранить в файл'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('Поделиться'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Очистить', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Поиск
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск по логам...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),

          // Фильтры
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _FilterChip(
                  label: 'Все',
                  isSelected: _filterLevel == null && _filterTag == null,
                  onTap: () => setState(() {
                    _filterLevel = null;
                    _filterTag = null;
                  }),
                ),
                _FilterChip(
                  label: 'Error',
                  color: Colors.red,
                  isSelected: _filterLevel == LogLevel.error,
                  onTap: () => setState(() {
                    _filterLevel = _filterLevel == LogLevel.error ? null : LogLevel.error;
                  }),
                ),
                _FilterChip(
                  label: 'Warning',
                  color: Colors.orange,
                  isSelected: _filterLevel == LogLevel.warning,
                  onTap: () => setState(() {
                    _filterLevel = _filterLevel == LogLevel.warning ? null : LogLevel.warning;
                  }),
                ),
                _FilterChip(
                  label: 'Info',
                  color: Colors.blue,
                  isSelected: _filterLevel == LogLevel.info,
                  onTap: () => setState(() {
                    _filterLevel = _filterLevel == LogLevel.info ? null : LogLevel.info;
                  }),
                ),
                _FilterChip(
                  label: 'Debug',
                  color: Colors.grey,
                  isSelected: _filterLevel == LogLevel.debug,
                  onTap: () => setState(() {
                    _filterLevel = _filterLevel == LogLevel.debug ? null : LogLevel.debug;
                  }),
                ),
                if (allTags.isNotEmpty) ...[
                  const VerticalDivider(width: 16),
                  ...allTags.map((tag) => _FilterChip(
                        label: tag,
                        isSelected: _filterTag == tag,
                        onTap: () => setState(() {
                          _filterTag = _filterTag == tag ? null : tag;
                        }),
                      )),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Список логов
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.article_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Нет записей', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: entries.length,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemBuilder: (context, index) {
                      return _LogEntryTile(
                        entry: entries[index],
                        onTap: () => _showLogDetail(entries[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'copy':
        await _copyLogs();
        break;
      case 'save':
        await _saveLogs();
        break;
      case 'share':
        await _shareLogs();
        break;
      case 'clear':
        await _clearLogs();
        break;
    }
  }

  Future<void> _copyLogs() async {
    final text = LogService.instance.exportAsText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Скопировано ${LogService.instance.count} записей'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveLogs() async {
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/obs_controller_logs_$timestamp.txt');
      await file.writeAsString(LogService.instance.exportAsText());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сохранено: ${file.path.split('/').last}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Путь',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: file.path));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Путь скопирован'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _shareLogs() async {
    try {
      final text = LogService.instance.exportAsText();
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'OBS Controller Logs'),
      );
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

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить логи?'),
        content: Text('Будет удалено ${LogService.instance.count} записей'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      LogService.instance.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Логи очищены'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showLogDetail(LogEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            _levelDot(entry.level),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.tag,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.dateTimeString,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SelectableText(
                entry.message,
                style: const TextStyle(fontSize: 14),
              ),
              if (entry.details != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                SelectableText(
                  entry.details!,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade300,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              final text = entry.toFormattedString();
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Запись скопирована'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Копировать'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  static Widget _levelDot(LogLevel level) {
    Color color;
    switch (level) {
      case LogLevel.debug:
        color = Colors.grey;
        break;
      case LogLevel.info:
        color = Colors.blue;
        break;
      case LogLevel.warning:
        color = Colors.orange;
        break;
      case LogLevel.error:
        color = Colors.red;
        break;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final VoidCallback? onTap;

  const _LogEntryTile({required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    Color levelColor;
    switch (entry.level) {
      case LogLevel.debug:
        levelColor = Colors.grey;
        break;
      case LogLevel.info:
        levelColor = Colors.blue;
        break;
      case LogLevel.warning:
        levelColor = Colors.orange;
        break;
      case LogLevel.error:
        levelColor = Colors.red;
        break;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Время
            SizedBox(
              width: 72,
              child: Text(
                entry.timeString,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey.shade500,
                ),
              ),
            ),
            // Уровень
            Container(
              width: 18,
              alignment: Alignment.center,
              child: Text(
                entry.levelIcon,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: levelColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Тег
            SizedBox(
              width: 50,
              child: Text(
                entry.tag,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // Сообщение
            Expanded(
              child: Text(
                entry.message,
                style: TextStyle(
                  fontSize: 12,
                  color: entry.level == LogLevel.error
                      ? Colors.red.shade300
                      : entry.level == LogLevel.warning
                          ? Colors.orange.shade300
                          : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Chip(
          label: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? Colors.white : (color ?? Colors.grey.shade300),
            ),
          ),
          backgroundColor: isSelected
              ? (color ?? Colors.blue).withValues(alpha: 0.3)
              : Colors.transparent,
          side: BorderSide(
            color: isSelected ? (color ?? Colors.blue) : Colors.grey.shade700,
          ),
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
