import 'package:flutter/material.dart';
import '../models/models.dart';

class SceneItemList extends StatelessWidget {
  final List<OBSSceneItem> items;
  final Function(OBSSceneItem) onToggle;

  const SceneItemList({
    super.key,
    required this.items,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('Нет источников'),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        return _AnimatedSourceItem(
          key: ValueKey('${item.sourceName}_${item.sceneItemId}'),
          item: item,
          index: index,
          onToggle: onToggle,
        );
      },
    );
  }
}

class _AnimatedSourceItem extends StatefulWidget {
  final OBSSceneItem item;
  final int index;
  final Function(OBSSceneItem) onToggle;

  const _AnimatedSourceItem({
    super.key,
    required this.item,
    required this.index,
    required this.onToggle,
  });

  @override
  State<_AnimatedSourceItem> createState() => _AnimatedSourceItemState();
}

class _AnimatedSourceItemState extends State<_AnimatedSourceItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 200 + (widget.index * 30).clamp(0, 150)),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.3, 0),
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                color: widget.item.isVisible
                    ? Colors.green.withValues(alpha:0.3)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: ListTile(
              leading: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: child,
                ),
                child: Icon(
                  widget.item.isVisible
                      ? Icons.visibility
                      : Icons.visibility_off,
                  key: ValueKey(widget.item.isVisible),
                  color: widget.item.isVisible ? Colors.green : Colors.grey,
                ),
              ),
              title: Text(widget.item.sourceName),
              subtitle: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 12,
                  color: widget.item.isVisible ? Colors.green : Colors.grey,
                ),
                child: Text(widget.item.isVisible ? 'Видим' : 'Скрыт'),
              ),
              trailing: Switch(
                value: widget.item.isVisible,
                onChanged: (_) => widget.onToggle(widget.item),
              ),
              onTap: () => widget.onToggle(widget.item),
            ),
          ),
        ),
      ),
    );
  }
}
