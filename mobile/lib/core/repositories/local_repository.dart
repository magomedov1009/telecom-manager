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

class InventoryHistoryItem {
  const InventoryHistoryItem({
    required this.operationType,
    required this.warehouseName,
    required this.materialName,
    required this.quantity,
    required this.occurredAt,
    required this.comment,
  });
  final String operationType;
  final String warehouseName;
  final String materialName;
  final double quantity;
  final DateTime occurredAt;
  final String? comment;
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

class MaterialSettlement {
  const MaterialSettlement({
    required this.creditorName,
    required this.debtorName,
    required this.materialName,
    required this.unitName,
    required this.quantity,
  });

  final String creditorName;
  final String debtorName;
  final String materialName;
  final String unitName;
  final double quantity;
}

class FinanceSummary {
  const FinanceSummary({
    required this.customerReceived,
    required this.officeAccrued,
    required this.paidToOffice,
    required this.paidFromOffice,
    required this.balance,
    required this.availableCash,
  });

  final double customerReceived;
  final double officeAccrued;
  final double paidToOffice;
  final double paidFromOffice;
  final double balance;
  final double availableCash;

  double get officeOwesMe => balance > 0 ? balance : 0;
  double get iOweOffice => balance < 0 ? -balance : 0;
}

class FinanceJournalItem {
  const FinanceJournalItem({
    required this.type,
    required this.providerName,
    required this.amount,
    required this.comment,
    required this.occurredAt,
  });

  final String type;
  final String? providerName;
  final double amount;
  final String? comment;
  final DateTime occurredAt;
}

class ExpenseItem {
  const ExpenseItem({
    required this.category,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.providerName,
    required this.expenseDate,
  });

  final String category;
  final String description;
  final double amount;
  final String paidBy;
  final String providerName;
  final DateTime expenseDate;
}

class ExtraWorkItem {
  const ExtraWorkItem({
    required this.typeName,
    required this.providerName,
    required this.amount,
    required this.workDate,
    required this.comment,
  });

  final String typeName;
  final String providerName;
  final double amount;
  final DateTime workDate;
  final String? comment;
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

