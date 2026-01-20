import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Виджет для прогрева шейдеров при первом запуске
/// Рендерит основные UI элементы невидимо, чтобы скомпилировать шейдеры
class ShaderWarmup extends StatefulWidget {
  final Widget child;
  
  const ShaderWarmup({super.key, required this.child});

  @override
  State<ShaderWarmup> createState() => _ShaderWarmupState();
}

class _ShaderWarmupState extends State<ShaderWarmup> {
  bool _isWarmedUp = false;
  bool _showWarmup = false;
  
  @override
  void initState() {
    super.initState();
    _checkWarmup();
  }
  
  Future<void> _checkWarmup() async {
    final prefs = await SharedPreferences.getInstance();
    final warmedUp = prefs.getBool('shaderWarmedUp') ?? false;
    
    if (warmedUp) {
      // Уже прогрето ранее
      setState(() => _isWarmedUp = true);
    } else {
      // Нужен прогрев
      setState(() => _showWarmup = true);
      
      // Даём время на рендер warmup виджетов
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Отмечаем как прогретое
      await prefs.setBool('shaderWarmedUp', true);
      
      setState(() {
        _showWarmup = false;
        _isWarmedUp = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWarmedUp) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Основной splash
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam, size: 64, color: Colors.blue),
                  SizedBox(height: 16),
                  Text(
                    'OBS Controller',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Загрузка...',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            
            // Невидимый слой с виджетами для прогрева шейдеров
            if (_showWarmup)
              Opacity(
                opacity: 0.01, // Почти невидимо, но рендерится
                child: IgnorePointer(
                  child: _WarmupWidgets(),
                ),
              ),
          ],
        ),
      );
    }
    
    return widget.child;
  }
}

/// Виджеты для прогрева шейдеров
class _WarmupWidgets extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Кнопки
          ElevatedButton(onPressed: () {}, child: const Text('Button')),
          FilledButton(onPressed: () {}, child: const Text('Filled')),
          OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
          IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
          FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
          
          // Карточки
          Card(
            child: ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Title'),
              subtitle: const Text('Subtitle'),
              trailing: Switch(value: true, onChanged: (_) {}),
            ),
          ),
          
          // Слайдер
          Slider(value: 0.5, onChanged: (_) {}),
          
          // Прогресс
          const CircularProgressIndicator(),
          const LinearProgressIndicator(),
          
          // Табы
          DefaultTabController(
            length: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.tv)),
                    Tab(icon: Icon(Icons.layers)),
                    Tab(icon: Icon(Icons.volume_up)),
                  ],
                ),
                SizedBox(
                  height: 50,
                  child: TabBarView(
                    children: [
                      Container(),
                      Container(),
                      Container(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Чипы
          const Chip(label: Text('Chip')),
          const FilterChip(label: Text('Filter'), selected: true, onSelected: null),
          
          // Диалог элементы
          const AlertDialog(
            title: Text('Title'),
            content: Text('Content'),
          ),
          
          // Контейнеры с градиентами
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.blue, Colors.purple],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          
          // Иконки
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, size: 48),
              Icon(Icons.pause, size: 48),
              Icon(Icons.stop, size: 48),
              Icon(Icons.fiber_manual_record, size: 48, color: Colors.red),
              Icon(Icons.visibility, size: 48),
              Icon(Icons.visibility_off, size: 48),
            ],
          ),
          
          // Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            children: List.generate(9, (i) => Card(
              child: Center(child: Text('$i')),
            )),
          ),
        ],
      ),
    );
  }
}
