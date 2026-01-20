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
  double _top = 100;
  double _left = 50;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _moveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _moveText());
  }

  @override
  void dispose() {
    _moveTimer.cancel();
    super.dispose();
  }

  void _moveText() {
    if (!mounted) return;
    setState(() {
      _top = _random.nextDouble() * (MediaQuery.of(context).size.height - 150);
      _left = _random.nextDouble() * (MediaQuery.of(context).size.width - 200);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOut,
              top: _top,
              left: _left,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tv, color: Colors.white54, size: 32),
                      const SizedBox(width: 12),
                      Text(
                        widget.connectionName ?? 'OBS Controller',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isRecording) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                              SizedBox(width: 4),
                              Text('REC', style: TextStyle(color: Colors.red, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (widget.isStreaming) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stream, color: Colors.red, size: 12),
                              SizedBox(width: 4),
                              Text('LIVE', style: TextStyle(color: Colors.red, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нажмите для продолжения',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Время в углу
            Positioned(
              bottom: 20,
              right: 20,
              child: StreamBuilder(
                stream: Stream.periodic(const Duration(seconds: 1)),
                builder: (context, _) {
                  final now = DateTime.now();
                  return Text(
                    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.2),
                      fontSize: 48,
                      fontWeight: FontWeight.w100,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
