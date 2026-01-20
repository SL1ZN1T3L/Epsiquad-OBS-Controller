import 'package:flutter/material.dart';
import '../models/models.dart';

class AudioSourceList extends StatelessWidget {
  final List<OBSAudioSource> sources;
  final Function(OBSAudioSource) onMuteToggle;
  final Function(OBSAudioSource, double)? onVolumeChange;

  const AudioSourceList({
    super.key,
    required this.sources,
    required this.onMuteToggle,
    this.onVolumeChange,
  });

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const Center(
        child: Text('Нет аудио источников'),
      );
    }

    return ListView.builder(
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return _AnimatedAudioItem(
          key: ValueKey(source.name),
          source: source,
          index: index,
          onMuteToggle: onMuteToggle,
          onVolumeChange: onVolumeChange,
        );
      },
    );
  }
}

class _AnimatedAudioItem extends StatefulWidget {
  final OBSAudioSource source;
  final int index;
  final Function(OBSAudioSource) onMuteToggle;
  final Function(OBSAudioSource, double)? onVolumeChange;

  const _AnimatedAudioItem({
    super.key,
    required this.source,
    required this.index,
    required this.onMuteToggle,
    this.onVolumeChange,
  });

  @override
  State<_AnimatedAudioItem> createState() => _AnimatedAudioItemState();
}

class _AnimatedAudioItemState extends State<_AnimatedAudioItem> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  double _localVolume = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _localVolume = widget.source.volume;
    _controller = AnimationController(
      duration: Duration(milliseconds: 200 + (widget.index * 30).clamp(0, 150)),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(_AnimatedAudioItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Обновляем локальную громкость только если не перетаскиваем слайдер
    if (!_isDragging && widget.source.volume != oldWidget.source.volume) {
      _localVolume = widget.source.volume;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: source.isMuted 
                    ? Colors.red.withOpacity(0.3) 
                    : Colors.green.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: _buildVolumeIcon(source),
                  title: Text(source.name),
                  subtitle: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 12,
                      color: source.isMuted ? Colors.red : Colors.grey,
                    ),
                    child: Text(
                      source.isMuted 
                          ? 'Выключен' 
                          : 'Громкость: ${(_localVolume * 100).round()}%',
                    ),
                  ),
                  trailing: IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                      child: Icon(
                        source.isMuted ? Icons.volume_off : Icons.volume_up,
                        key: ValueKey(source.isMuted),
                        color: source.isMuted ? Colors.red : Colors.green,
                      ),
                    ),
                    onPressed: () => widget.onMuteToggle(source),
                  ),
                ),
                // Слайдер громкости
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: widget.onVolumeChange != null && !source.isMuted
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.volume_down, 
                          size: 20,
                          color: Colors.grey.shade600,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16,
                              ),
                            ),
                            child: Slider(
                              value: _localVolume.clamp(0.0, 1.0),
                              min: 0.0,
                              max: 1.0,
                              divisions: 100,
                              onChangeStart: (_) => _isDragging = true,
                              onChanged: (value) {
                                setState(() => _localVolume = value);
                              },
                              onChangeEnd: (value) {
                                _isDragging = false;
                                widget.onVolumeChange?.call(source, value);
                              },
                            ),
                          ),
                        ),
                        Icon(
                          Icons.volume_up, 
                          size: 20,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6, 
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(_localVolume * 100).round()}%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeIcon(OBSAudioSource source) {
    final volume = _localVolume;
    IconData icon;
    Color color;
    
    if (source.isMuted) {
      icon = Icons.volume_off;
      color = Colors.red;
    } else if (volume < 0.01) {
      icon = Icons.volume_mute;
      color = Colors.grey;
    } else if (volume < 0.5) {
      icon = Icons.volume_down;
      color = Colors.orange;
    } else {
      icon = Icons.volume_up;
      color = Colors.green;
    }
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Icon(
        icon,
        key: ValueKey('$icon${source.isMuted}'),
        color: color,
      ),
    );
  }
}
