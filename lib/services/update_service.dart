import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Информация о релизе с GitHub
class ReleaseInfo {
  final String version;
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final String? apkSha256Url;
  final DateTime publishedAt;

  ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.apkDownloadUrl,
    this.apkSha256Url,
    required this.publishedAt,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    // Ищем APK и (опционально) файл контрольной суммы в assets
    String? apkUrl;
    String? shaUrl;
    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String?;
        if (name.endsWith('.apk')) {
          apkUrl ??= url;
        } else if (name.endsWith('.sha256') || name.endsWith('.apk.sha256')) {
          shaUrl ??= url;
        }
      }
    }

    final tagName = json['tag_name'] as String? ?? '';
    // Убираем 'v' из начала тега если есть
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    return ReleaseInfo(
      version: version,
      tagName: tagName,
      name: json['name'] as String? ?? tagName,
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      apkDownloadUrl: apkUrl,
      apkSha256Url: shaUrl,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Результат проверки обновлений
class UpdateCheckResult {
  final bool hasUpdate;
  final ReleaseInfo? latestRelease;
  final String currentVersion;
  final String? error;

  UpdateCheckResult({
    required this.hasUpdate,
    this.latestRelease,
    required this.currentVersion,
    this.error,
  });
}

/// Сервис для проверки и скачивания обновлений с GitHub
/// Канал обновлений
enum UpdateChannel {
  stable, // Только стабильные релизы
  prerelease // Включая пре-релизы (бета, альфа)
}

class UpdateService {
  static const String _repoOwner = 'SL1ZN1T3L';
  static const String _repoName = 'Epsiquad-OBS-Controller';
  static const String _lastCheckKey = 'last_update_check';
  static const String _autoCheckKey = 'auto_check_updates';
  static const String _skippedVersionKey = 'skipped_update_version';
  static const String _updateChannelKey = 'update_channel';

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _requestTimeout = Duration(seconds: 20);

  final SharedPreferences _prefs;

  UpdateService(this._prefs);

  /// Проверяет, включена ли автопроверка обновлений
  bool get autoCheckEnabled => _prefs.getBool(_autoCheckKey) ?? true;

  /// Включает/выключает автопроверку обновлений
  Future<void> setAutoCheckEnabled(bool enabled) async {
    await _prefs.setBool(_autoCheckKey, enabled);
  }

  /// Возвращает текущий канал обновлений
  UpdateChannel get updateChannel {
    final value = _prefs.getString(_updateChannelKey);
    if (value == 'prerelease') return UpdateChannel.prerelease;
    return UpdateChannel.stable;
  }

  /// Устанавливает канал обновлений
  Future<void> setUpdateChannel(UpdateChannel channel) async {
    await _prefs.setString(_updateChannelKey, channel.name);
    // Сбрасываем пропущенную версию при смене канала
    await clearSkippedVersion();
  }

  /// Возвращает версию, которую пользователь пропустил
  String? get skippedVersion => _prefs.getString(_skippedVersionKey);

  /// Сохраняет версию как пропущенную
  Future<void> skipVersion(String version) async {
    await _prefs.setString(_skippedVersionKey, version);
  }

  /// Сбрасывает пропущенную версию
  Future<void> clearSkippedVersion() async {
    await _prefs.remove(_skippedVersionKey);
  }

  /// Возвращает время последней проверки
  DateTime? get lastCheckTime {
    final timestamp = _prefs.getInt(_lastCheckKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Проверяет, нужно ли делать автопроверку (раз в 24 часа)
  bool shouldAutoCheck() {
    if (!autoCheckEnabled) return false;

    final lastCheck = lastCheckTime;
    if (lastCheck == null) return true;

    final now = DateTime.now();
    final diff = now.difference(lastCheck);
    return diff.inHours >= 24;
  }

  /// Проверяет наличие новой версии на GitHub
  Future<UpdateCheckResult> checkForUpdates({bool force = false}) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Получаем список релизов с GitHub API
      final request = await client
          .getUrl(
            Uri.parse(
                'https://api.github.com/repos/$_repoOwner/$_repoName/releases'),
          )
          .timeout(_requestTimeout);
      request.headers.add('Accept', 'application/vnd.github.v3+json');
      request.headers.add('User-Agent', 'OBS-Controller-App');

      final response = await request.close().timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
          error: 'Ошибка сервера: ${response.statusCode}',
        );
      }

      final responseBody =
          await response.transform(utf8.decoder).join().timeout(_requestTimeout);
      final releases = json.decode(responseBody) as List<dynamic>;

      // Ищем релиз в зависимости от выбранного канала
      final allowPrerelease = updateChannel == UpdateChannel.prerelease;
      ReleaseInfo? latestRelease;
      for (final release in releases) {
        final isPrerelease = release['prerelease'] as bool? ?? false;
        final isDraft = release['draft'] as bool? ?? false;

        // Пропускаем черновики всегда
        if (isDraft) continue;

        // Если канал stable - пропускаем пре-релизы
        if (!allowPrerelease && isPrerelease) continue;

        latestRelease = ReleaseInfo.fromJson(release);
        break;
      }

      // Сохраняем время проверки
      await _prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

      if (latestRelease == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
        );
      }

      final hasUpdate = _isNewerVersion(latestRelease.version, currentVersion);

      // Проверяем, не пропустил ли пользователь эту версию (только если не force)
      if (hasUpdate && !force && skippedVersion == latestRelease.version) {
        return UpdateCheckResult(
          hasUpdate: false,
          latestRelease: latestRelease,
          currentVersion: currentVersion,
        );
      }

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        latestRelease: latestRelease,
        currentVersion: currentVersion,
      );
    } catch (e) {
      debugPrint('Ошибка проверки обновлений: $e');
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: '',
        error: 'Ошибка подключения: $e',
      );
    } finally {
      client.close();
    }
  }

  /// Сравнивает версии (поддерживает формат X.Y.Z, суффиксы
  /// пре-релизов и билдов вида 3.8.0-beta+42 отбрасываются)
  bool _isNewerVersion(String remote, String current) {
    try {
      List<int> parseParts(String version) {
        final core = version.split(RegExp(r'[-+]')).first;
        final parts =
            core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
        while (parts.length < 3) {
          parts.add(0);
        }
        return parts;
      }

      final remoteParts = parseParts(remote);
      final currentParts = parseParts(current);

      for (var i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }

      return false;
    } catch (e) {
      debugPrint('Version compare error: $e');
      return false;
    }
  }

  /// Скачивает APK файл обновления
  /// Возвращает путь к скачанному файлу
  Future<String> downloadUpdate(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    if (release.apkDownloadUrl == null) {
      throw Exception('APK файл не найден в релизе');
    }

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse(release.apkDownloadUrl!))
          .timeout(_requestTimeout);
      request.headers.add('User-Agent', 'OBS-Controller-App');

      final response = await request.close().timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Ошибка скачивания: ${response.statusCode}');
      }

      // Получаем директорию для скачивания
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        throw Exception('Не удалось получить директорию для скачивания');
      }

      final fileName = 'OBS-Controller-${release.version}.apk';
      final file = File('${dir.path}/$fileName');

      // Получаем размер файла
      final contentLength = response.contentLength;
      var downloadedBytes = 0;

      // Скачиваем файл
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          if (contentLength > 0 && onProgress != null) {
            onProgress(downloadedBytes / contentLength);
          }
        }
      } finally {
        await sink.close();
      }

      // Проверяем контрольную сумму, если релиз её публикует.
      await _verifyChecksum(client, file, release.apkSha256Url);

      return file.path;
    } finally {
      client.close();
    }
  }

  /// Сверяет SHA256 скачанного файла с опубликованной суммой.
  /// Если релиз не содержит .sha256 — проверка пропускается (не фатально).
  Future<void> _verifyChecksum(
      HttpClient client, File file, String? shaUrl) async {
    if (shaUrl == null) return;
    try {
      final request =
          await client.getUrl(Uri.parse(shaUrl)).timeout(_requestTimeout);
      request.headers.add('User-Agent', 'OBS-Controller-App');
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != 200) return; // не смогли получить — пропускаем

      final body =
          await response.transform(utf8.decoder).join().timeout(_requestTimeout);
      // Формат файла обычно "<hex>  filename" — берём первый токен.
      final expected = body.trim().split(RegExp(r'\s+')).first.toLowerCase();
      if (expected.length != 64) return; // не похоже на sha256 — пропускаем

      final actual = sha256.convert(await file.readAsBytes()).toString();
      if (actual.toLowerCase() != expected) {
        // Файл повреждён или подменён — удаляем и прерываем установку.
        try {
          await file.delete();
        } catch (_) {}
        throw Exception('Контрольная сумма не совпала — файл повреждён');
      }
      debugPrint('APK checksum verified OK');
    } on Exception catch (e) {
      // Ошибку несовпадения пробрасываем, сетевые проблемы проверки — нет.
      if (e.toString().contains('Контрольная сумма')) rethrow;
      debugPrint('Checksum verify skipped: $e');
    }
  }

  /// Устанавливает скачанный APK (открывает установщик)
  /// Возвращает путь к файлу для ручной установки через файловый менеджер
  Future<String> getApkInstallInstructions(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('APK файл не найден');
    }

    return filePath;
  }

  /// Открывает страницу релиза на GitHub
  Future<bool> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