  Future<List<LookupItem>> extraWorkTypes() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'extra_work_types',
      columns: ['id', 'name'],
      where: 'organization_id = ? AND deleted_at IS NULL AND is_active = 1',
      whereArgs: [orgId],
      orderBy: 'name',
    );
    return rows
        .map((row) => LookupItem(row['id']! as String, row['name']! as String))
        .toList();
  }

  Future<void> addProvider(String name) async {
    await _addCatalogRow('providers', {
      'name': _requiredName(name),
      'is_active': 1,
    }, 'provider');
  }

  Future<void> addWarehouse({
    required String name,
    required String providerId,
  }) async {
    await _addCatalogRow('warehouses', {
      'name': _requiredName(name),
      'provider_id': providerId,
      'is_active': 1,
    }, 'warehouse');
  }

  Future<void> addMaterial({
    required String name,
    required String itemType,
    required String unitName,
    String? category,
  }) async {
    if (!{'MATERIAL', 'EQUIPMENT'}.contains(itemType)) {
      throw ArgumentError('Неизвестный тип позиции');
    }
    await _addCatalogRow('materials', {
      'name': _requiredName(name),
      'item_type': itemType,
      'unit_name': _requiredName(unitName),
      'category': category?.trim().isEmpty == true ? null : category?.trim(),
      'is_active': 1,
    }, 'material');
  }

  Future<void> addExtraWorkType({
    required String name,
    double defaultPrice = 0,
    bool requiresMaterials = false,
  }) async {
    if (defaultPrice < 0) {
      throw ArgumentError('Цена не может быть отрицательной');
    }
    await _addCatalogRow('extra_work_types', {
      'name': _requiredName(name),
      'default_price': defaultPrice,
      'requires_materials': requiresMaterials ? 1 : 0,
      'is_active': 1,
    }, 'extra_work_type');
  }

  Future<void> _addCatalogRow(
    String table,
    Map<String, Object?> values,
    String entityType,
  ) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    final row = <String, Object?>{
      'id': _uuid.v7(),
      'organization_id': orgId,
      ...values,
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      try {
        await transaction.insert(table, row);
      } on DatabaseException catch (error) {
        if (error.isUniqueConstraintError()) {
          throw ArgumentError('Запись с таким названием уже существует');
        }
        rethrow;
      }
      await _queueRow(transaction, orgId, entityType, row, now);
    });
  }

  String _requiredName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) throw ArgumentError('Название обязательно');
    return clean;
  }

  Future<List<InventoryHistoryItem>> inventoryHistory() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT movement.operation_type, movement.quantity, movement.occurred_at,
             movement.comment, warehouse.name warehouse_name,
             material.name material_name
      FROM inventory_transactions movement
      JOIN warehouses warehouse ON warehouse.id = movement.warehouse_id
      JOIN materials material ON material.id = movement.material_id
      WHERE movement.organization_id = ? AND movement.deleted_at IS NULL
      ORDER BY movement.occurred_at DESC, movement.created_at DESC
      ''',
      [orgId],
    );
    return rows
        .map(
          (row) => InventoryHistoryItem(
            operationType: row['operation_type']! as String,
            warehouseName: row['warehouse_name']! as String,
            materialName: row['material_name']! as String,
            quantity: (row['quantity']! as num).toDouble(),
            occurredAt: DateTime.parse(row['occurred_at']! as String),
            comment: row['comment'] as String?,
          ),
        )
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
      final client = (await transaction.query(
        'clients',
        columns: ['provider_id'],
        where: 'id = ? AND organization_id = ?',
        whereArgs: [clientId, orgId],
        limit: 1,
      )).single;
      final clientProviderId = client['provider_id']! as String;
      for (final material in materials) {
        final available = await _balanceInTransaction(
          transaction,
          organizationId: orgId,
          warehouseId: warehouseId,
          materialId: material.materialId,
        );
        if (available + 0.000001 < material.quantity) {
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
      for (final accrual in [
        (
          amount: installerAmount,
          to: 'INSTALLER',
          comment: 'Начисление монтажнику',
        ),
        (amount: officeAmount, to: 'OFFICE', comment: 'Начисление офису'),
      ]) {
        if (accrual.amount <= 0) continue;
        final financeRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'provider_id': clientProviderId,
          'connection_id': id,
          'transaction_type': 'CONNECTION',
          'accrual_to': accrual.to,
          'amount': accrual.amount,
          'comment': accrual.comment,
          'occurred_at': connectionDate.toUtc().toIso8601String(),
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('finance_transactions', financeRow);
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: 'finance_transaction',
          entityId: financeRow['id']! as String,
          operation: 'upsert',
          payload: financeRow,
          now: now,
        );
      }
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
          'provider_id': clientProviderId,
          'material_id': material.materialId,
          'connection_id': id,
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

  Future<void> addTransfer({
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required String materialId,
    required double quantity,
    String? comment,
  }) async {
    if (sourceWarehouseId == destinationWarehouseId) {
      throw ArgumentError('Выберите разные склады');
    }
    if (quantity <= 0) {
      throw ArgumentError('Количество должно быть больше нуля');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final available = await _balanceInTransaction(
        transaction,
        organizationId: orgId,
        warehouseId: sourceWarehouseId,
        materialId: materialId,
      );
      if (available + 0.000001 < quantity) {
        throw StateError('Недостаточно материала на складе отправителя');
      }
      final destination = (await transaction.query(
        'warehouses',
        columns: ['provider_id'],
        where: 'id = ? AND organization_id = ?',
        whereArgs: [destinationWarehouseId, orgId],
        limit: 1,
      )).single;
      final destinationProviderId = destination['provider_id'] as String?;
      final cleanComment = comment?.trim().isEmpty == true
          ? null
          : comment?.trim();
      for (final movement in [
        (
          warehouseId: sourceWarehouseId,
          counterpartId: destinationWarehouseId,
          type: 'TRANSFER_OUT',
          amount: -quantity,
        ),
        (
          warehouseId: destinationWarehouseId,
          counterpartId: sourceWarehouseId,
          type: 'TRANSFER_IN',
          amount: quantity,
        ),
      ]) {
        final row = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'warehouse_id': movement.warehouseId,
          'counterpart_warehouse_id': movement.counterpartId,
          'provider_id': destinationProviderId,
          'material_id': materialId,
          'operation_type': movement.type,
          'quantity': movement.amount,
          'comment': cleanComment,
          'occurred_at': now,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('inventory_transactions', row);
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: 'inventory_transaction',
          entityId: row['id']! as String,
          operation: 'upsert',
          payload: row,
          now: now,
        );
      }
    });
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

  Future<List<MaterialSettlement>> materialSettlements() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT creditor.id AS creditor_id, creditor.name AS creditor_name,
             debtor.id AS debtor_id, debtor.name AS debtor_name,
             material.id AS material_id, material.name AS material_name,
             material.unit_name,
             SUM(-transaction_row.quantity) AS quantity
      FROM inventory_transactions transaction_row
      JOIN warehouses source ON source.id = transaction_row.warehouse_id
      JOIN providers creditor ON creditor.id = source.provider_id
      JOIN providers debtor ON debtor.id = transaction_row.provider_id
      JOIN materials material ON material.id = transaction_row.material_id
      WHERE transaction_row.organization_id = ?
        AND transaction_row.deleted_at IS NULL
        AND transaction_row.operation_type IN ('CONNECTION', 'TRANSFER_OUT')
        AND transaction_row.quantity < 0
        AND creditor.id <> debtor.id
      GROUP BY creditor.id, creditor.name, debtor.id, debtor.name,
               material.id, material.name, material.unit_name
      ''',
      [orgId],
    );
    final net = <String, ({double amount, Map<String, Object?> row})>{};
    for (final row in rows) {
      final creditorId = row['creditor_id']! as String;
      final debtorId = row['debtor_id']! as String;
      final materialId = row['material_id']! as String;
      final forward = creditorId.compareTo(debtorId) < 0;
      final first = forward ? creditorId : debtorId;
      final second = forward ? debtorId : creditorId;
      final key = '$first|$second|$materialId';
      final signed = (row['quantity']! as num).toDouble() * (forward ? 1 : -1);
      final previous = net[key];
      net[key] = (
        amount: (previous?.amount ?? 0) + signed,
        row: forward
            ? row
            : {
                ...row,
                'creditor_name': row['debtor_name'],
                'debtor_name': row['creditor_name'],
              },
      );
    }
    return net.values.where((item) => item.amount.abs() > 0.000001).map((item) {
      final positive = item.amount > 0;
      return MaterialSettlement(
        creditorName:
            (positive ? item.row['creditor_name'] : item.row['debtor_name'])
                as String,
        debtorName:
            (positive ? item.row['debtor_name'] : item.row['creditor_name'])
                as String,
        materialName: item.row['material_name']! as String,
        unitName: item.row['unit_name']! as String,
        quantity: item.amount.abs(),
      );
    }).toList()..sort((a, b) => a.debtorName.compareTo(b.debtorName));
  }

  Future<FinanceSummary> financeSummary({String? providerId}) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final providerClause = providerId == null ? '' : ' AND provider_id = ?';
    final arguments = <Object?>[orgId, ?providerId];
    Future<double> sum(String condition) async {
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM($condition), 0) AS amount
        FROM finance_transactions
        WHERE organization_id = ? AND deleted_at IS NULL$providerClause
        ''', arguments);
      return (rows.single['amount']! as num).toDouble();
    }

    final customerReceived = await sum(
      "CASE WHEN transaction_type = 'CONNECTION' AND amount > 0 THEN amount ELSE 0 END",
    );
    final officeAccrued = await sum(
      "CASE WHEN transaction_type = 'CONNECTION' AND accrual_to = 'OFFICE' AND amount > 0 THEN amount ELSE 0 END",
    );
    final paidFromOffice = await sum(
      "CASE WHEN transaction_type = 'PAYMENT_FROM_OFFICE' THEN amount ELSE 0 END",
    );
    final paidToOffice = await sum(
      "CASE WHEN transaction_type = 'PAYMENT_TO_OFFICE' THEN ABS(amount) ELSE 0 END",
    );
    final adjustments = await sum(
      "CASE WHEN transaction_type = 'ADJUSTMENT' THEN amount ELSE 0 END",
    );
    final extraWorkInstaller = await sum(
      "CASE WHEN transaction_type = 'EXTRA_WORK' AND accrual_to = 'INSTALLER' AND amount > 0 THEN amount ELSE 0 END",
    );
    final expenseRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS amount FROM expenses
      WHERE organization_id = ? AND paid_by = 'INSTALLER'
        AND deleted_at IS NULL$providerClause
      ''', arguments);
    final installerExpenses = (expenseRows.single['amount']! as num).toDouble();
    final balance =
        extraWorkInstaller +
        installerExpenses -
        paidFromOffice +
        adjustments -
        officeAccrued +
        paidToOffice;
    return FinanceSummary(
      customerReceived: customerReceived,
      officeAccrued: officeAccrued,
      paidToOffice: paidToOffice,
      paidFromOffice: paidFromOffice,
      balance: balance,
      availableCash:
          customerReceived + paidFromOffice - paidToOffice - installerExpenses,
    );
  }

  Future<List<FinanceJournalItem>> financeJournal({String? providerId}) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT transaction_row.transaction_type, transaction_row.amount,
             transaction_row.comment, transaction_row.occurred_at,
             provider.name AS provider_name
      FROM finance_transactions transaction_row
      LEFT JOIN providers provider ON provider.id = transaction_row.provider_id
      WHERE transaction_row.organization_id = ?
        AND transaction_row.deleted_at IS NULL
        ${providerId == null ? '' : 'AND transaction_row.provider_id = ?'}
      ORDER BY transaction_row.occurred_at DESC, transaction_row.created_at DESC
      ''',
      [orgId, ?providerId],
    );
    return rows
        .map(
          (row) => FinanceJournalItem(
            type: row['transaction_type']! as String,
            providerName: row['provider_name'] as String?,
            amount: (row['amount']! as num).toDouble(),
            comment: row['comment'] as String?,
            occurredAt: DateTime.parse(row['occurred_at']! as String),
          ),
        )
        .toList();
  }

  Future<void> addManualFinanceTransaction({
    required String transactionType,
    required double amount,
    String? providerId,
    String? comment,
  }) async {
    const allowed = {'PAYMENT_TO_OFFICE', 'PAYMENT_FROM_OFFICE', 'ADJUSTMENT'};
    if (!allowed.contains(transactionType)) {
      throw ArgumentError('Неизвестный тип финансовой операции');
    }
    if (amount <= 0) {
      throw ArgumentError('Сумма должна быть больше нуля');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    final signedAmount = transactionType == 'PAYMENT_TO_OFFICE'
        ? -amount
        : amount;
    final row = <String, Object?>{
      'id': _uuid.v7(),
      'organization_id': orgId,
      'provider_id': providerId,
      'transaction_type': transactionType,
      'amount': signedAmount,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'occurred_at': now,
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      await transaction.insert('finance_transactions', row);
      await _enqueue(
        transaction,
        organizationId: orgId,
        entityType: 'finance_transaction',
        entityId: row['id']! as String,
        operation: 'upsert',
        payload: row,
        now: now,
      );
    });
  }

  Future<void> addExpense({
    required String providerId,
    required String category,
    required String description,
    required double amount,
    required String paidBy,
    required DateTime expenseDate,
    String? comment,
  }) async {
    if (amount <= 0) throw ArgumentError('Сумма должна быть больше нуля');
    if (description.trim().isEmpty) {
      throw ArgumentError('Описание обязательно');
    }
    if (!{'INSTALLER', 'OFFICE'}.contains(paidBy)) {
      throw ArgumentError('Укажите, кто оплатил расход');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    final expenseId = _uuid.v7();
    final expenseRow = <String, Object?>{
      'id': expenseId,
      'organization_id': orgId,
      'provider_id': providerId,
      'category': category,
      'description': description.trim(),
      'amount': amount,
      'paid_by': paidBy,
      'expense_date': expenseDate.toIso8601String().substring(0, 10),
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    final financeRow = <String, Object?>{
      'id': _uuid.v7(),
      'organization_id': orgId,
      'provider_id': providerId,
      'expense_id': expenseId,
      'transaction_type': 'EXPENSE',
      'amount': -amount,
      'comment': description.trim(),
      'occurred_at': expenseDate.toUtc().toIso8601String(),
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      await transaction.insert('expenses', expenseRow);
      await transaction.insert('finance_transactions', financeRow);
      for (final item in [
        ('expense', expenseRow),
        ('finance_transaction', financeRow),
      ]) {
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: item.$1,
          entityId: item.$2['id']! as String,
          operation: 'upsert',
          payload: item.$2,
          now: now,
        );
      }
    });
  }

  Future<void> addExtraWork({
    required String providerId,
    required String workTypeId,
    required DateTime workDate,
    required double amount,
    String? warehouseId,
    List<ConnectionMaterialInput> materials = const [],
    String? comment,
  }) async {
    if (amount < 0) {
      throw ArgumentError('Стоимость не может быть отрицательной');
    }
    if (materials.any((item) => item.quantity <= 0)) {
      throw ArgumentError('Количество материала должно быть больше нуля');
    }
    if (materials.isNotEmpty && warehouseId == null) {
      throw ArgumentError('Выберите склад для списания');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    final workId = _uuid.v7();
    final workRow = <String, Object?>{
      'id': workId,
      'organization_id': orgId,
      'provider_id': providerId,
      'work_type_id': workTypeId,
      'warehouse_id': warehouseId,
      'work_date': workDate.toIso8601String().substring(0, 10),
      'amount': amount,
      'office_amount': 0,
      'installer_amount': amount,
      'status': 'completed',
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      for (final material in materials) {
        final available = await _balanceInTransaction(
          transaction,
          organizationId: orgId,
          warehouseId: warehouseId!,
          materialId: material.materialId,
        );
        if (available + 0.000001 < material.quantity) {
          throw StateError('Недостаточно материала на выбранном складе');
        }
      }
      await transaction.insert('extra_works', workRow);
      await _queueRow(transaction, orgId, 'extra_work', workRow, now);
      for (final material in materials) {
        final usageRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'extra_work_id': workId,
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
          'provider_id': providerId,
          'material_id': material.materialId,
          'operation_type': 'WRITE_OFF',
          'quantity': -material.quantity,
          'comment': 'Допработа',
          'occurred_at': workDate.toUtc().toIso8601String(),
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('extra_work_materials', usageRow);
        await transaction.insert('inventory_transactions', inventoryRow);
        await _queueRow(
          transaction,
          orgId,
          'extra_work_material',
          usageRow,
          now,
        );
        await _queueRow(
          transaction,
          orgId,
          'inventory_transaction',
          inventoryRow,
          now,
        );
      }
      if (amount > 0) {
        final financeRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'provider_id': providerId,
          'extra_work_id': workId,
          'transaction_type': 'EXTRA_WORK',
          'accrual_to': 'INSTALLER',
          'amount': amount,
          'comment': 'Допработа: офис должен монтажнику',
          'occurred_at': workDate.toUtc().toIso8601String(),
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('finance_transactions', financeRow);
        await _queueRow(
          transaction,
          orgId,
          'finance_transaction',
          financeRow,
          now,
        );
      }
    });
  }

  Future<List<ExtraWorkItem>> extraWorks() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT work.amount, work.work_date, work.comment,
             type.name type_name, provider.name provider_name
      FROM extra_works work
      JOIN extra_work_types type ON type.id = work.work_type_id
      JOIN providers provider ON provider.id = work.provider_id
      WHERE work.organization_id = ? AND work.deleted_at IS NULL
      ORDER BY work.work_date DESC, work.created_at DESC
      ''',
      [orgId],
    );
    return rows
        .map(
          (row) => ExtraWorkItem(
            typeName: row['type_name']! as String,
            providerName: row['provider_name']! as String,
            amount: (row['amount']! as num).toDouble(),
            workDate: DateTime.parse(row['work_date']! as String),
            comment: row['comment'] as String?,
          ),
        )
        .toList();
  }

  Future<List<ExpenseItem>> expenses() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT expense.category, expense.description, expense.amount,
             expense.paid_by, expense.expense_date, provider.name provider_name
      FROM expenses expense
      JOIN providers provider ON provider.id = expense.provider_id
      WHERE expense.organization_id = ? AND expense.deleted_at IS NULL
      ORDER BY expense.expense_date DESC, expense.created_at DESC
      ''',
      [orgId],
    );
    return rows
        .map(
          (row) => ExpenseItem(
            category: row['category']! as String,
            description: row['description']! as String,
            amount: (row['amount']! as num).toDouble(),
            paidBy: row['paid_by']! as String,
            providerName: row['provider_name']! as String,
            expenseDate: DateTime.parse(row['expense_date']! as String),
          ),
        )
        .toList();
  }

  Future<double> _balanceInTransaction(
    DatabaseExecutor transaction, {
    required String organizationId,
    required String warehouseId,
    required String materialId,
  }) async {
    final rows = await transaction.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS quantity
      FROM inventory_transactions
      WHERE organization_id = ? AND warehouse_id = ?
        AND material_id = ? AND deleted_at IS NULL
      ''',
      [organizationId, warehouseId, materialId],
    );
    return (rows.single['quantity']! as num).toDouble();
  }

  Future<void> _queueRow(
    DatabaseExecutor transaction,
    String organizationId,
    String entityType,
    Map<String, Object?> row,
    String now,
  ) {
    return _enqueue(
      transaction,
      organizationId: organizationId,
      entityType: entityType,
      entityId: row['id']! as String,
      operation: 'upsert',
      payload: row,
      now: now,
    );
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
      (
        'extra_work_types',
        {
          'id': _uuid.v7(),
          'organization_id': orgId,
          'name': 'Ремонт линии',
          'default_price': 0,
          'requires_materials': 1,
          'created_at': now,
          'updated_at': now,
        },
      ),
      (
        'extra_work_types',
        {
          'id': _uuid.v7(),
          'organization_id': orgId,
          'name': 'Настройка оборудования',
          'default_price': 0,
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
