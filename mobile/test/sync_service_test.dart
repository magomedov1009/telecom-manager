import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:telecom_manager_mobile/core/database/app_database.dart';
import 'package:telecom_manager_mobile/core/repositories/local_repository.dart';
import 'package:telecom_manager_mobile/core/sync/sync_service.dart';

class MemoryTokenStore implements TokenStore {
  String? token;
  @override
  Future<void> clear() async => token = null;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async => token = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('connect securely stores token and sync acknowledges queue', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: inMemoryDatabasePath,
    );
    final repository = LocalRepository(database);
    await repository.initialize();
    final tokenStore = MemoryTokenStore();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        return http.Response(
          jsonEncode({
            'token': 'secret-device-token',
            'organization_id': 1,
            'organization_name': 'Test',
            'user_id': 1,
            'role': 'admin',
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/sync/push')) {
        final changes =
            (jsonDecode(request.body) as Map<String, Object?>)['changes']!
                as List;
        return http.Response(
          jsonEncode(
            changes
                .map(
                  (raw) => {
                    'entity_type': (raw as Map)['entity_type'],
                    'entity_id': raw['entity_id'],
                    'status': 'accepted',
                    'server_version': 1,
                  },
                )
                .toList(),
          ),
          200,
        );
      }
      return http.Response(
        jsonEncode({'cursor': 0, 'has_more': false, 'changes': []}),
        200,
      );
    });
    final service = SyncService(
      repository: repository,
      serverUrl: 'https://example.test',
      client: client,
      tokenStore: tokenStore,
    );

    await service.connect(
      username: 'admin',
      password: 'secret',
      deviceName: 'test',
    );
    expect(tokenStore.token, 'secret-device-token');
    final result = await service.synchronize();
    expect(result.sent, 10);
    expect(await repository.pendingChanges(), 0);
    await database.close();
  });
}
