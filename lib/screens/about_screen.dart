import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('О приложении'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Лого и название
          const Icon(
            Icons.cast_connected,
            size: 80,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          const Text(
            'Epsiquad OBS Controller',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _version.isEmpty
                ? 'Загрузка...'
                : 'Версия $_version ($_buildNumber)',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          // Описание
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Профессиональное управление OBS Studio',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Полнофункциональное приложение для удалённого управления OBS Studio через WebSocket. '
                    'Переключение сцен, управление записью и стримом, настройка аудио и многое другое.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Создатели
          const Text(
            'Создатели',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          _buildCreatorCard(
            context,
            name: 'Epsiquad',
            role: 'Разработка и дизайн',
            icon: Icons.code,
          ),

          const SizedBox(height: 24),

          // Функции
          const Text(
            'Основные возможности',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          _buildFeatureItem(Icons.tv, 'Переключение сцен'),
          _buildFeatureItem(Icons.fiber_manual_record, 'Запись с паузой'),
          _buildFeatureItem(Icons.stream, 'Управление стримом'),
          _buildFeatureItem(Icons.volume_up, 'Контроль аудио'),
          _buildFeatureItem(Icons.layers, 'Управление источниками'),
          _buildFeatureItem(Icons.camera_alt, 'Скриншоты'),
          _buildFeatureItem(Icons.replay, 'Replay Buffer'),
          _buildFeatureItem(Icons.videocam, 'Виртуальная камера'),
          _buildFeatureItem(Icons.keyboard, 'Горячие клавиши'),
          _buildFeatureItem(
              Icons.dashboard_customize, 'Кастомизация интерфейса'),
          _buildFeatureItem(Icons.palette, 'Настройка цветов и иконок'),
          _buildFeatureItem(Icons.account_tree, 'Профили управления'),

          const SizedBox(height: 24),

          // Технологии
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Технологии',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTechItem('Flutter', 'UI Framework'),
                  _buildTechItem('OBS WebSocket 5.x', 'Protocol'),
                  _buildTechItem('Provider', 'State Management'),
                  _buildTechItem('SharedPreferences', 'Local Storage'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // GitHub
          Card(
            child: ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Open Source'),
              subtitle:
                  const Text('github.com/SL1ZN1T3L/Epsiquad-OBS-Controller'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openGitHub(),
            ),
          ),

          const SizedBox(height: 16),

          // Лицензия
          const Text(
            '© 2026 Epsiquad & Claude\nGPL 2.0 License',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Widget _buildCreatorCard(
    BuildContext context, {
    required String name,
    required String role,
    required IconData icon,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(role),
      ),
    );
  }

  static Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }

  static Widget _buildTechItem(String name, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            description,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static Future<void> _openGitHub() async {
    final uri =
        Uri.parse('https://github.com/SL1ZN1T3L/Epsiquad-OBS-Controller');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
