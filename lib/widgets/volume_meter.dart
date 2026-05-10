import 'package:flutter/material.dart';

class VolumeMeter extends StatefulWidget {
  final List<double> levels;
  final bool isMuted;

  const VolumeMeter({
    super.key,
    required this.levels,
    this.isMuted = false,
  });

  @override
  State<VolumeMeter> createState() => _VolumeMeterState();
}

class _VolumeMeterState extends State<VolumeMeter> {
  int _channelCount = 0;

  @override
  void didUpdateWidget(VolumeMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Запоминаем макс. число каналов, чтобы при исчезновении данных
    // метры плавно затухали, а не пропадали
    if (widget.levels.length > _channelCount) {
      _channelCount = widget.levels.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Если у нас ни одного канала и пустые данные — всё равно рисуем одну
    // пустую полоску. VolumeMeter инстанцируется только для аудио-источников
    // (виджет родителя оборачивает его в `if (volumeStream != null)`),
    // поэтому полоска уместна даже без данных от OBS — это нормально для
    // источников, неактивных в текущей сцене.
    final count = _channelCount > 0 ? _channelCount : 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _MeterBar(
            level: i < widget.levels.length ? widget.levels[i] : 0.0,
            isMuted: widget.isMuted,
          ),
        ],
      ],
    );
  }
}

class _MeterBar extends StatefulWidget {
  final double level;
  final bool isMuted;

  const _MeterBar({required this.level, required this.isMuted});

  @override
  State<_MeterBar> createState() => _MeterBarState();
}

class _MeterBarState extends State<_MeterBar>
    with SingleTickerProviderStateMixin {
  double _displayLevel = 0.0;
  double _peakLevel = 0.0;
  int _peakHoldFrames = 0;

  late AnimationController _controller;

  static const double _fallSpeed = 1.8;
  static const double _peakFallSpeed = 0.6;
  static const int _peakHoldDuration = 30;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tick() {
    final target = widget.level.clamp(0.0, 1.0);
    const dt = 1.0 / 60.0;

    if (target > _displayLevel) {
      _displayLevel = target;
    } else {
      _displayLevel = (_displayLevel - _fallSpeed * dt).clamp(0.0, 1.0);
    }

    if (target > _peakLevel) {
      _peakLevel = target;
      _peakHoldFrames = _peakHoldDuration;
    } else if (_peakHoldFrames > 0) {
      _peakHoldFrames--;
    } else {
      _peakLevel = (_peakLevel - _peakFallSpeed * dt).clamp(0.0, 1.0);
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(color: Colors.grey.shade900),

                if (_displayLevel > 0)
                  ClipRect(
                    clipper: _LevelClipper(_displayLevel),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: widget.isMuted
                            ? LinearGradient(
                                colors: [
                                  Colors.red.shade900,
                                  Colors.red.shade600,
                                ],
                              )
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF26A626),
                                  Color(0xFF26A626),
                                  Color(0xFFA6A626),
                                  Color(0xFFA62626),
                                ],
                                stops: [0.0, 0.6, 0.8, 1.0],
                              ),
                      ),
                    ),
                  ),

                if (_peakLevel > 0.01 && !widget.isMuted)
                  Positioned(
                    left: (width * _peakLevel - 1.5).clamp(0.0, width - 1.5),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1.5,
                      color: _peakLevel > 0.8
                          ? const Color(0xFFA62626)
                          : _peakLevel > 0.6
                              ? const Color(0xFFA6A626)
                              : const Color(0xFF26A626),
                    ),
                  ),

                Positioned(
                  left: width * 0.6,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 0.5, color: Colors.black26),
                ),
                Positioned(
                  left: width * 0.8,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 0.5, color: Colors.black26),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LevelClipper extends CustomClipper<Rect> {
  final double fraction;

  _LevelClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  }

  @override
  bool shouldReclip(_LevelClipper oldClipper) => oldClipper.fraction != fraction;
}
