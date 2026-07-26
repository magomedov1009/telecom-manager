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
    required this.pendingChanges,
  });

  final String organizationName;
  final int providers;
  final int warehouses;
  final int materials;
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
