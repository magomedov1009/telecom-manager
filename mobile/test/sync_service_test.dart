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

  test('remote changes are applied in dependency order', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: inMemoryDatabasePath,
    );
    final repository = LocalRepository(database);
    await repository.initialize();
    final now = DateTime(2026, 7, 27).toUtc().toIso8601String();

    await repository.applyRemoteChanges([
      {
        'entity_type': 'warehouse',
        'entity_id': 'warehouse-remote',
        'operation': 'upsert',
        'version': 1,
        'payload': {
          'id': 'warehouse-remote',
          'organization_id': 'server-org',
          'provider_id': 'provider-remote',
          'name': 'Удалённый склад',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        },
      },
      {
        'entity_type': 'provider',
        'entity_id': 'provider-remote',
        'operation': 'upsert',
        'version': 1,
        'payload': {
          'id': 'provider-remote',
          'organization_id': 'server-org',
          'name': 'Удалённый провайдер',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        },
      },
    ], 2);

    expect(
      (await repository.providers()).map((item) => item.name),
      contains('Удалённый провайдер'),
    );
    expect(
      (await repository.warehouses()).map((item) => item.name),
      contains('Удалённый склад'),
    );
    expect(await repository.syncCursor(), 2);
    await database.close();
  });

  test('remote pull never overwrites an unsent local edit', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: inMemoryDatabasePath,
    );
    final repository = LocalRepository(database);
    await repository.initialize();
    for (final item in await repository.syncQueue()) {
      await repository.acknowledgeSync(item.entityType, item.entityId);
    }
    await repository.addProvider('Локальное имя');
    final provider = (await repository.providerCatalog()).singleWhere(
      (item) => item.name == 'Локальное имя',
    );
    final now = DateTime(2026, 7, 27).toUtc().toIso8601String();

    await repository.applyRemoteChanges([
      {
        'entity_type': 'provider',
        'entity_id': provider.id,
        'operation': 'upsert',
        'version': 1,
        'payload': {
          'id': provider.id,
          'organization_id': 'server-org',
          'name': 'Серверное имя',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'synced',
        },
      },
    ], 1);

    expect(
      (await repository.providerCatalog())
          .singleWhere((item) => item.id == provider.id)
          .name,
      'Локальное имя',
    );
    expect((await repository.syncQueue()).single.entityId, provider.id);
    expect(await repository.syncCursor(), 1);
    await database.close();
  });
}
