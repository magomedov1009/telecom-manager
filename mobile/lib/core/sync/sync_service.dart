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

class ServerSubscription {
  const ServerSubscription({
    required this.hostingMode,
    required this.planCode,
    required this.status,
    required this.expiresAt,
    required this.paymentUrl,
    required this.checkoutAvailable,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.canSync,
  });

  final String hostingMode;
  final String planCode;
  final String status;
  final DateTime? expiresAt;
  final String? paymentUrl;
  final bool checkoutAvailable;
  final int? monthlyPrice;
  final int? yearlyPrice;
  final bool canSync;

  factory ServerSubscription.fromJson(Map<String, Object?> json) =>
      ServerSubscription(
        hostingMode: json['hosting_mode']! as String,
        planCode: json['plan_code']! as String,
        status: json['status']! as String,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at']! as String).toLocal(),
        paymentUrl: json['payment_url'] as String?,
        checkoutAvailable: json['checkout_available'] as bool? ?? false,
        monthlyPrice: (json['monthly_price'] as num?)?.toInt(),
        yearlyPrice: (json['yearly_price'] as num?)?.toInt(),
        canSync: json['can_sync']! as bool,
      );
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
    return _storeConnection(body, username: username, password: password);
  }

  Future<ServerConnection> register({
    required String organizationName,
    required String fullName,
    required String username,
    required String password,
    required String deviceName,
  }) async {
    final response = await client.post(
      endpoint('/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'organization_name': organizationName,
        'full_name': fullName,
        'username': username,
        'password': password,
        'device_name': deviceName,
      }),
    );
    if (response.statusCode != 201) _serverError(response);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return _storeConnection(body, username: username, password: password);
  }

  Future<ServerConnection> _storeConnection(
    Map<String, Object?> body, {
    required String username,
    required String password,
  }) async {
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

  Future<ServerSubscription> subscriptionStatus() async {
    final response = await client.get(
      endpoint('/subscription'),
      headers: await _authorizedHeaders(),
    );
    if (response.statusCode != 200) _serverError(response);
    return ServerSubscription.fromJson(
      Map<String, Object?>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<Uri> createCheckout(String planCode) async {
    final response = await client.post(
      endpoint('/subscription/checkout'),
      headers: await _authorizedHeaders(),
      body: jsonEncode({'plan_code': planCode}),
    );
    if (response.statusCode != 200) _serverError(response);
    final body = Map<String, Object?>.from(jsonDecode(response.body) as Map);
    final url = Uri.tryParse(body['checkout_url']?.toString() ?? '');
    if (url == null || !url.hasScheme) {
      throw StateError('Сервер вернул неверную ссылку на оплату');
    }
    return url;
  }

  Future<void> deleteCloudAccount() async {
    final response = await client.delete(
      endpoint('/account'),
      headers: await _authorizedHeaders(),
      body: jsonEncode({'confirmation': 'DELETE_MY_CLOUD_ACCOUNT'}),
    );
    if (response.statusCode != 204) _serverError(response);
    await tokenStore.clear();
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
    for (var pushAttempt = 0; pushAttempt < 2; pushAttempt++) {
      final queue = await repository.syncQueue(limit: 500);
      if (queue.isEmpty) break;
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
        _serverError(response);
      }
      final results = jsonDecode(response.body) as List;
      var shouldRetry = false;
      for (final raw in results) {
        final result = raw as Map<String, Object?>;
        final type = result['entity_type']! as String;
        final id = result['entity_id']! as String;
        if (result['status'] == 'conflict') {
          if (pushAttempt == 0) {
            await repository.rebaseSyncConflict(
              type,
              id,
              (result['server_version']! as num).toInt(),
            );
            shouldRetry = true;
          } else {
            conflicts++;
            await repository.markSyncError(type, id, 'Конфликт версии');
          }
        } else {
          sent++;
          await repository.acknowledgeSync(type, id);
        }
      }
      if (!shouldRetry) break;
    }
    var cursor = await repository.syncCursor();
    var hasMore = true;
    while (hasMore) {
      final response = await client.get(
        endpoint('/sync/pull', {'cursor': '$cursor', 'limit': '200'}),
        headers: headers,
      );
      if (response.statusCode != 200) {
        _serverError(response);
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

  Future<Map<String, int>> replaceServerFromPhone({
    required int ownerUserId,
  }) async {
    final snapshot = await repository.fullSyncSnapshot();
    final response = await client.post(
      endpoint('/sync/replace-snapshot'),
      headers: await _authorizedHeaders(),
      body: jsonEncode({
        'confirmation': 'REPLACE_ALL_FROM_PHONE',
        'owner_user_id': ownerUserId,
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

  Future<Map<String, Object?>> reassignSnapshotOwner(int ownerUserId) async {
    final response = await client.post(
      endpoint('/sync/reassign-snapshot-owner'),
      headers: await _authorizedHeaders(),
      body: jsonEncode({'owner_user_id': ownerUserId}),
    );
    if (response.statusCode != 200) _serverError(response);
    return Map<String, Object?>.from(jsonDecode(response.body) as Map);
  }
}
