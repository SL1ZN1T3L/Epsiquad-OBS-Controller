import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/obs_provider.dart';
import '../services/log_service.dart';
import '../models/models.dart';

class MediaControlsScreen extends StatefulWidget {
  const MediaControlsScreen({super.key});

  @override
  State<MediaControlsScreen> createState() => _MediaControlsScreenState();
}

class _MediaControlsScreenState extends State<MediaControlsScreen> {
  List<_MediaInput> _mediaInputs = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadMediaInputs();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMediaInputs() async {
    final provider = Provider.of<OBSProvider>(context, listen: false);
    if (!provider.isConnected) return;

    setState(() => _isLoading = true);

    try {
      // Запрашиваем медиа-источники по inputKind через API
      final mediaNames = await provider.obsService.getMediaInputNames();

      final inputs = <_MediaInput>[];
      for (final name in mediaNames) {
        try {
          final status = await provider.obsService.getMediaInputStatus(name);
          inputs.add(_MediaInput(name: name, status: status));
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _mediaInputs = inputs;
          _isLoading = false;
        });

        // Запускаем периодическое обновление статуса
        _startRefreshTimer(provider);
      }
    } catch (e) {
      log.e('Media', 'Error loading media inputs', e.toString());
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startRefreshTimer(OBSProvider provider) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !provider.isConnected) return;
      _refreshStatuses(provider);
    });
  }

  Future<void> _refreshStatuses(OBSProvider provider) async {
    if (_mediaInputs.isEmpty || _isRefreshing) return;
    _isRefreshing = true;

    try {
      final updated = <_MediaInput>[];
      for (final input in _mediaInputs) {
        try {
          final status = await provider.obsService.getMediaInputStatus(input.name);
          updated.add(_MediaInput(name: input.name, status: status));
        } catch (_) {
          updated.add(input);
        }
      }

      if (mounted) {
        setState(() => _mediaInputs = updated);
      }
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Медиа источники'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loadMediaInputs,
          ),
        ],
      ),
      body: Consumer<OBSProvider>(
        builder: (context, provider, _) {
          if (!provider.isConnected) {
            return const Center(child: Text('Не подключено к OBS'));
          }

          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_mediaInputs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.movie_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Нет медиа-источников',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text(
                    'Добавьте Media Source или VLC Source в OBS',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _mediaInputs.length,
            itemBuilder: (context, index) {
              final input = _mediaInputs[index];
              return _MediaCard(
                input: input,
                onPlay: () => _mediaAction(provider, input.name, 'play'),
                onPause: () => _mediaAction(provider, input.name, 'pause'),
                onStop: () => _mediaAction(provider, input.name, 'stop'),
                onRestart: () => _mediaAction(provider, input.name, 'restart'),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _mediaAction(
      OBSProvider provider, String inputName, String action) async {
    try {
      HapticFeedback.lightImpact();
      switch (action) {
        case 'play':
          await provider.obsService.playMediaInput(inputName);
          break;
        case 'pause':
          await provider.obsService.pauseMediaInput(inputName);
          break;
        case 'stop':
          await provider.obsService.stopMediaInput(inputName);
          break;
        case 'restart':
          await provider.obsService.restartMediaInput(inputName);
          break;
      }
    } catch (e) {
      log.e('Media', 'Error: $action $inputName', e.toString());
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
}

class _MediaInput {
  final String name;
  final OBSMediaStatus status;

  _MediaInput({required this.name, required this.status});
}

class _MediaCard extends StatelessWidget {
  final _MediaInput input;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  const _MediaCard({
    required this.input,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final status = input.status;
    final isPlaying = status.isPlaying;
    final isPaused = status.isPaused;

    Color stateColor;
    IconData stateIcon;
    if (isPlaying) {
      stateColor = Colors.green;
      stateIcon = Icons.play_arrow;
    } else if (isPaused) {
      stateColor = Colors.orange;
      stateIcon = Icons.pause;
    } else {
      stateColor = Colors.grey;
      stateIcon = Icons.stop;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                Icon(Icons.movie, color: stateColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        input.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Icon(stateIcon, size: 14, color: stateColor),
                          const SizedBox(width: 4),
                          Text(
                            status.stateLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: stateColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Прогресс
            if (status.duration != null && status.duration!.inMilliseconds > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: status.progress.clamp(0.0, 1.0),
                backgroundColor: Colors.grey.shade800,
                valueColor: AlwaysStoppedAnimation<Color>(stateColor),
              ),
              const SizedBox(height: 4),
              Text(
                status.progressString,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  fontFamily: 'monospace',
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Кнопки управления
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay),
                  tooltip: 'Перезапустить',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                  tooltip: 'Стоп',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: isPlaying ? onPause : onPlay,
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 32,
                  ),
                  tooltip: isPlaying ? 'Пауза' : 'Воспроизвести',
                  style: IconButton.styleFrom(
                    backgroundColor: isPlaying ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(56, 56),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
