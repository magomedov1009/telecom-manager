import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdate {
  const AppUpdate({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.playStoreManaged = false,
  });

  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final bool playStoreManaged;

  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id='
      'ru.telecommanager.telecom_manager_mobile';

  bool get available =>
      _versionNumber(latestVersion) > _versionNumber(currentVersion);

  static int compareVersions(String left, String right) =>
      _versionNumber(left).compareTo(_versionNumber(right));

  static int _versionNumber(String value) {
    final parts = value.replaceFirst(RegExp(r'^[^0-9]*'), '').split('.');
    var result = 0;
    for (var index = 0; index < 3; index++) {
      result =
          result * 1000 +
          (index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0);
    }
    return result;
  }
}

class AppUpdateService {
  AppUpdateService({
    this.client,
    this.currentVersionProvider,
    this.installerStoreProvider,
  });

  static const _latestRelease =
      'https://api.github.com/repos/magomedov1009/telecom-manager/releases/latest';

  final http.Client? client;
  final Future<String> Function()? currentVersionProvider;
  final Future<String?> Function()? installerStoreProvider;

  Future<AppUpdate> check({String? serverUrl}) async {
    final packageInfo = currentVersionProvider == null
        ? await PackageInfo.fromPlatform()
        : null;
    final currentVersion = currentVersionProvider == null
        ? packageInfo!.version
        : await currentVersionProvider!();
    final installerStore = installerStoreProvider == null
        ? packageInfo?.installerStore
        : await installerStoreProvider!();
    if (installerStore == 'com.android.vending') {
      return AppUpdate(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        downloadUrl: AppUpdate.playStoreUrl,
        playStoreManaged: true,
      );
    }
    final urls = <String>[
      if (serverUrl != null && serverUrl.trim().isNotEmpty)
        '${serverUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/mobile/update',
      _latestRelease,
    ];
    Object? lastError;
    AppUpdate? newest;
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        const headers = {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Telecom-Manager-Android',
        };
        final responseFuture = client == null
            ? http.get(uri, headers: headers)
            : client!.get(uri, headers: headers);
        final response = await responseFuture.timeout(
          const Duration(seconds: 12),
        );
        if (response.statusCode != 200) {
          throw StateError('HTTP ${response.statusCode}');
        }
        final candidate = _parse(currentVersion, response.body);
        if (newest == null ||
            AppUpdate.compareVersions(
                  candidate.latestVersion,
                  newest.latestVersion,
                ) >
                0) {
          newest = candidate;
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (newest != null) return newest;
    throw StateError('Не удалось проверить обновление: $lastError');
  }

  AppUpdate _parse(String currentVersion, String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, Object?>;
    final assets = body['assets'] as List? ?? const [];
    Map<String, Object?>? apk;
    for (final raw in assets) {
      final asset = Map<String, Object?>.from(raw as Map);
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apk = asset;
        break;
      }
    }
    if (apk == null) throw StateError('APK не найден в последнем выпуске');
    return AppUpdate(
      currentVersion: currentVersion,
      latestVersion: (body['tag_name'] as String).replaceFirst('android-v', ''),
      downloadUrl: apk['browser_download_url']! as String,
    );
  }

  Future<void> downloadAndInstall(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (update.playStoreManaged) {
      throw StateError('Обновляйте приложение через Google Play');
    }
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/telecom-manager-${update.latestVersion}.apk',
    );
    final canonicalUrl =
        'https://github.com/magomedov1009/telecom-manager/releases/download/'
        'android-v${update.latestVersion}/app-release.apk';
    Object? lastError;
    for (final url in {update.downloadUrl, canonicalUrl}) {
      try {
        final response = await http.Request('GET', Uri.parse(url)).send();
        if (response.statusCode != 200) {
          throw StateError('HTTP ${response.statusCode}');
        }
        final sink = file.openWrite();
        var received = 0;
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, response.contentLength ?? 0);
        }
        await sink.close();
        final header = await file
            .openRead(0, 4)
            .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
        if (header.length < 4 || header[0] != 0x50 || header[1] != 0x4b) {
          throw StateError('Сервер вернул не APK-файл');
        }
        lastError = null;
        break;
      } catch (error) {
        lastError = error;
        if (await file.exists()) await file.delete();
      }
    }
    if (lastError != null || !await file.exists()) {
      throw StateError('Не удалось скачать корректный APK: $lastError');
    }
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) throw StateError(result.message);
  }
}
