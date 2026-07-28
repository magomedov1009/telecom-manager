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
  });

  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;

  bool get available =>
      _versionNumber(latestVersion) > _versionNumber(currentVersion);

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
  static const _latestRelease =
      'https://api.github.com/repos/magomedov1009/telecom-manager/releases/latest';

  Future<AppUpdate> check() async {
    final package = await PackageInfo.fromPlatform();
    final response = await http.get(
      Uri.parse(_latestRelease),
      headers: const {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Не удалось проверить обновление (${response.statusCode})',
      );
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final assets = body['assets'] as List? ?? const [];
    Map<String, Object?>? apk;
    for (final raw in assets) {
      final asset = Map<String, Object?>.from(raw as Map);
      if (asset['name'] == 'app-release.apk') {
        apk = asset;
        break;
      }
    }
    if (apk == null) throw StateError('APK не найден в последнем выпуске');
    return AppUpdate(
      currentVersion: package.version,
      latestVersion: (body['tag_name'] as String).replaceFirst('android-v', ''),
      downloadUrl: apk['browser_download_url']! as String,
    );
  }

  Future<void> downloadAndInstall(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await http.Request(
      'GET',
      Uri.parse(update.downloadUrl),
    ).send();
    if (response.statusCode != 200) {
      throw StateError('Не удалось скачать APK (${response.statusCode})');
    }
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/telecom-manager-${update.latestVersion}.apk',
    );
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, response.contentLength ?? 0);
    }
    await sink.close();
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) throw StateError(result.message);
  }
}
