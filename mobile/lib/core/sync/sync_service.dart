import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../repositories/local_repository.dart';

abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: 'mobile_sync_token');
  @override
  Future<void> write(String token) =>
      _storage.write(key: 'mobile_sync_token', value: token);
  @override
  Future<void> clear() => _storage.delete(key: 'mobile_sync_token');
}

class SyncResult {
  const SyncResult({
    required this.sent,
    required this.received,
    required this.conflicts,
  });
  final int sent;
  final int received;
  final int conflicts;
}

class SyncService {
  SyncService({
    required this.repository,
    required this.serverUrl,
    http.Client? client,
    TokenStore? tokenStore,
  }) : client = client ?? http.Client(),
       tokenStore = tokenStore ?? const SecureTokenStore();

  final LocalRepository repository;
  final String serverUrl;
  final http.Client client;
  final TokenStore tokenStore;

  Uri endpoint(String path, [Map<String, String>? query]) => Uri.parse(
    '${serverUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/mobile$path',
  ).replace(queryParameters: query);

  Future<void> connect({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    final response = await client.post(
      endpoint('/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'device_name': deviceName,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('Сервер отклонил вход (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    await tokenStore.write(body['token']! as String);
    await repository.bindRemoteOrganization(
      serverUrl: serverUrl,
      remoteOrganizationId: '${body['organization_id']}',
      organizationName: body['organization_name']! as String,
      username: (body['username'] as String?) ?? username.trim(),
      fullName:
          (body['full_name'] as String?) ??
          (body['username'] as String?) ??
          username.trim(),
      role: body['role']! as String,
      password: password,
    );
  }

  Future<SyncResult> synchronize() async {
    final token = await tokenStore.read();
    if (token == null) throw StateError('Сначала подключитесь к серверу');
    if (!await repository.syncTargetMatches(serverUrl)) {
      throw StateError(
        'Выбранная организация не связана с этим подключением. '
        'Подключите устройство заново.',
      );
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    var sent = 0;
    var received = 0;
    var conflicts = 0;
    final queue = await repository.syncQueue(limit: 500);
    if (queue.isNotEmpty) {
      final response = await client.post(
        endpoint('/sync/push'),
        headers: headers,
        body: jsonEncode({
          'changes': queue
              .map(
                (item) => {
                  'entity_type': item.entityType,
                  'entity_id': item.entityId,
                  'operation': item.operation,
                  'version': item.version,
                  'payload': item.payload,
                },
              )
              .toList(),
        }),
      );
      if (response.statusCode != 200) {
        throw StateError('Ошибка отправки (${response.statusCode})');
      }
      final results = jsonDecode(response.body) as List;
      for (final raw in results) {
        final result = raw as Map<String, Object?>;
        final type = result['entity_type']! as String;
        final id = result['entity_id']! as String;
        if (result['status'] == 'conflict') {
          conflicts++;
          await repository.markSyncError(type, id, 'Конфликт версии');
        } else {
          sent++;
          await repository.acknowledgeSync(type, id);
        }
      }
    }
    var cursor = await repository.syncCursor();
    var hasMore = true;
    while (hasMore) {
      final response = await client.get(
        endpoint('/sync/pull', {'cursor': '$cursor', 'limit': '200'}),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw StateError('Ошибка получения (${response.statusCode})');
      }
      final body = jsonDecode(response.body) as Map<String, Object?>;
      final changes = (body['changes']! as List)
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
      cursor = (body['cursor']! as num).toInt();
      await repository.applyRemoteChanges(changes, cursor);
      received += changes.length;
      hasMore = body['has_more']! as bool;
    }
    return SyncResult(sent: sent, received: received, conflicts: conflicts);
  }
}
