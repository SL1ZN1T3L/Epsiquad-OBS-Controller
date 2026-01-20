import 'package:flutter/material.dart';
import '../models/models.dart';

class ConnectionStatusWidget extends StatelessWidget {
  final bool isConnected;
  final OBSStatus status;

  const ConnectionStatusWidget({
    super.key,
    required this.isConnected,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    if (isConnected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            const Text(
              'Подключено к OBS',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (status.obsVersion != null)
              Text(
                'OBS ${status.obsVersion}',
                style: const TextStyle(color: Colors.grey),
              ),
          ],
        ),
      );
    }

    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.link_off,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'Не подключено',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Нажмите на панель сверху\nдля подключения к OBS',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
