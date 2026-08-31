import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'log_service.dart';

class DiscoveredOBS {
  final String ip;
  final int port;
  final int responseTimeMs;

  DiscoveredOBS({
    required this.ip,
    required this.port,
    required this.responseTimeMs,
  });
}

class AutoDiscoveryService {
  static const _tag = 'Discovery';

  /// Сканирует подсеть на наличие OBS WebSocket серверов
  static Future<List<DiscoveredOBS>> scan({
    int port = 4455,
    Duration timeout = const Duration(milliseconds: 800),
    void Function(int scanned, int total)? onProgress,
  }) async {
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();

    if (wifiIP == null) {
      log.w(_tag, 'No WiFi IP address found');
      return [];
    }

    log.i(_tag, 'Starting scan from $wifiIP on port $port');

    final subnet = wifiIP.substring(0, wifiIP.lastIndexOf('.'));
    final results = <DiscoveredOBS>[];
    int scanned = 0;
    const total = 254;

    // Сканируем батчами по 30 для баланса скорости и нагрузки
    const batchSize = 30;
    for (int start = 1; start <= 254; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, 254);
      final futures = <Future<DiscoveredOBS?>>[];

      for (int i = start; i <= end; i++) {
        final ip = '$subnet.$i';
        futures.add(_checkHost(ip, port, timeout));
      }

      final batch = await Future.wait(futures);
      for (final result in batch) {
        if (result != null) {
          results.add(result);
          log.i(_tag, 'Found OBS at ${result.ip}:${result.port} (${result.responseTimeMs}ms)');
        }
      }

      scanned += (end - start + 1);
      onProgress?.call(scanned, total);
    }

    log.i(_tag, 'Scan complete: ${results.length} found');
    return results;
  }

  static Future<DiscoveredOBS?> _checkHost(
      String ip, int port, Duration timeout) async {
    Socket? socket;
    try {
      final sw = Stopwatch()..start();
      socket = await Socket.connect(ip, port, timeout: timeout);
      sw.stop();
      socket.destroy();

      // Открытый порт — ещё не OBS. Подтверждаем WebSocket-хендшейком:
      // obs-websocket сразу присылает Hello (op=0). Это отсекает любые
      // другие сервисы, случайно слушающие тот же порт.
      final confirmed = await _verifyObs(ip, port, timeout);
      if (!confirmed) return null;

      return DiscoveredOBS(
        ip: ip,
        port: port,
        responseTimeMs: sw.elapsedMilliseconds,
      );
    } catch (_) {
      socket?.destroy();
      return null;
    }
  }

  /// Подключается по WebSocket и проверяет, что первый кадр — Hello (op=0).
  static Future<bool> _verifyObs(String ip, int port, Duration timeout) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect('ws://$ip:$port').timeout(timeout);
      final firstMessage = await ws.first.timeout(timeout);
      final data = json.decode(firstMessage as String) as Map<String, dynamic>;
      return data['op'] == 0;
    } catch (_) {
      return false;
    } finally {
      try {
        await ws?.close();
      } catch (_) {}
    }
  }
}
