import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.organizationName,
    required this.providers,
    required this.warehouses,
    required this.materials,
    required this.clients,
    required this.connections,
    required this.pendingChanges,
  });

  final String organizationName;
  final int providers;
  final int warehouses;
  final int materials;
  final int clients;
  final int connections;
  final int pendingChanges;
}

class InventoryBalance {
  const InventoryBalance({
    required this.materialId,
    required this.name,
    required this.itemType,
    required this.unitName,
    required this.quantity,
  });

  final String materialId;
  final String name;
  final String itemType;
  final String unitName;
  final double quantity;
}

class LookupItem {
  const LookupItem(this.id, this.name);
  final String id;
  final String name;
}

class ClientListItem {
  const ClientListItem({
    required this.id,
    required this.providerName,
    required this.login,
    required this.contractNumber,
    required this.address,
    required this.phone,
    required this.connections,
  });

  final String id;
  final String providerName;
  final String login;
  final String contractNumber;
  final String address;
  final String? phone;
  final int connections;
}

class MaterialBalance {
  const MaterialBalance({
    required this.materialId,
    required this.name,
    required this.unitName,
    required this.quantity,
  });

  final String materialId;
  final String name;
  final String unitName;
  final double quantity;
}

class ConnectionMaterialInput {
  const ConnectionMaterialInput({
    required this.materialId,
    required this.quantity,
  });

  final String materialId;
  final double quantity;
}

class LocalRepository {
  LocalRepository(this.database);

  final AppDatabase database;
  final Uuid _uuid = const Uuid();

