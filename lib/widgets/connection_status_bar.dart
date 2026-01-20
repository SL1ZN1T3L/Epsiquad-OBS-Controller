import 'package:flutter/material.dart';
import '../models/models.dart';

class ConnectionStatusBar extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final OBSConnection? connection;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback? onReconnect;

  const ConnectionStatusBar({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    this.connection,
    this.error,
    required this.onTap,
    this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    IconData icon;
    String text;

    if (isConnecting) {
      bgColor = Colors.orange;
      icon = Icons.sync;
      text = 'Подключение...';
    } else if (isConnected) {
      bgColor = Colors.green;
      icon = Icons.check_circle;
      text = connection?.name ?? 'Подключено';
    } else {
      bgColor = Colors.red;
      icon = Icons.error;
      text = error ?? 'Не подключено';
    }

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!isConnected && !isConnecting && onReconnect != null)
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: onReconnect,
                  tooltip: 'Переподключиться',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
