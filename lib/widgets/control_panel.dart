import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';

class ControlPanel extends StatelessWidget {
  final OBSStatus status;
  final VoidCallback? onStreamToggle;
  final VoidCallback? onRecordToggle;
  final VoidCallback? onRecordPause;
  final VoidCallback? onVirtualCamToggle;
  final bool hapticFeedback;

  const ControlPanel({
    super.key,
    required this.status,
    this.onStreamToggle,
    this.onRecordToggle,
    this.onRecordPause,
    this.onVirtualCamToggle,
    this.hapticFeedback = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Стрим
            _buildStreamRow(context),
            const Divider(height: 24),
            // Запись
            _buildRecordRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamRow(BuildContext context) {
    final isActive = status.streamStatus.isActive;

    return Row(
      children: [
        // Статус
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.red : Colors.grey,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.red.withValues(alpha:0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 12),

        // Текст
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isActive ? 'СТРИМ АКТИВЕН' : 'Стрим остановлен',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.red : null,
                ),
              ),
              if (isActive)
                Text(
                  status.streamStatus.durationString,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),

        // Кнопка
        _ControlButton(
          icon: isActive ? Icons.stop : Icons.play_arrow,
          label: isActive ? 'Стоп' : 'Старт',
          color: isActive ? Colors.red : Colors.green,
          onPressed: onStreamToggle,
          hapticFeedback: hapticFeedback,
        ),
      ],
    );
  }

  Widget _buildRecordRow(BuildContext context) {
    final isActive = status.recordStatus.isActive;
    final isPaused = status.recordStatus.isPaused;

    return Row(
      children: [
        // Статус
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? (isPaused ? Colors.orange : Colors.red)
                : Colors.grey,
            boxShadow: isActive && !isPaused
                ? [
                    BoxShadow(
                      color: Colors.red.withValues(alpha:0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 12),

        // Текст
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isActive
                    ? (isPaused ? 'ЗАПИСЬ НА ПАУЗЕ' : 'ЗАПИСЬ АКТИВНА')
                    : 'Запись остановлена',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      isActive ? (isPaused ? Colors.orange : Colors.red) : null,
                ),
              ),
              if (isActive)
                Text(
                  status.recordStatus.durationString,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),

        // Кнопка паузы (только когда запись активна)
        if (isActive) ...[
          _ControlButton(
            icon: isPaused ? Icons.play_arrow : Icons.pause,
            label: isPaused ? 'Продолжить' : 'Пауза',
            color: Colors.orange,
            onPressed: onRecordPause,
            hapticFeedback: hapticFeedback,
          ),
          const SizedBox(width: 8),
        ],

        // Кнопка старт/стоп
        _ControlButton(
          icon: isActive ? Icons.stop : Icons.fiber_manual_record,
          label: isActive ? 'Стоп' : 'Запись',
          color: isActive ? Colors.red : Colors.green,
          onPressed: onRecordToggle,
          hapticFeedback: hapticFeedback,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool hapticFeedback;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.hapticFeedback = true,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed == null
          ? null
          : () {
              if (hapticFeedback) {
                HapticFeedback.mediumImpact();
              }
              onPressed!();
            },
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

// Компактная версия панели управления
class CompactControlPanel extends StatelessWidget {
  final OBSStatus status;
  final VoidCallback? onStreamToggle;
  final VoidCallback? onRecordToggle;
  final VoidCallback? onRecordPause;

  const CompactControlPanel({
    super.key,
    required this.status,
    this.onStreamToggle,
    this.onRecordToggle,
    this.onRecordPause,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Стрим
            _CompactButton(
              icon:
                  status.streamStatus.isActive ? Icons.stop : Icons.play_arrow,
              label: status.streamStatus.isActive
                  ? status.streamStatus.durationString
                  : 'Стрим',
              isActive: status.streamStatus.isActive,
              color: Colors.red,
              onPressed: onStreamToggle,
            ),

            // Запись
            _CompactButton(
              icon: status.recordStatus.isActive
                  ? Icons.stop
                  : Icons.fiber_manual_record,
              label: status.recordStatus.isActive
                  ? status.recordStatus.durationString
                  : 'Запись',
              isActive: status.recordStatus.isActive,
              isPaused: status.recordStatus.isPaused,
              color: Colors.red,
              onPressed: onRecordToggle,
            ),

            // Пауза записи
            if (status.recordStatus.isActive)
              _CompactButton(
                icon: status.recordStatus.isPaused
                    ? Icons.play_arrow
                    : Icons.pause,
                label: status.recordStatus.isPaused ? 'Продолжить' : 'Пауза',
                isActive: status.recordStatus.isPaused,
                color: Colors.orange,
                onPressed: onRecordPause,
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isPaused;
  final Color color;
  final VoidCallback? onPressed;

  const _CompactButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.isPaused = false,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        onPressed?.call();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? (isPaused ? Colors.orange : color)
                    : Colors.grey.shade700,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? color : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
