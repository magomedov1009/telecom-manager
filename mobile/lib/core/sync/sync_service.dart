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

class ServerOrganization {
  const ServerOrganization({
    required this.id,
    required this.name,
    required this.role,
  });

  final int id;
  final String name;
  final String role;

  factory ServerOrganization.fromJson(Map<String, Object?> json) =>
      ServerOrganization(
        id: (json['id']! as num).toInt(),
        name: json['name']! as String,
        role: json['role']! as String,
      );
}

class ServerMember {
  const ServerMember({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
  });

  final int userId;
  final String username;
  final String fullName;
  final String role;

  factory ServerMember.fromJson(Map<String, Object?> json) => ServerMember(
    userId: (json['user_id']! as num).toInt(),
    username: json['username']! as String,
    fullName: json['full_name']! as String,
    role: json['role']! as String,
  );
}

class ServerConnection {
  const ServerConnection({
    required this.organizationId,
    required this.organizations,
  });

  final int organizationId;
  final List<ServerOrganization> organizations;
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

  static String normalizeServerUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return normalized;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    normalized = normalized.replaceFirst(
      RegExp(r'/(?:dashboard|login)(?:/.*)?$', caseSensitive: false),
      '',
    );
    normalized = normalized.replaceFirst(
      RegExp(r'/api/mobile(?:/.*)?$', caseSensitive: false),
      '',
    );
    return normalized.replaceAll(RegExp(r'/+$'), '');
  }

  String get normalizedServerUrl => normalizeServerUrl(serverUrl);

  Uri endpoint(String path, [Map<String, String>? query]) => Uri.parse(
    '$normalizedServerUrl/api/mobile$path',
  ).replace(queryParameters: query);

  Future<ServerConnection> connect({
    required String username,
    required String password,
    required String deviceName,
    int? organizationId,
  }) async {
    final response = await client.post(
      endpoint('/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'device_name': deviceName,
        'organization_id': ?organizationId,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('Сервер отклонил вход (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    await tokenStore.write(body['token']! as String);
    await repository.bindRemoteOrganization(
      serverUrl: normalizedServerUrl,
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
    return ServerConnection(
      organizationId: (body['organization_id']! as num).toInt(),
      organizations: ((body['organizations'] as List?) ?? const [])
          .map(
            (item) => ServerOrganization.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final token = await tokenStore.read();
    if (token == null) throw StateError('Сначала подключитесь к серверу');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Never _serverError(http.Response response) {
    var message = 'Ошибка сервера (${response.statusCode})';
    try {
      final body = jsonDecode(response.body) as Map<String, Object?>;
      message = body['detail']?.toString() ?? message;
    } catch (_) {}
    throw StateError(message);
  }

  Future<ServerOrganization> createOrganization(String name) async {
    final response = await client.post(
      endpoint('/organizations'),
      headers: await _authorizedHeaders(),
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 200) _serverError(response);
    return ServerOrganization.fromJson(
      Map<String, Object?>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<List<ServerMember>> members() async {
    final binding = await repository.remoteOrganizationBinding();
    if (binding == null) throw StateError('Организация не подключена');
    final response = await client.get(
      endpoint('/organizations/${binding.remoteOrganizationId}/members'),
      headers: await _authorizedHeaders(),
    );
    if (response.statusCode != 200) _serverError(response);
    return (jsonDecode(response.body) as List)
        .map(
          (item) =>
              ServerMember.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList();
  }

  Future<ServerMember> addMember({
    required String username,
    required String role,
  }) async {
    final binding = await repository.remoteOrganizationBinding();
    if (binding == null) throw StateError('Организация не подключена');
    final response = await client.post(
      endpoint('/organizations/${binding.remoteOrganizationId}/members'),
      headers: await _authorizedHeaders(),
      body: jsonEncode({'username': username, 'role': role}),
    );
    if (response.statusCode != 200) _serverError(response);
    return ServerMember.fromJson(
      Map<String, Object?>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<void> removeMember(int userId) async {
    final binding = await repository.remoteOrganizationBinding();
    if (binding == null) throw StateError('Организация не подключена');
    final response = await client.delete(
      endpoint(
        '/organizations/${binding.remoteOrganizationId}/members/$userId',
      ),
      headers: await _authorizedHeaders(),
    );
    if (response.statusCode != 204) _serverError(response);
  }

  Future<SyncResult> synchronize() async {
    final token = await tokenStore.read();
    if (token == null) throw StateError('Сначала подключитесь к серверу');
    if (!await repository.syncTargetMatches(normalizedServerUrl)) {
      throw StateError(
        'Выбранная организация не связана с этим подключением. '
        'Подключите устройство заново.',
      );
    }
    final headers = await _authorizedHeaders();
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

  Future<Map<String, int>> replaceServerFromPhone() async {
    final snapshot = await repository.fullSyncSnapshot();
    final response = await client.post(
      endpoint('/sync/replace-snapshot'),
      headers: await _authorizedHeaders(),
      body: jsonEncode({
        'confirmation': 'REPLACE_ALL_FROM_PHONE',
        'changes': snapshot,
      }),
    );
    if (response.statusCode != 200) _serverError(response);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return Map<String, int>.from(
      (body['counts'] as Map).map(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      ),
    );
  }
}
