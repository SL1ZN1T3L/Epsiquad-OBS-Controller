import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/obs_provider.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика OBS'),
      ),
      body: Consumer<OBSProvider>(
        builder: (context, provider, _) {
          if (!provider.isConnected) {
            return const Center(
              child: Text('Нет подключения к OBS'),
            );
          }

          final stats = provider.stats;
          final status = provider.status;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Производительность
              _buildSection('Производительность', [
                _StatTile(
                  icon: Icons.speed,
                  label: 'CPU',
                  value: '${stats.cpuUsage.toStringAsFixed(1)}%',
                  color: _cpuColor(stats.cpuUsage),
                ),
                _StatTile(
                  icon: Icons.memory,
                  label: 'Память',
                  value: '${stats.memoryUsage.toStringAsFixed(0)} MB',
                  color: Colors.blue,
                ),
                _StatTile(
                  icon: Icons.tv,
                  label: 'FPS',
                  value: stats.activeFps.toStringAsFixed(1),
                  color: _fpsColor(stats.activeFps),
                ),
                _StatTile(
                  icon: Icons.save,
                  label: 'Диск',
                  value: _formatDiskSpace(stats.availableDiskSpace),
                  color: _diskColor(stats.availableDiskSpace),
                ),
              ]),

              const SizedBox(height: 16),

              // Рендер
              _buildSection('Рендеринг', [
                _StatTile(
                  icon: Icons.image,
                  label: 'Всего кадров',
                  value: '${stats.renderTotalFrames}',
                  color: Colors.grey,
                ),
                _StatTile(
                  icon: Icons.broken_image,
                  label: 'Пропущено (рендер)',
                  value: '${stats.renderSkippedFrames} (${stats.renderSkipPercent.toStringAsFixed(2)}%)',
                  color: stats.renderSkippedFrames > 0 ? Colors.orange : Colors.green,
                ),
                _StatTile(
                  icon: Icons.output,
                  label: 'Пропущено (выход)',
                  value: '${stats.outputSkippedFrames} (${stats.outputSkipPercent.toStringAsFixed(2)}%)',
                  color: stats.outputSkippedFrames > 0 ? Colors.orange : Colors.green,
                ),
              ]),

              const SizedBox(height: 16),

              // Стрим
              if (status.streamStatus.isActive)
                _buildSection('Стрим', [
                  _StatTile(
                    icon: Icons.timer,
                    label: 'Длительность',
                    value: status.streamStatus.durationString,
                    color: Colors.red,
                  ),
                ]),

              if (status.streamStatus.isActive)
                const SizedBox(height: 16),

              // Запись
              if (status.recordStatus.isActive)
                _buildSection('Запись', [
                  _StatTile(
                    icon: Icons.timer,
                    label: 'Длительность',
                    value: status.recordStatus.durationString,
                    color: status.recordStatus.isPaused ? Colors.orange : Colors.red,
                  ),
                  _StatTile(
                    icon: Icons.info_outline,
                    label: 'Состояние',
                    value: status.recordStatus.isPaused ? 'На паузе' : 'Запись',
                    color: status.recordStatus.isPaused ? Colors.orange : Colors.green,
                  ),
                ]),

              const SizedBox(height: 16),

              // Версия OBS
              _buildSection('Информация', [
                _StatTile(
                  icon: Icons.info,
                  label: 'OBS Studio',
                  value: status.obsVersion ?? 'N/A',
                  color: Colors.grey,
                ),
                _StatTile(
                  icon: Icons.cable,
                  label: 'WebSocket',
                  value: status.websocketVersion ?? 'N/A',
                  color: Colors.grey,
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Color _cpuColor(double cpu) {
    if (cpu > 80) return Colors.red;
    if (cpu > 50) return Colors.orange;
    return Colors.green;
  }

  Color _fpsColor(double fps) {
    if (fps < 25) return Colors.red;
    if (fps < 55) return Colors.orange;
    return Colors.green;
  }

  Color _diskColor(double mb) {
    if (mb < 1024) return Colors.red;
    if (mb < 5120) return Colors.orange;
    return Colors.green;
  }

  String _formatDiskSpace(double mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
