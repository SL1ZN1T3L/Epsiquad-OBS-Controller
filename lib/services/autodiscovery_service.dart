import 'dart:async';
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
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(ip, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return DiscoveredOBS(
        ip: ip,
        port: port,
        responseTimeMs: sw.elapsedMilliseconds,
      );
    } catch (_) {
      return null;
    }
  }
}
