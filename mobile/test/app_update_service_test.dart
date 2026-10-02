import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telecom_manager_mobile/core/update/app_update_service.dart';

void main() {
  group('AppUpdateService', () {
    test('chooses the newer version across server and GitHub releases', () async {
      const serverUrl = 'https://cloud.example.ru';
      final client = _ReleaseClient({
        '$serverUrl/api/mobile/update': _release('android-v1.1.1'),
        'https://api.github.com/repos/magomedov1009/telecom-manager/releases/latest':
            _release('android-v1.1.2'),
      });
      final service = AppUpdateService(
        client: client,
        currentVersionProvider: () async => '1.1.1',
      );

      final update = await service.check(serverUrl: serverUrl);

      expect(update.latestVersion, '1.1.2');
      expect(update.available, isTrue);
      expect(client.requestedUrls, hasLength(2));
    });

    test('uses a valid server release when GitHub cannot be reached', () async {
      const serverUrl = 'https://cloud.example.ru';
      final client = _ReleaseClient({
        '$serverUrl/api/mobile/update': _release('android-v1.1.2'),
      });
      final service = AppUpdateService(
        client: client,
        currentVersionProvider: () async => '1.1.1',
      );

      final update = await service.check(serverUrl: serverUrl);

      expect(update.latestVersion, '1.1.2');
      expect(update.available, isTrue);
    });

    test(
      'routes Google Play installs to the store instead of APK sideloading',
      () async {
        final client = _ReleaseClient({});
        final service = AppUpdateService(
          client: client,
          currentVersionProvider: () async => '1.1.1',
          installerStoreProvider: () async => 'com.android.vending',
        );

        final update = await service.check();

        expect(update.playStoreManaged, isTrue);
        expect(update.available, isFalse);
        expect(update.downloadUrl, AppUpdate.playStoreUrl);
        expect(client.requestedUrls, isEmpty);
        await expectLater(
          service.downloadAndInstall(update),
          throwsStateError,
        );
      },
    );
  });
}

http.Response _release(String tag) => http.Response(
  jsonEncode({
    'tag_name': tag,
    'assets': [
      {
        'name': 'app-release.apk',
        'browser_download_url': 'https://example.com/$tag/app-release.apk',
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

class _ReleaseClient extends http.BaseClient {
  _ReleaseClient(this.responses);

  final Map<String, http.Response> responses;
  final List<String> requestedUrls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    requestedUrls.add(url);
    final response = responses[url];
    if (response == null) {
      throw const FormatException('Release source unavailable');
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
