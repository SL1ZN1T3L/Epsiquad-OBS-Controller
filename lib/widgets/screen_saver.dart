import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class ScreenSaverOverlay extends StatefulWidget {
  final VoidCallback onTap;
  final String? connectionName;
  final bool isRecording;
  final bool isStreaming;

  const ScreenSaverOverlay({
    super.key,
    required this.onTap,
    this.connectionName,
    this.isRecording = false,
    this.isStreaming = false,
  });

  @override
  State<ScreenSaverOverlay> createState() => _ScreenSaverOverlayState();
}

class _ScreenSaverOverlayState extends State<ScreenSaverOverlay>
    with SingleTickerProviderStateMixin {
  late Timer _moveTimer;
  late Timer _clockTimer;
  late AnimationController _pulseController;

  double _top = 100;
  double _left = 50;
  final _random = Random();
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();

    // Пульсация только если есть запись/стрим
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    if (widget.isRecording || widget.isStreaming) {
      _pulseController.repeat(reverse: true);
    }

    // Перемещение текста каждые 10 секунд (реже)
    _moveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _moveText());

    // Обновление часов каждую минуту (без секунд)
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _moveTimer.cancel();
    _clockTimer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _moveText() {
    if (!mounted) return;
    setState(() {
      _top = _random.nextDouble() * (MediaQuery.of(context).size.height - 200);
      _left = _random.nextDouble() * (MediaQuery.of(context).size.width - 280);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: const Color(0xFF0D1117),
          child: Stack(
            children: [
              // Основной контент
              AnimatedPositioned(
                duration: const Duration(seconds: 3),
                curve: Curves.easeInOutCubic,
                top: _top,
                left: _left,
                child: _buildContent(),
              ),

              // Время в углу
              Positioned(
                bottom: 30,
                right: 30,
                child: _buildClock(),
              ),

              // Дата слева внизу
              Positioned(
                bottom: 30,
                left: 30,
                child: _buildDate(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: Colors.white70, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.connectionName ?? 'OBS Controller',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Подключено',
                    style: TextStyle(
                      color: Colors.green.shade400,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (widget.isRecording || widget.isStreaming) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isRecording)
                  _buildStatusBadge(
                    icon: Icons.fiber_manual_record,
                    label: 'REC',
                    color: Colors.red,
                  ),
                if (widget.isRecording && widget.isStreaming)
                  const SizedBox(width: 12),
                if (widget.isStreaming)
                  _buildStatusBadge(
                    icon: Icons.stream,
                    label: 'LIVE',
                    color: Colors.red,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.touch_app_rounded,
                color: Colors.white.withValues(alpha: 0.3),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Нажмите для продолжения',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.5 + (_pulseController.value * 0.5);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: opacity),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color.withValues(alpha: opacity), size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: opacity),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClock() {
    return Text(
      '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.15),
        fontSize: 72,
        fontWeight: FontWeight.w100,
        letterSpacing: 4,
      ),
    );
  }

  Widget _buildDate() {
    final months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    final weekdays = [
      'Понедельник', 'Вторник', 'Среда', 'Четверг',
      'Пятница', 'Суббота', 'Воскресенье'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          weekdays[_currentTime.weekday - 1],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            fontSize: 16,
            fontWeight: FontWeight.w300,
          ),
        ),
        Text(
          '${_currentTime.day} ${months[_currentTime.month - 1]}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.15),
            fontSize: 24,
            fontWeight: FontWeight.w200,
          ),
        ),
      ],
    );
  }
}
