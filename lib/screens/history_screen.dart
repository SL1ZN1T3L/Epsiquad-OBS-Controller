import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/session_stats.dart';
import '../services/stats_history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    await StatsHistoryService.instance.load();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        actions: [
          if (StatsHistoryService.instance.sessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Очистить всё',
              onPressed: _clearAll,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.stream), text: 'Стримы'),
            Tab(icon: Icon(Icons.fiber_manual_record), text: 'Записи'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _SessionList(
                  sessions: StatsHistoryService.instance.streamSessions,
                  emptyIcon: Icons.stream,
                  emptyText: 'Нет завершённых стримов',
                  onRefresh: _load,
                ),
                _SessionList(
                  sessions: StatsHistoryService.instance.recordSessions,
                  emptyIcon: Icons.fiber_manual_record,
                  emptyText: 'Нет завершённых записей',
                  onRefresh: _load,
                ),
              ],
            ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text('Все записи будут удалены'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StatsHistoryService.instance.clearAll();
      if (mounted) setState(() {});
    }
  }
}

class _SessionList extends StatelessWidget {
  final List<SessionStats> sessions;
  final IconData emptyIcon;
  final String emptyText;
  final VoidCallback onRefresh;

  const _SessionList({
    required this.sessions,
    required this.emptyIcon,
    required this.emptyText,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(emptyText, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionCard(
          session: session,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _SessionDetailScreen(session: session),
            ),
          ),
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SessionStats session;
  final VoidCallback onTap;

  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isStream = session.type == SessionType.stream;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isStream ? Icons.stream : Icons.fiber_manual_record,
                color: isStream ? Colors.red : Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name ?? session.dateString,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.timer, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          session.durationString,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        ),
                        if (session.snapshots.isNotEmpty) ...[
                          const SizedBox(width: 16),
                          Icon(Icons.speed, size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            '${session.avgFps.toStringAsFixed(0)} fps',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.memory, size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            '${session.avgCpu.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (session.starred)
                const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Detail Screen ====================

class _SessionDetailScreen extends StatefulWidget {
  final SessionStats session;

  const _SessionDetailScreen({required this.session});

  @override
  State<_SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<_SessionDetailScreen> {
  late SessionStats _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  @override
  Widget build(BuildContext context) {
    final isStream = _session.type == SessionType.stream;
    final snaps = _session.snapshots;

    return Scaffold(
      appBar: AppBar(
        title: Text(_session.name ?? _session.dateString),
        actions: [
          IconButton(
            icon: Icon(
              _session.starred ? Icons.star : Icons.star_border,
              color: _session.starred ? Colors.amber : null,
            ),
            onPressed: _toggleStar,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Инфо-карточка
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isStream ? Icons.stream : Icons.fiber_manual_record,
                        color: isStream ? Colors.red : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isStream ? 'Стрим' : 'Запись',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _InfoRow('Начало', _session.dateString),
                  _InfoRow('Длительность', _session.durationString),
                  if (snaps.isNotEmpty) ...[
                    _InfoRow('Средний FPS', _session.avgFps.toStringAsFixed(1)),
                    _InfoRow('Средний CPU', '${_session.avgCpu.toStringAsFixed(1)}%'),
                    _InfoRow('Макс CPU', '${_session.maxCpu.toStringAsFixed(1)}%'),
                    _InfoRow('Средняя RAM', '${_session.avgMemory.toStringAsFixed(0)} MB'),
                    _InfoRow('Точек данных', '${snaps.length}'),
                  ],
                ],
              ),
            ),
          ),

          // Графики
          if (snaps.length >= 2) ...[
            const SizedBox(height: 16),
            _ChartCard(
              title: 'FPS',
              color: Colors.green,
              data: snaps.map((s) => FlSpot(s.elapsedSeconds.toDouble(), s.fps)).toList(),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'CPU %',
              color: Colors.orange,
              data: snaps
                  .map((s) => FlSpot(s.elapsedSeconds.toDouble(), s.cpuUsage))
                  .toList(),
            ),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'RAM (MB)',
              color: Colors.blue,
              data: snaps
                  .map((s) => FlSpot(s.elapsedSeconds.toDouble(), s.memoryUsage))
                  .toList(),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'Недостаточно данных для графиков',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleStar() async {
    final updated = _session.copyWith(starred: !_session.starred);
    await StatsHistoryService.instance.updateSession(updated);
    setState(() => _session = updated);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final nav = Navigator.of(context);
      await StatsHistoryService.instance.deleteSession(_session.id);
      nav.pop();
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<FlSpot> data;

  const _ChartCard({
    required this.title,
    required this.color,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 14)),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _calcInterval(),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.shade800,
                      strokeWidth: 0.5,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: _calcTimeInterval(),
                        getTitlesWidget: (value, meta) {
                          final m = (value ~/ 60).toString();
                          return Text('${m}m',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500));
                        },
                      ),
                    ),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: color,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                                s.y.toStringAsFixed(1),
                                TextStyle(color: color, fontSize: 12),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calcInterval() {
    if (data.isEmpty) return 10;
    final maxY = data.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    if (maxY > 1000) return 500;
    if (maxY > 100) return 25;
    if (maxY > 10) return 5;
    return 1;
  }

  double _calcTimeInterval() {
    if (data.isEmpty) return 60;
    final maxX = data.last.x;
    if (maxX > 7200) return 1800;
    if (maxX > 3600) return 900;
    if (maxX > 600) return 300;
    return 60;
  }
}