  Future<void> initialize() async {
    final db = await database.instance;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM organizations'),
        ) ??
        0;
    if (count == 0) await _seedLocalWorkspace(db);
  }

  Future<String> get organizationId async {
    final db = await database.instance;
    final rows = await db.query('organizations', limit: 1);
    return rows.single['id']! as String;
  }

  Future<DashboardSummary> dashboardSummary() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final organization = (await db.query(
      'organizations',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [orgId],
    )).single;
    Future<int> count(String table) async =>
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $table WHERE organization_id = ? AND deleted_at IS NULL',
            [orgId],
          ),
        ) ??
        0;
    final pending =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sync_queue WHERE organization_id = ?',
            [orgId],
          ),
        ) ??
        0;
    return DashboardSummary(
      organizationName: organization['name']! as String,
      providers: await count('providers'),
      warehouses: await count('warehouses'),
      materials: await count('materials'),
      clients: await count('clients'),
      connections: await count('connections'),
      pendingChanges: pending,
    );
  }

  Future<List<InventoryBalance>> inventoryBalances() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT material.id, material.name, material.item_type, material.unit_name,
             COALESCE(SUM(transaction_row.quantity), 0) AS quantity
      FROM materials material
      LEFT JOIN inventory_transactions transaction_row
        ON transaction_row.material_id = material.id
       AND transaction_row.deleted_at IS NULL
      WHERE material.organization_id = ?
        AND material.deleted_at IS NULL
      GROUP BY material.id, material.name, material.item_type, material.unit_name
      ORDER BY material.item_type, material.name
    ''',
      [orgId],
    );
    return rows
        .map(
          (row) => InventoryBalance(
            materialId: row['id']! as String,
            name: row['name']! as String,
            itemType: row['item_type']! as String,
            unitName: row['unit_name']! as String,
            quantity: (row['quantity']! as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<LookupItem>> warehouses() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'warehouses',
      columns: ['id', 'name'],
      where: 'organization_id = ? AND deleted_at IS NULL AND is_active = 1',
      whereArgs: [orgId],
      orderBy: 'name',
    );
    return rows
        .map((row) => LookupItem(row['id']! as String, row['name']! as String))
        .toList();
  }

  Future<List<LookupItem>> materials() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'materials',
      columns: ['id', 'name'],
      where: 'organization_id = ? AND deleted_at IS NULL AND is_active = 1',
      whereArgs: [orgId],
      orderBy: 'name',
    );
    return rows
        .map((row) => LookupItem(row['id']! as String, row['name']! as String))
        .toList();
  }

  Future<List<LookupItem>> providers() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'providers',
      columns: ['id', 'name'],
      where: 'organization_id = ? AND deleted_at IS NULL AND is_active = 1',
      whereArgs: [orgId],
      orderBy: 'name',
    );
    return rows
        .map((row) => LookupItem(row['id']! as String, row['name']! as String))
        .toList();
  }

  Future<List<ClientListItem>> clients() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT client.id, provider.name AS provider_name, client.login,
             client.contract_number, client.address, client.phone,
             COUNT(connection.id) AS connection_count
      FROM clients client
      JOIN providers provider ON provider.id = client.provider_id
      LEFT JOIN connections connection
        ON connection.client_id = client.id AND connection.deleted_at IS NULL
      WHERE client.organization_id = ? AND client.deleted_at IS NULL
      GROUP BY client.id, provider.name, client.login, client.contract_number,
               client.address, client.phone
      ORDER BY client.updated_at DESC
      ''',
      [orgId],
    );
    return rows
        .map(
          (row) => ClientListItem(
            id: row['id']! as String,
            providerName: row['provider_name']! as String,
            login: (row['login'] as String?) ?? '',
            contractNumber: (row['contract_number'] as String?) ?? '',
            address: row['address']! as String,
            phone: row['phone'] as String?,
            connections: (row['connection_count']! as num).toInt(),
          ),
        )
        .toList();
  }

  Future<String> addClient({
    required String providerId,
    required String contractNumber,
    required String login,
    required String address,
    String? phone,
  }) async {
    if (contractNumber.trim().isEmpty ||
        login.trim().isEmpty ||
        address.trim().isEmpty) {
      throw ArgumentError('Заполните договор, логин и адрес');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _uuid.v7();
    final row = <String, Object?>{
      'id': id,
      'organization_id': orgId,
      'provider_id': providerId,
      'contract_number': contractNumber.trim(),
      'login': login.trim(),
      'address': address.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      await transaction.insert('clients', row);
      await _enqueue(
        transaction,
        organizationId: orgId,
        entityType: 'client',
        entityId: id,
        operation: 'upsert',
        payload: row,
        now: now,
      );
    });
    return id;
  }

  Future<List<MaterialBalance>> materialBalancesForWarehouse(
    String warehouseId,
  ) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT material.id, material.name, material.unit_name,
             COALESCE(SUM(transaction_row.quantity), 0) AS quantity
      FROM materials material
      LEFT JOIN inventory_transactions transaction_row
        ON transaction_row.material_id = material.id
       AND transaction_row.warehouse_id = ?
       AND transaction_row.deleted_at IS NULL
      WHERE material.organization_id = ? AND material.deleted_at IS NULL
      GROUP BY material.id, material.name, material.unit_name
      ORDER BY material.name
      ''',
      [warehouseId, orgId],
    );
    return rows
        .map(
          (row) => MaterialBalance(
            materialId: row['id']! as String,
            name: row['name']! as String,
            unitName: row['unit_name']! as String,
            quantity: (row['quantity']! as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<String> addConnection({
    required String clientId,
    required String warehouseId,
    required String connectionType,
    required DateTime connectionDate,
    required double price,
    required double officeAmount,
    required double installerAmount,
    required List<ConnectionMaterialInput> materials,
    String? comment,
  }) async {
    if (price < 0 || officeAmount < 0 || installerAmount < 0) {
      throw ArgumentError('Суммы не могут быть отрицательными');
    }
    if (connectionType == 'WITHOUT_MATERIALS' && materials.isNotEmpty) {
      throw ArgumentError(
        'Для подключения без материалов список должен быть пуст',
      );
    }
    if (materials.any((item) => item.quantity <= 0)) {
      throw ArgumentError('Количество материала должно быть больше нуля');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _uuid.v7();
    final connectionRow = <String, Object?>{
      'id': id,
      'organization_id': orgId,
      'client_id': clientId,
      'warehouse_id': warehouseId,
      'connection_type': connectionType,
      'connection_date': connectionDate.toIso8601String().substring(0, 10),
      'price': price,
      'office_amount': officeAmount,
      'installer_amount': installerAmount,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      for (final material in materials) {
        final available =
            Sqflite.firstIntValue(
              await transaction.rawQuery(
                '''
            SELECT CAST(COALESCE(SUM(quantity), 0) * 1000 AS INTEGER)
            FROM inventory_transactions
            WHERE organization_id = ? AND warehouse_id = ?
              AND material_id = ? AND deleted_at IS NULL
            ''',
                [orgId, warehouseId, material.materialId],
              ),
            ) ??
            0;
        if (available < (material.quantity * 1000).round()) {
          throw StateError('Недостаточно материала на выбранном складе');
        }
      }
      await transaction.insert('connections', connectionRow);
      await _enqueue(
        transaction,
        organizationId: orgId,
        entityType: 'connection',
        entityId: id,
        operation: 'upsert',
        payload: connectionRow,
        now: now,
      );
      for (final material in materials) {
        final materialRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'connection_id': id,
          'material_id': material.materialId,
          'quantity': material.quantity,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        final inventoryRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'warehouse_id': warehouseId,
          'material_id': material.materialId,
          'operation_type': 'CONNECTION',
          'quantity': -material.quantity,
          'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
          'occurred_at': connectionDate.toUtc().toIso8601String(),
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('connection_materials', materialRow);
        await transaction.insert('inventory_transactions', inventoryRow);
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: 'connection_material',
          entityId: materialRow['id']! as String,
          operation: 'upsert',
          payload: materialRow,
          now: now,
        );
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: 'inventory_transaction',
          entityId: inventoryRow['id']! as String,
          operation: 'upsert',
          payload: inventoryRow,
          now: now,
        );
      }
    });
    return id;
  }

  Future<void> addReceipt({
    required String warehouseId,
    required String materialId,
    required double quantity,
    String? comment,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Количество должно быть больше нуля');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _uuid.v7();
    final row = {
      'id': id,
      'organization_id': orgId,
      'warehouse_id': warehouseId,
      'material_id': materialId,
      'operation_type': 'RECEIPT',
      'quantity': quantity,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'occurred_at': now,
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      await transaction.insert('inventory_transactions', row);
      await _enqueue(
        transaction,
        organizationId: orgId,
        entityType: 'inventory_transaction',
        entityId: id,
        operation: 'upsert',
        payload: row,
        now: now,
      );
    });
  }

  Future<int> pendingChanges() async {
    final db = await database.instance;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sync_queue'),
        ) ??
        0;
  }

  Future<void> _seedLocalWorkspace(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final orgId = _uuid.v7();
    final ellkoId = _uuid.v7();
    final optimaId = _uuid.v7();
    final entities = <(String, Map<String, Object?>)>[
      (
        'organizations',
        {
          'id': orgId,
          'name': 'Локальная организация',
          'mode': 'local',
          'created_at': now,
          'updated_at': now,
        },
      ),
      (
        'providers',
        {
          'id': ellkoId,
          'organization_id': orgId,
          'name': 'Эллко',
          'created_at': now,
          'updated_at': now,
        },
      ),
      (
        'providers',
        {
          'id': optimaId,
          'organization_id': orgId,
          'name': 'Оптимасеть',
          'created_at': now,
          'updated_at': now,
        },
      ),
      (
        'warehouses',
        {
          'id': _uuid.v7(),
          'organization_id': orgId,
          'provider_id': ellkoId,
          'name': 'Эллко',
          'created_at': now,
          'updated_at': now,
        },
      ),
      (
        'warehouses',
        {
          'id': _uuid.v7(),
          'organization_id': orgId,
          'provider_id': optimaId,
          'name': 'Оптимасеть',
          'created_at': now,
          'updated_at': now,
        },
      ),
      (
        'materials',
        {
          'id': _uuid.v7(),
          'organization_id': orgId,
          'name': 'ONU',
          'item_type': 'EQUIPMENT',
          'unit_name': 'шт.',
          'category': 'Оборудование',
          'created_at': now,
          'updated_at': now,
        },
      ),
      (
        'materials',
        {
          'id': _uuid.v7(),
          'organization_id': orgId,
          'name': 'Кабель оптика',
          'item_type': 'MATERIAL',
          'unit_name': 'м',
          'category': 'Кабель',
          'created_at': now,
          'updated_at': now,
        },
      ),
    ];
    await db.transaction((transaction) async {
      for (final entity in entities) {
        await transaction.insert(entity.$1, entity.$2);
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: entity.$1,
          entityId: entity.$2['id']! as String,
          operation: 'upsert',
          payload: entity.$2,
          now: now,
        );
      }
    });
  }

  Future<void> _enqueue(
    DatabaseExecutor db, {
    required String organizationId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, Object?> payload,
    required String now,
  }) async {
    await db.insert('sync_queue', {
      'id': _uuid.v7(),
      'organization_id': organizationId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
