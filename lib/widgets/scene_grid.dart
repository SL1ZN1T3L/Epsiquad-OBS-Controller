import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';

class SceneGrid extends StatelessWidget {
  final List<OBSScene> scenes;
  final Function(OBSScene) onSceneTap;
  final int columns;

  const SceneGrid({
    super.key,
    required this.scenes,
    required this.onSceneTap,
    this.columns = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (scenes.isEmpty) {
      return const Center(
        child: Text('Нет сцен'),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.2,
      ),
      itemCount: scenes.length,
      itemBuilder: (context, index) {
        final scene = scenes[index];
        return _AnimatedSceneCard(
          key: ValueKey(scene.name),
          scene: scene,
          index: index,
          onTap: () {
            HapticFeedback.mediumImpact();
            onSceneTap(scene);
          },
        );
      },
    );
  }
}

class _AnimatedSceneCard extends StatefulWidget {
  final OBSScene scene;
  final int index;
  final VoidCallback onTap;

  const _AnimatedSceneCard({
    super.key,
    required this.scene,
    required this.index,
    required this.onTap,
  });

  @override
  State<_AnimatedSceneCard> createState() => _AnimatedSceneCardState();
}

class _AnimatedSceneCardState extends State<_AnimatedSceneCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 200 + (widget.index * 50).clamp(0, 200)),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.scene.isCurrentProgram;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isPressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isActive
                    ? Colors.red.shade700
                    : Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: isActive
                        ? Colors.red.withOpacity(0.4)
                        : Colors.black.withOpacity(0.2),
                    blurRadius: isActive ? 12 : 4,
                    spreadRadius: isActive ? 2 : 0,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isActive ? Icons.tv : Icons.tv_outlined,
                        key: ValueKey(isActive),
                        size: 32,
                        color: isActive ? Colors.white : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.scene.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? Colors.white : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
