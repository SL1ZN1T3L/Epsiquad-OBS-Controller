import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/obs_provider.dart';
import '../services/log_service.dart';
import '../models/models.dart';

class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  String? _selectedSource;
  List<OBSSourceFilter> _filters = [];
  bool _isLoading = false;
  List<String> _allSources = [];
  bool _sourcesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    final provider = Provider.of<OBSProvider>(context, listen: false);
    if (!provider.isConnected) return;

    setState(() => _sourcesLoading = true);

    final sources = <String>{};

    // Сцены — тоже источники с фильтрами
    for (final scene in provider.scenes) {
      sources.add(scene.name);
    }

    // Аудио источники
    for (final audio in provider.audioSources) {
      sources.add(audio.name);
    }

    // Источники из всех сцен
    for (final entry in provider.allSceneItems.entries) {
      for (final item in entry.value) {
        sources.add(item.sourceName);
      }
    }

    if (mounted) {
      setState(() {
        _allSources = sources.toList()..sort();
        _sourcesLoading = false;
      });
    }
  }

  Future<void> _loadFilters(String sourceName) async {
    final provider = Provider.of<OBSProvider>(context, listen: false);
    if (!provider.isConnected) return;

    setState(() {
      _selectedSource = sourceName;
      _isLoading = true;
    });

    try {
      final filters = await provider.obsService.getSourceFilterList(sourceName);
      if (mounted) {
        setState(() {
          _filters = filters;
          _isLoading = false;
        });
      }
    } catch (e) {
      log.w('Filters', 'Error loading filters for $sourceName', e.toString());
      if (mounted) {
        setState(() {
          _filters = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFilter(
      OBSProvider provider, String sourceName, String filterName, bool enabled) async {
    // Optimistic update
    setState(() {
      final idx = _filters.indexWhere((f) => f.name == filterName);
      if (idx != -1) {
        _filters[idx] = _filters[idx].copyWith(enabled: enabled);
      }
    });

    try {
      await provider.obsService.setSourceFilterEnabled(
          sourceName, filterName, enabled);
      HapticFeedback.lightImpact();
    } catch (e) {
      log.e('Filters', 'Error toggling filter', e.toString());
      // Rollback
      setState(() {
        final idx = _filters.indexWhere((f) => f.name == filterName);
        if (idx != -1) {
          _filters[idx] = _filters[idx].copyWith(enabled: !enabled);
        }
      });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Фильтры'),
        actions: [
          if (_selectedSource != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
              onPressed: () => _loadFilters(_selectedSource!),
            ),
        ],
      ),
      body: Consumer<OBSProvider>(
        builder: (context, provider, _) {
          if (!provider.isConnected) {
            return const Center(child: Text('Не подключено к OBS'));
          }

          return Column(
            children: [
              // Выбор источника
              Padding(
                padding: const EdgeInsets.all(12),
                child: _sourcesLoading
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        key: ValueKey(_selectedSource),
                        initialValue: _allSources.contains(_selectedSource)
                            ? _selectedSource
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Источник',
                          prefixIcon: const Icon(Icons.layers, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                        items: _allSources.map((name) {
                          return DropdownMenuItem(
                            value: name,
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) _loadFilters(value);
                        },
                      ),
              ),

              const Divider(height: 1),

              // Список фильтров
              Expanded(
                child: _selectedSource == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_alt_outlined,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('Выберите источник',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey)),
                            SizedBox(height: 8),
                            Text(
                              'Для просмотра его фильтров',
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _filters.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.filter_alt_off,
                                        size: 48, color: Colors.grey),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Нет фильтров у "$_selectedSource"',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                itemCount: _filters.length,
                                itemBuilder: (context, index) {
                                  final filter = _filters[index];
                                  return _FilterTile(
                                    filter: filter,
                                    onToggle: (enabled) => _toggleFilter(
                                      provider,
                                      _selectedSource!,
                                      filter.name,
                                      enabled,
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  final OBSSourceFilter filter;
  final ValueChanged<bool> onToggle;

  const _FilterTile({
    required this.filter,
    required this.onToggle,
  });

  IconData _getFilterIcon(String kind) {
    if (kind.contains('color') || kind.contains('Color')) return Icons.palette;
    if (kind.contains('chroma') || kind.contains('Chroma')) return Icons.crop_free;
    if (kind.contains('noise') || kind.contains('Noise')) return Icons.graphic_eq;
    if (kind.contains('gain') || kind.contains('Gain')) return Icons.volume_up;
    if (kind.contains('compressor')) return Icons.compress;
    if (kind.contains('limiter')) return Icons.vertical_align_center;
    if (kind.contains('blur') || kind.contains('Blur')) return Icons.blur_on;
    if (kind.contains('sharpen') || kind.contains('Sharp')) return Icons.blur_off;
    if (kind.contains('scroll') || kind.contains('Scroll')) return Icons.swap_vert;
    if (kind.contains('crop') || kind.contains('Crop')) return Icons.crop;
    if (kind.contains('mask') || kind.contains('Mask')) return Icons.masks;
    if (kind.contains('lut') || kind.contains('LUT')) return Icons.gradient;
    if (kind.contains('delay')) return Icons.timer;
    return Icons.filter_alt;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        secondary: Icon(
          _getFilterIcon(filter.kind),
          color: filter.enabled ? Colors.green : Colors.grey,
        ),
        title: Text(
          filter.name,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: filter.enabled ? null : Colors.grey,
          ),
        ),
        subtitle: Text(
          filter.kind,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        value: filter.enabled,
        onChanged: onToggle,
      ),
    );
  }
}
