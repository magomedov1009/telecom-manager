import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
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

class FakeSyncServer {
  final records = <String, Map<String, Object?>>{};
  final changes = <Map<String, Object?>>[];
  var tokenNumber = 0;

  http.Response jsonResponse(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  late final http.Client client = MockClient((request) async {
    if (request.url.path.endsWith('/login')) {
      tokenNumber++;
      return jsonResponse({
        'token': 'token-$tokenNumber',
        'organization_id': 10,
        'organization_name': 'Общая организация',
        'user_id': 1,
        'username': 'admin',
        'full_name': 'Администратор',
        'role': 'admin',
        'organizations': [
          {'id': 10, 'name': 'Общая организация', 'role': 'admin'},
        ],
      }, 200);
    }
    if (request.url.path.endsWith('/sync/push')) {
      final incoming =
          (jsonDecode(request.body) as Map<String, Object?>)['changes']!
              as List;
      final results = <Map<String, Object?>>[];
      for (final raw in incoming) {
        final item = Map<String, Object?>.from(raw as Map);
        final key = '${item['entity_type']}:${item['entity_id']}';
        final existing = records[key];
        final version = (item['version']! as num).toInt();
        final existingVersion = (existing?['version'] as num?)?.toInt() ?? 0;
        if (existing != null && version <= existingVersion) {
          final duplicate =
              version == existingVersion &&
              jsonEncode(existing['payload']) == jsonEncode(item['payload']);
          results.add({
            'entity_type': item['entity_type'],
            'entity_id': item['entity_id'],
            'status': duplicate ? 'duplicate' : 'conflict',
            'server_version': existingVersion,
          });
          continue;
        }
        records[key] = item;
        changes.add({'cursor': changes.length + 1, ...item});
        results.add({
          'entity_type': item['entity_type'],
          'entity_id': item['entity_id'],
          'status': 'accepted',
          'server_version': version,
        });
      }
      return jsonResponse(results, 200);
    }
    if (request.url.path.endsWith('/sync/pull')) {
      final cursor = int.parse(request.url.queryParameters['cursor'] ?? '0');
      final result = changes
          .where((item) => (item['cursor']! as int) > cursor)
          .toList();
      return jsonResponse({
        'cursor': result.isEmpty ? cursor : result.last['cursor']! as int,
        'has_more': false,
        'changes': result,
      }, 200);
    }
    return http.Response('{}', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'connect creates isolated server workspace and acknowledges queue',
    () async {
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
              'username': 'admin',
              'full_name': 'Administrator',
              'role': 'admin',
              'organizations': [
                {'id': 1, 'name': 'Test', 'role': 'admin'},
                {'id': 2, 'name': 'Second', 'role': 'manager'},
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/organizations') &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({'id': 3, 'name': 'New city', 'role': 'admin'}),
            200,
          );
        }
        if (request.url.path.endsWith('/members') && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'user_id': 7,
              'username': 'worker',
              'full_name': 'Worker',
              'role': 'installer',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/members') && request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'user_id': 7,
                'username': 'worker',
                'full_name': 'Worker',
                'role': 'installer',
              },
            ]),
            200,
          );
        }
        if (request.url.path.contains('/members/') &&
            request.method == 'DELETE') {
          return http.Response('', 204);
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

      final connection = await service.connect(
        username: 'admin',
        password: 'secret',
        deviceName: 'test',
      );
      expect(connection.organizations, hasLength(2));
      expect(tokenStore.token, 'secret-device-token');
      expect((await repository.dashboardSummary()).organizationName, 'Test');
      expect((await service.createOrganization('New city')).id, 3);
      expect(
        (await service.addMember(username: 'worker', role: 'installer')).userId,
        7,
      );
      expect(await service.members(), hasLength(1));
      await service.removeMember(7);
      await repository.addProvider('После подключения');
      final result = await service.synchronize();
      expect(result.sent, 1);
      expect(await repository.pendingChanges(), 0);
      await database.close();
    },
  );

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

  test('two devices exchange edits through one organization', () async {
    final temp = Directory.systemTemp.createTempSync('telecom-two-devices-');
    final firstDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: path.join(temp.path, 'first.db'),
    );
    final secondDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: path.join(temp.path, 'second.db'),
    );
    final firstRepository = LocalRepository(firstDatabase);
    final secondRepository = LocalRepository(secondDatabase);
    await firstRepository.initialize();
    await secondRepository.initialize();
    final server = FakeSyncServer();
    final firstService = SyncService(
      repository: firstRepository,
      serverUrl: 'https://sync.test',
      client: server.client,
      tokenStore: MemoryTokenStore(),
    );
    final secondService = SyncService(
      repository: secondRepository,
      serverUrl: 'https://sync.test',
      client: server.client,
      tokenStore: MemoryTokenStore(),
    );
    await firstService.connect(
      username: 'admin',
      password: 'secret',
      deviceName: 'first',
    );
    await secondService.connect(
      username: 'admin',
      password: 'secret',
      deviceName: 'second',
    );

    await firstRepository.addProvider('Городская сеть');
    await firstService.synchronize();
    final received = await secondService.synchronize();
    expect(received.received, 1);
    var remoteProvider = (await secondRepository.providerCatalog()).single;
    expect(remoteProvider.name, 'Городская сеть');

    await secondRepository.updateProvider(
      providerId: remoteProvider.id,
      name: 'Городская сеть 2',
    );
    await secondService.synchronize();
    await firstService.synchronize();
    remoteProvider = (await firstRepository.providerCatalog()).single;
    expect(remoteProvider.name, 'Городская сеть 2');

    await firstDatabase.close();
    await secondDatabase.close();
    temp.deleteSync(recursive: true);
  });
}
