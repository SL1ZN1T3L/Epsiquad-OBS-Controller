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
    with TickerProviderStateMixin {
  late Timer _moveTimer;
  late AnimationController _pulseController;
  late AnimationController _gradientController;
  late Animation<double> _pulseAnimation;

  double _top = 100;
  double _left = 50;
  final _random = Random();

  // Плавающие частицы
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();

    // Пульсация для индикаторов записи/стрима
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Анимация градиента фона
    _gradientController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    // Инициализация частиц
    for (int i = 0; i < 15; i++) {
      _particles.add(_Particle.random(_random));
    }

    _moveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _moveText());
  }

  @override
  void dispose() {
    _moveTimer.cancel();
    _pulseController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  void _moveText() {
    if (!mounted) return;
    setState(() {
      _top = _random.nextDouble() * (MediaQuery.of(context).size.height - 200);
      _left = _random.nextDouble() * (MediaQuery.of(context).size.width - 280);

      // Обновляем частицы
      for (var particle in _particles) {
        particle.update(_random);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
        animation: _gradientController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _getAnimatedColor(0),
                  _getAnimatedColor(1),
                  _getAnimatedColor(2),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: child,
          );
        },
        child: Stack(
          children: [
            // Плавающие частицы
            ..._particles.map((particle) => _buildParticle(particle)),

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

  Color _getAnimatedColor(int index) {
    final baseColors = [
      [
        const Color(0xFF0D1117),
        const Color(0xFF161B22),
        const Color(0xFF1A1F25)
      ],
      [
        const Color(0xFF161B22),
        const Color(0xFF1A1F25),
        const Color(0xFF0D1117)
      ],
      [
        const Color(0xFF1A1F25),
        const Color(0xFF0D1117),
        const Color(0xFF161B22)
      ],
    ];

    final t = _gradientController.value;
    final fromIndex = (t * 3).floor() % 3;
    final toIndex = (fromIndex + 1) % 3;
    final localT = (t * 3) % 1;

    return Color.lerp(
      baseColors[fromIndex][index],
      baseColors[toIndex][index],
      localT,
    )!;
  }

  Widget _buildParticle(_Particle particle) {
    return AnimatedPositioned(
      duration: const Duration(seconds: 5),
      curve: Curves.easeInOut,
      top: particle.y * MediaQuery.of(context).size.height,
      left: particle.x * MediaQuery.of(context).size.width,
      child: AnimatedOpacity(
        duration: const Duration(seconds: 2),
        opacity: particle.opacity,
        child: Container(
          width: particle.size,
          height: particle.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                particle.color.withValues(alpha:0.3),
                particle.color.withValues(alpha:0.0),
              ],
            ),
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
        color: Colors.black.withValues(alpha:0.3),
        border: Border.all(
          color: Colors.white.withValues(alpha:0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.purple.withValues(alpha:0.3),
                      Colors.blue.withValues(alpha:0.3),
                    ],
                  ),
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
                color: Colors.white.withValues(alpha:0.3),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Нажмите для продолжения',
                style: TextStyle(
                  color: Colors.white.withValues(alpha:0.3),
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
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.15 * _pulseAnimation.value),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha:0.5 * _pulseAnimation.value),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha:0.3 * _pulseAnimation.value),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
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
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, _) {
        final now = DateTime.now();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: Colors.white.withValues(alpha:0.15),
                fontSize: 72,
                fontWeight: FontWeight.w100,
                letterSpacing: 4,
              ),
            ),
            Text(
              ':${now.second.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: Colors.white.withValues(alpha:0.08),
                fontSize: 24,
                fontWeight: FontWeight.w100,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDate() {
    final now = DateTime.now();
    final months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря'
    ];
    final weekdays = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          weekdays[now.weekday - 1],
          style: TextStyle(
            color: Colors.white.withValues(alpha:0.2),
            fontSize: 16,
            fontWeight: FontWeight.w300,
          ),
        ),
        Text(
          '${now.day} ${months[now.month - 1]}',
          style: TextStyle(
            color: Colors.white.withValues(alpha:0.15),
            fontSize: 24,
            fontWeight: FontWeight.w200,
          ),
        ),
      ],
    );
  }
}

class _Particle {
  double x;
  double y;
  double size;
  double opacity;
  Color color;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.color,
  });

  factory _Particle.random(Random random) {
    final colors = [
      Colors.purple,
      Colors.blue,
      Colors.cyan,
      Colors.teal,
      Colors.indigo,
    ];

    return _Particle(
      x: random.nextDouble(),
      y: random.nextDouble(),
      size: 50 + random.nextDouble() * 150,
      opacity: 0.1 + random.nextDouble() * 0.3,
      color: colors[random.nextInt(colors.length)],
    );
  }

  void update(Random random) {
    x = random.nextDouble();
    y = random.nextDouble();
    opacity = 0.1 + random.nextDouble() * 0.3;
  }
}
