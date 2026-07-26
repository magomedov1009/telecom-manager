import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';

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

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.isActive,
    this.description,
    this.defaultPrice,
    this.defaultOfficeAmount,
    this.requiresMaterials = false,
    this.requiresEquipment = false,
  });

  final String id;
  final String name;
  final bool isActive;
  final String? description;
  final double? defaultPrice;
  final double? defaultOfficeAmount;
  final bool requiresMaterials;
  final bool requiresEquipment;
}

class UserItem {
  const UserItem({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
  });
  final String id;
  final String username;
  final String fullName;
  final String role;
  final bool isActive;
}

class ClientListItem {
  const ClientListItem({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.login,
    required this.contractNumber,
    required this.address,
    required this.phone,
    required this.comment,
    required this.connections,
  });

  final String id;
  final String providerId;
  final String providerName;
  final String login;
  final String contractNumber;
  final String address;
  final String? phone;
  final String? comment;
  final int connections;
}

class ConnectionListItem {
  const ConnectionListItem({
    required this.id,
    required this.clientLogin,
    required this.address,
    required this.providerName,
    required this.connectionType,
    required this.connectionDate,
    required this.price,
  });
  final String id;
  final String clientLogin;
  final String address;
  final String providerName;
  final String connectionType;
  final DateTime connectionDate;
  final double price;
}

class ConnectionEditData {
  const ConnectionEditData({
    required this.warehouseId,
    required this.connectionType,
    required this.connectionDate,
    required this.price,
    required this.officeAmount,
    required this.installerAmount,
    required this.comment,
    required this.materials,
  });
  final String warehouseId;
  final String connectionType;
  final DateTime connectionDate;
  final double price;
  final double officeAmount;
  final double installerAmount;
  final String? comment;
  final Map<String, double> materials;
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
    required this.installerAccrued,
    required this.officeAccrued,
    required this.extraWorkIncome,
    required this.incomeTotal,
    required this.expensesTotal,
    required this.profit,
    required this.paidToOffice,
    required this.paidFromOffice,
    required this.balance,
    required this.availableCash,
  });

  final double customerReceived;
  final double installerAccrued;
  final double officeAccrued;
  final double extraWorkIncome;
  final double incomeTotal;
  final double expensesTotal;
  final double profit;
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
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.providerName,
    required this.expenseDate,
  });

  final String id;
  final String category;
  final String description;
  final double amount;
  final String paidBy;
  final String providerName;
  final DateTime expenseDate;
}

class ExtraWorkItem {
  const ExtraWorkItem({
    required this.id,
    required this.typeName,
    required this.providerName,
    required this.amount,
    required this.workDate,
    required this.comment,
  });

  final String id;
  final String typeName;
  final String providerName;
  final double amount;
  final DateTime workDate;
  final String? comment;
}

class ExtraWorkEditData {
  const ExtraWorkEditData({
    required this.providerId,
    required this.workTypeId,
    required this.workDate,
    required this.amount,
    required this.warehouseId,
    required this.materials,
    required this.comment,
  });

  final String providerId;
  final String workTypeId;
  final DateTime workDate;
  final double amount;
  final String? warehouseId;
  final Map<String, double> materials;
  final String? comment;
}

class ExpenseEditData {
  const ExpenseEditData({
    required this.providerId,
    required this.category,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.expenseDate,
    required this.comment,
  });

  final String providerId;
  final String category;
  final String description;
  final double amount;
  final String paidBy;
  final DateTime expenseDate;
  final String? comment;
}

class ReportSummary {
  const ReportSummary({
    required this.connections,
    required this.connectionAmount,
    required this.extraWorks,
    required this.extraWorkAmount,
    required this.expenses,
    required this.materialSpent,
  });
  final int connections;
  final double connectionAmount;
  final int extraWorks;
  final double extraWorkAmount;
  final double expenses;
  final double materialSpent;
  double get income => connectionAmount + extraWorkAmount;
  double get profit => income - expenses;
}

class ReportDetailItem {
  const ReportDetailItem({
    required this.title,
    required this.subtitle,
    required this.value,
  });
  final String title;
  final String subtitle;
  final double value;
}

class SyncQueueItem {
  const SyncQueueItem({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.version,
    required this.payload,
  });
  final String entityType;
  final String entityId;
  final String operation;
  final int version;
  final Map<String, Object?> payload;
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
    final orgId = await organizationId;
    await db.insert('app_settings', {
      'key': 'current_organization_id',
      'value': orgId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final users =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM users WHERE organization_id = ?',
            [orgId],
          ),
        ) ??
        0;
    if (users == 0) {
      await _insertUser(
        db,
        organizationId: orgId,
        username: 'admin',
        fullName: 'Администратор',
        role: 'admin',
        password: '0000',
      );
    }
    final withoutPassword = await db.query(
      'users',
      columns: ['id'],
      where: 'organization_id = ? AND password_hash IS NULL',
      whereArgs: [orgId],
    );
    for (final user in withoutPassword) {
      await _setPassword(db, user['id']! as String, '0000');
    }
  }

  Future<String> get organizationId async {
    final db = await database.instance;
    final setting = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['current_organization_id'],
      limit: 1,
    );
    if (setting.isNotEmpty) return setting.single['value']! as String;
    final rows = await db.query('organizations', limit: 1);
    return rows.single['id']! as String;
  }

  Future<List<LookupItem>> organizations() async {
    final db = await database.instance;
    final rows = await db.query(
      'organizations',
      columns: ['id', 'name'],
      where: 'deleted_at IS NULL',
      orderBy: 'name',
    );
    return rows
        .map((row) => LookupItem(row['id']! as String, row['name']! as String))
        .toList();
  }

  Future<void> switchOrganization(String id) async {
    final db = await database.instance;
    final exists =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM organizations WHERE id = ? AND deleted_at IS NULL',
            [id],
          ),
        ) ??
        0;
    if (exists != 1) throw ArgumentError('Организация не найдена');
    await db.insert('app_settings', {
      'key': 'current_organization_id',
      'value': id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> addOrganization(String name) async {
    final clean = _requiredName(name);
    final db = await database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _uuid.v7();
    final row = <String, Object?>{
      'id': id,
      'name': clean,
      'mode': 'local',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.transaction((transaction) async {
      await transaction.insert('organizations', row);
      await _queueRow(transaction, id, 'organization', row, now);
      await _insertUser(
        transaction,
        organizationId: id,
        username: 'admin',
        fullName: 'Администратор',
        role: 'admin',
        password: '0000',
      );
    });
    await switchOrganization(id);
    return id;
  }

  Future<List<UserItem>> users() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'users',
      where: 'organization_id = ? AND deleted_at IS NULL',
      whereArgs: [orgId],
      orderBy: 'full_name',
    );
    return rows
        .map(
          (row) => UserItem(
            id: row['id']! as String,
            username: row['username']! as String,
            fullName: row['full_name']! as String,
            role: row['role']! as String,
            isActive: row['is_active'] == 1,
          ),
        )
        .toList();
  }

  Future<void> addUser({
    required String username,
    required String fullName,
    required String role,
    required String password,
  }) async {
    if (!{'admin', 'manager', 'installer'}.contains(role)) {
      throw ArgumentError('Неизвестная роль');
    }
    final db = await database.instance;
    await _insertUser(
      db,
      organizationId: await organizationId,
      username: _requiredName(username),
      fullName: _requiredName(fullName),
      role: role,
      password: password,
    );
  }

  Future<void> _insertUser(
    DatabaseExecutor db, {
    required String organizationId,
    required String username,
    required String fullName,
    required String role,
    required String password,
  }) async {
    if (password.length < 4) {
      throw ArgumentError('Пароль должен содержать минимум 4 символа');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final row = <String, Object?>{
      'id': _uuid.v7(),
      'organization_id': organizationId,
      'username': username,
      'full_name': fullName,
      'role': role,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'sync_state': 'pending',
    };
    await db.insert('users', row);
    await _setPassword(db, row['id']! as String, password);
    final stored = (await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [row['id']],
      limit: 1,
    )).single;
    row['password_hash'] = stored['password_hash'];
    row['password_salt'] = stored['password_salt'];
    await _queueRow(db, organizationId, 'user', row, now);
  }

  Future<void> _setPassword(
    DatabaseExecutor db,
    String userId,
    String password,
  ) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    await db.update(
      'users',
      {
        'password_hash': base64Encode(await key.extractBytes()),
        'password_salt': base64Encode(salt),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<UserItem?> authenticate(String username, String password) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'users',
      where:
          'organization_id = ? AND username = ? AND is_active = 1 AND deleted_at IS NULL',
      whereArgs: [orgId, username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final salt = base64Decode(row['password_salt']! as String);
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    if (base64Encode(await key.extractBytes()) != row['password_hash']) {
      return null;
    }
    await db.insert('app_settings', {
      'key': 'current_user_id',
      'value': row['id']! as String,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return UserItem(
      id: row['id']! as String,
      username: row['username']! as String,
      fullName: row['full_name']! as String,
      role: row['role']! as String,
      isActive: true,
    );
  }

  Future<UserItem?> currentUser() async {
    final db = await database.instance;
    final setting = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['current_user_id'],
      limit: 1,
    );
    if (setting.isEmpty) return null;
    final rows = await db.query(
      'users',
      where: 'id = ? AND organization_id = ? AND is_active = 1',
      whereArgs: [setting.single['value'], await organizationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return UserItem(
      id: row['id']! as String,
      username: row['username']! as String,
      fullName: row['full_name']! as String,
      role: row['role']! as String,
      isActive: true,
    );
  }

  Future<void> logout() async {
    final db = await database.instance;
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['current_user_id'],
    );
  }

  Future<void> changeUserPassword(String userId, String password) async {
    if (password.length < 4) {
      throw ArgumentError('Пароль должен содержать минимум 4 символа');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final belongs =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM users WHERE id = ? AND organization_id = ?',
            [userId, orgId],
          ),
        ) ??
        0;
    if (belongs != 1) throw ArgumentError('Пользователь не найден');
    await _setPassword(db, userId, password);
    final row = (await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    )).single;
    await _enqueue(
      db,
      organizationId: orgId,
      entityType: 'user',
      entityId: userId,
      operation: 'upsert',
      payload: row,
      now: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> toggleUser(String userId) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final current = await currentUser();
    if (current?.id == userId) {
      throw ArgumentError('Нельзя отключить текущего пользователя');
    }
    final rows = await db.query(
      'users',
      where: 'id = ? AND organization_id = ?',
      whereArgs: [userId, orgId],
      limit: 1,
    );
    if (rows.isEmpty) throw ArgumentError('Пользователь не найден');
    final now = DateTime.now().toUtc().toIso8601String();
    final active = rows.single['is_active'] == 1 ? 0 : 1;
    await db.update(
      'users',
      {'is_active': active, 'updated_at': now, 'sync_state': 'pending'},
      where: 'id = ?',
      whereArgs: [userId],
    );
    final row = (await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    )).single;
    await _enqueue(
      db,
      organizationId: orgId,
      entityType: 'user',
      entityId: userId,
      operation: 'upsert',
      payload: row,
      now: now,
    );
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

  Future<List<InventoryBalance>> inventoryBalances({
    String? warehouseId,
    String? providerId,
  }) async {
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
       ${warehouseId == null ? '' : 'AND transaction_row.warehouse_id = ?'}
       ${providerId == null ? '' : '''
       AND COALESCE(
         transaction_row.provider_id,
         (SELECT owner.provider_id FROM warehouses owner
          WHERE owner.id = transaction_row.warehouse_id)
       ) = ?'''}
      WHERE material.organization_id = ?
        AND material.deleted_at IS NULL
      GROUP BY material.id, material.name, material.item_type, material.unit_name
      ORDER BY material.item_type, material.name
    ''',
      [?warehouseId, ?providerId, orgId],
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

  Future<List<CatalogItem>> providerCatalog() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'providers',
      where: 'organization_id = ? AND deleted_at IS NULL',
      whereArgs: [orgId],
      orderBy: 'name',
    );
    return rows
        .map(
          (row) => CatalogItem(
            id: row['id']! as String,
            name: row['name']! as String,
            description: row['description'] as String?,
            isActive: row['is_active'] == 1,
          ),
        )
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

  Future<List<CatalogItem>> extraWorkTypeCatalog() async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'extra_work_types',
      where: 'organization_id = ? AND deleted_at IS NULL',
      whereArgs: [orgId],
      orderBy: 'name',
    );
    return rows
        .map(
          (row) => CatalogItem(
            id: row['id']! as String,
            name: row['name']! as String,
            description: row['description'] as String?,
            defaultPrice: (row['default_price'] as num?)?.toDouble(),
            defaultOfficeAmount: (row['default_office_amount'] as num?)
                ?.toDouble(),
            requiresMaterials: row['requires_materials'] == 1,
            requiresEquipment: row['requires_equipment'] == 1,
            isActive: row['is_active'] == 1,
          ),
        )
        .toList();
  }

  Future<void> addProvider(String name, {String? description}) async {
    await _addCatalogRow('providers', {
      'name': _requiredName(name),
      'description': description?.trim().isEmpty == true
          ? null
          : description?.trim(),
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
    String? description,
    double defaultPrice = 0,
    double defaultOfficeAmount = 0,
    bool requiresMaterials = false,
    bool requiresEquipment = false,
  }) async {
    if (defaultPrice < 0 || defaultOfficeAmount < 0) {
      throw ArgumentError('Суммы не могут быть отрицательными');
    }
    await _addCatalogRow('extra_work_types', {
      'name': _requiredName(name),
      'description': description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      'default_price': defaultPrice,
      'default_office_amount': defaultOfficeAmount,
      'requires_materials': requiresMaterials ? 1 : 0,
      'requires_equipment': requiresEquipment ? 1 : 0,
      'is_active': 1,
    }, 'extra_work_type');
  }

  Future<void> updateProvider({
    required String providerId,
    required String name,
    String? description,
  }) {
    return _updateCatalogRow(
      table: 'providers',
      entityType: 'provider',
      id: providerId,
      values: {
        'name': _requiredName(name),
        'description': description?.trim().isEmpty == true
            ? null
            : description?.trim(),
      },
    );
  }

  Future<void> toggleProvider(String providerId) {
    return _toggleCatalogRow(
      table: 'providers',
      entityType: 'provider',
      id: providerId,
    );
  }

  Future<void> updateExtraWorkType({
    required String workTypeId,
    required String name,
    String? description,
    required double defaultPrice,
    required double defaultOfficeAmount,
    required bool requiresMaterials,
    required bool requiresEquipment,
  }) {
    if (defaultPrice < 0 || defaultOfficeAmount < 0) {
      throw ArgumentError('Суммы не могут быть отрицательными');
    }
    return _updateCatalogRow(
      table: 'extra_work_types',
      entityType: 'extra_work_type',
      id: workTypeId,
      values: {
        'name': _requiredName(name),
        'description': description?.trim().isEmpty == true
            ? null
            : description?.trim(),
        'default_price': defaultPrice,
        'default_office_amount': defaultOfficeAmount,
        'requires_materials': requiresMaterials ? 1 : 0,
        'requires_equipment': requiresEquipment ? 1 : 0,
      },
    );
  }

  Future<void> toggleExtraWorkType(String workTypeId) {
    return _toggleCatalogRow(
      table: 'extra_work_types',
      entityType: 'extra_work_type',
      id: workTypeId,
    );
  }

  Future<void> _updateCatalogRow({
    required String table,
    required String entityType,
    required String id,
    required Map<String, Object?> values,
  }) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        table,
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [id, orgId],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Запись не найдена');
      final row = <String, Object?>{
        ...rows.single,
        ...values,
        'updated_at': now,
        'version': (rows.single['version']! as num).toInt() + 1,
        'sync_state': 'pending',
      };
      try {
        await transaction.update(table, row, where: 'id = ?', whereArgs: [id]);
      } on DatabaseException catch (error) {
        if (error.isUniqueConstraintError()) {
          throw ArgumentError('Запись с таким названием уже существует');
        }
        rethrow;
      }
      await _queueRow(transaction, orgId, entityType, row, now);
    });
  }

  Future<void> _toggleCatalogRow({
    required String table,
    required String entityType,
    required String id,
  }) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        table,
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [id, orgId],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Запись не найдена');
      final row = <String, Object?>{
        ...rows.single,
        'is_active': rows.single['is_active'] == 1 ? 0 : 1,
        'updated_at': now,
        'version': (rows.single['version']! as num).toInt() + 1,
        'sync_state': 'pending',
      };
      await transaction.update(table, row, where: 'id = ?', whereArgs: [id]);
      await _queueRow(transaction, orgId, entityType, row, now);
    });
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

  Future<List<InventoryHistoryItem>> inventoryHistory({
    String? warehouseId,
    String? materialId,
    String? operationType,
    String? itemType,
    String? providerId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String search = '',
  }) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final from = dateFrom == null
        ? null
        : DateTime(
            dateFrom.year,
            dateFrom.month,
            dateFrom.day,
          ).toUtc().toIso8601String();
    final toExclusive = dateTo == null
        ? null
        : DateTime(
            dateTo.year,
            dateTo.month,
            dateTo.day + 1,
          ).toUtc().toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT movement.operation_type, movement.quantity, movement.occurred_at,
             movement.comment, warehouse.name warehouse_name,
             material.name material_name
      FROM inventory_transactions movement
      JOIN warehouses warehouse ON warehouse.id = movement.warehouse_id
      JOIN materials material ON material.id = movement.material_id
      WHERE movement.organization_id = ? AND movement.deleted_at IS NULL
        ${warehouseId == null ? '' : 'AND movement.warehouse_id = ?'}
        ${materialId == null ? '' : 'AND movement.material_id = ?'}
        ${operationType == null ? '' : 'AND movement.operation_type = ?'}
        ${itemType == null ? '' : 'AND material.item_type = ?'}
        ${providerId == null ? '' : 'AND COALESCE(movement.provider_id, warehouse.provider_id) = ?'}
        ${from == null ? '' : 'AND movement.occurred_at >= ?'}
        ${toExclusive == null ? '' : 'AND movement.occurred_at < ?'}
      ORDER BY movement.occurred_at DESC, movement.created_at DESC
      ''',
      [
        orgId,
        ?warehouseId,
        ?materialId,
        ?operationType,
        ?itemType,
        ?providerId,
        ?from,
        ?toExclusive,
      ],
    );
    final result = rows
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
    final normalized = search.trim().toLowerCase();
    if (normalized.isEmpty) return result;
    return result
        .where(
          (item) =>
              item.materialName.toLowerCase().contains(normalized) ||
              item.warehouseName.toLowerCase().contains(normalized) ||
              item.operationType.toLowerCase().contains(normalized) ||
              (item.comment?.toLowerCase().contains(normalized) ?? false),
        )
        .toList();
  }

  Future<ReportSummary> reportSummary({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? providerId,
  }) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final from = dateFrom?.toIso8601String().substring(0, 10);
    final to = dateTo?.toIso8601String().substring(0, 10);
    final inventoryFrom = dateFrom == null
        ? null
        : DateTime(
            dateFrom.year,
            dateFrom.month,
            dateFrom.day,
          ).toUtc().toIso8601String();
    final inventoryToExclusive = dateTo == null
        ? null
        : DateTime(
            dateTo.year,
            dateTo.month,
            dateTo.day + 1,
          ).toUtc().toIso8601String();
    String conditions(String dateColumn, String providerColumn) {
      return [
        'organization_id = ?',
        'deleted_at IS NULL',
        if (from != null) '$dateColumn >= ?',
        if (to != null) '$dateColumn <= ?',
        if (providerId != null) '$providerColumn = ?',
      ].join(' AND ');
    }

    List<Object?> args() => [orgId, ?from, ?to, ?providerId];
    Future<Map<String, Object?>> aggregate(
      String table,
      String dateColumn,
      String providerColumn,
      String amountColumn,
    ) async {
      return (await db.rawQuery('''
        SELECT COUNT(*) item_count, COALESCE(SUM($amountColumn), 0) amount
        FROM $table WHERE ${conditions(dateColumn, providerColumn)}
        ''', args())).single;
    }

    // Connection provider is reached through the client, so use a dedicated query.
    final connectionRows = await db.rawQuery('''
      SELECT COUNT(*) item_count, COALESCE(SUM(connection.price), 0) amount
      FROM connections connection
      JOIN clients client ON client.id = connection.client_id
      WHERE connection.organization_id = ? AND connection.deleted_at IS NULL
        ${from == null ? '' : 'AND connection.connection_date >= ?'}
        ${to == null ? '' : 'AND connection.connection_date <= ?'}
        ${providerId == null ? '' : 'AND client.provider_id = ?'}
      ''', args());
    final works = await aggregate(
      'extra_works',
      'work_date',
      'provider_id',
      'amount',
    );
    final expenseRows = await aggregate(
      'expenses',
      'expense_date',
      'provider_id',
      'amount',
    );
    final materialRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(ABS(quantity)), 0) amount
      FROM inventory_transactions
      WHERE organization_id = ? AND deleted_at IS NULL
        AND quantity < 0
        AND operation_type IN ('CONNECTION', 'WRITE_OFF')
        ${inventoryFrom == null ? '' : 'AND occurred_at >= ?'}
        ${inventoryToExclusive == null ? '' : 'AND occurred_at < ?'}
        ${providerId == null ? '' : 'AND provider_id = ?'}
      ''',
      [orgId, ?inventoryFrom, ?inventoryToExclusive, ?providerId],
    );
    final connection = connectionRows.single;
    return ReportSummary(
      connections: (connection['item_count']! as num).toInt(),
      connectionAmount: (connection['amount']! as num).toDouble(),
      extraWorks: (works['item_count']! as num).toInt(),
      extraWorkAmount: (works['amount']! as num).toDouble(),
      expenses: (expenseRows['amount']! as num).toDouble(),
      materialSpent: (materialRows.single['amount']! as num).toDouble(),
    );
  }

  Future<List<ReportDetailItem>> reportDetails({
    required String section,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? providerId,
    String search = '',
  }) async {
    if (section == 'providers') {
      final result = <ReportDetailItem>[];
      for (final provider in await providers()) {
        if (providerId != null && provider.id != providerId) continue;
        final summary = await reportSummary(
          dateFrom: dateFrom,
          dateTo: dateTo,
          providerId: provider.id,
        );
        result.add(
          ReportDetailItem(
            title: provider.name,
            subtitle:
                'Подключений: ${summary.connections} · '
                'Допработ: ${summary.extraWorks} · '
                'Расходы: ${summary.expenses.toStringAsFixed(2)}',
            value: summary.profit,
          ),
        );
      }
      return _filterReportDetails(result, search);
    }
    if (section == 'material_settlements') {
      return _filterReportDetails(
        (await materialSettlements())
            .map(
              (item) => ReportDetailItem(
                title: '${item.debtorName} → ${item.creditorName}',
                subtitle: '${item.materialName} · ${item.unitName}',
                value: item.quantity,
              ),
            )
            .toList(),
        search,
      );
    }
    if (section == 'finance') {
      final items =
          (await financeJournal(
                providerId: providerId,
                dateFrom: dateFrom,
                dateTo: dateTo,
                search: search,
              ))
              .map(
                (item) => ReportDetailItem(
                  title: item.type,
                  subtitle: [
                    if (item.providerName != null) item.providerName!,
                    if (item.comment != null) item.comment!,
                  ].join(' · '),
                  value: item.amount,
                ),
              )
              .toList();
      return _filterReportDetails(items, search);
    }
    if (section == 'inventory') {
      final balances = await inventoryBalances(providerId: providerId);
      final movements = await inventoryHistory(
        providerId: providerId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      final receipt = <String, double>{};
      final expense = <String, double>{};
      for (final movement in movements) {
        if (movement.quantity > 0) {
          receipt.update(
            movement.materialName,
            (value) => value + movement.quantity,
            ifAbsent: () => movement.quantity,
          );
        } else {
          expense.update(
            movement.materialName,
            (value) => value + movement.quantity.abs(),
            ifAbsent: () => movement.quantity.abs(),
          );
        }
      }
      final items = balances
          .map(
            (item) => ReportDetailItem(
              title: item.name,
              subtitle:
                  'Приход: ${(receipt[item.name] ?? 0).toStringAsFixed(2)} · '
                  'Расход: ${(expense[item.name] ?? 0).toStringAsFixed(2)} · '
                  'Остаток: ${item.quantity.toStringAsFixed(2)} ${item.unitName}',
              value: item.quantity,
            ),
          )
          .toList();
      return _filterReportDetails(items, search);
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final from = dateFrom?.toIso8601String().substring(0, 10);
    final to = dateTo?.toIso8601String().substring(0, 10);
    final inventoryFrom = dateFrom == null
        ? null
        : DateTime(
            dateFrom.year,
            dateFrom.month,
            dateFrom.day,
          ).toUtc().toIso8601String();
    final inventoryToExclusive = dateTo == null
        ? null
        : DateTime(
            dateTo.year,
            dateTo.month,
            dateTo.day + 1,
          ).toUtc().toIso8601String();
    final args = <Object?>[orgId, ?from, ?to, ?providerId];
    String dateFilter(String column) =>
        '${from == null ? '' : 'AND $column >= ?'} '
        '${to == null ? '' : 'AND $column <= ?'}';
    late final List<Map<String, Object?>> rows;
    switch (section) {
      case 'connections':
        rows = await db.rawQuery('''
          SELECT client.login title,
                 client.address || ' · ' || connection.connection_date subtitle,
                 connection.price value
          FROM connections connection
          JOIN clients client ON client.id = connection.client_id
          WHERE connection.organization_id = ? AND connection.deleted_at IS NULL
            ${dateFilter('connection.connection_date')}
            ${providerId == null ? '' : 'AND client.provider_id = ?'}
          ORDER BY connection.connection_date DESC
          ''', args);
        break;
      case 'works':
        rows = await db.rawQuery('''
          SELECT type.name title,
                 provider.name || ' · ' || work.work_date subtitle,
                 work.amount value
          FROM extra_works work
          JOIN extra_work_types type ON type.id = work.work_type_id
          JOIN providers provider ON provider.id = work.provider_id
          WHERE work.organization_id = ? AND work.deleted_at IS NULL
            ${dateFilter('work.work_date')}
            ${providerId == null ? '' : 'AND work.provider_id = ?'}
          ORDER BY work.work_date DESC
          ''', args);
        break;
      case 'expenses':
        rows = await db.rawQuery('''
          SELECT expense.description title,
                 provider.name || ' · ' || expense.expense_date subtitle,
                 expense.amount value
          FROM expenses expense
          JOIN providers provider ON provider.id = expense.provider_id
          WHERE expense.organization_id = ? AND expense.deleted_at IS NULL
            ${dateFilter('expense.expense_date')}
            ${providerId == null ? '' : 'AND expense.provider_id = ?'}
          ORDER BY expense.expense_date DESC
          ''', args);
        break;
      case 'inventory':
        rows = await db.rawQuery(
          '''
          SELECT material.name title,
                 warehouse.name || ' · ' || substr(movement.occurred_at, 1, 10) subtitle,
                 ABS(movement.quantity) value
          FROM inventory_transactions movement
          JOIN materials material ON material.id = movement.material_id
          JOIN warehouses warehouse ON warehouse.id = movement.warehouse_id
          WHERE movement.organization_id = ? AND movement.deleted_at IS NULL
            AND movement.quantity < 0
            AND movement.operation_type IN ('CONNECTION', 'WRITE_OFF')
            ${inventoryFrom == null ? '' : 'AND movement.occurred_at >= ?'}
            ${inventoryToExclusive == null ? '' : 'AND movement.occurred_at < ?'}
            ${providerId == null ? '' : 'AND movement.provider_id = ?'}
          ORDER BY movement.occurred_at DESC
          ''',
          [orgId, ?inventoryFrom, ?inventoryToExclusive, ?providerId],
        );
        break;
      default:
        throw ArgumentError('Неизвестный раздел отчёта');
    }
    return _filterReportDetails(
      rows
          .map(
            (row) => ReportDetailItem(
              title: row['title']! as String,
              subtitle: row['subtitle']! as String,
              value: (row['value']! as num).toDouble(),
            ),
          )
          .toList(),
      search,
    );
  }

  List<ReportDetailItem> _filterReportDetails(
    List<ReportDetailItem> items,
    String search,
  ) {
    final normalized = search.trim().toLowerCase();
    if (normalized.isEmpty) return items;
    return items
        .where(
          (item) =>
              item.title.toLowerCase().contains(normalized) ||
              item.subtitle.toLowerCase().contains(normalized),
        )
        .toList();
  }

  Future<List<ClientListItem>> clients({String query = ''}) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT client.id, client.provider_id, provider.name AS provider_name, client.login,
             client.contract_number, client.address, client.phone,
             client.comment,
             COUNT(connection.id) AS connection_count
      FROM clients client
      JOIN providers provider ON provider.id = client.provider_id
      LEFT JOIN connections connection
        ON connection.client_id = client.id AND connection.deleted_at IS NULL
      WHERE client.organization_id = ? AND client.deleted_at IS NULL
      GROUP BY client.id, client.provider_id, provider.name, client.login,
               client.contract_number, client.address, client.phone,
               client.comment
      ORDER BY client.updated_at DESC
      ''',
      [orgId],
    );
    final result = rows
        .map(
          (row) => ClientListItem(
            id: row['id']! as String,
            providerId: row['provider_id']! as String,
            providerName: row['provider_name']! as String,
            login: (row['login'] as String?) ?? '',
            contractNumber: (row['contract_number'] as String?) ?? '',
            address: row['address']! as String,
            phone: row['phone'] as String?,
            comment: row['comment'] as String?,
            connections: (row['connection_count']! as num).toInt(),
          ),
        )
        .toList();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return result;
    return result
        .where(
          (client) =>
              client.login.toLowerCase().contains(normalized) ||
              client.contractNumber.toLowerCase().contains(normalized) ||
              client.address.toLowerCase().contains(normalized) ||
              (client.phone?.toLowerCase().contains(normalized) ?? false) ||
              (client.comment?.toLowerCase().contains(normalized) ?? false) ||
              client.providerName.toLowerCase().contains(normalized),
        )
        .toList();
  }

  Future<List<ConnectionListItem>> connections({String? clientId}) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.rawQuery(
      '''
      SELECT connection.id, connection.connection_type,
             connection.connection_date, connection.price,
             client.login, client.address, provider.name provider_name
      FROM connections connection
      JOIN clients client ON client.id = connection.client_id
      JOIN providers provider ON provider.id = client.provider_id
      WHERE connection.organization_id = ? AND connection.deleted_at IS NULL
        ${clientId == null ? '' : 'AND connection.client_id = ?'}
      ORDER BY connection.connection_date DESC, connection.created_at DESC
      ''',
      [orgId, ?clientId],
    );
    return rows
        .map(
          (row) => ConnectionListItem(
            id: row['id']! as String,
            clientLogin: (row['login'] as String?) ?? '',
            address: row['address']! as String,
            providerName: row['provider_name']! as String,
            connectionType: row['connection_type']! as String,
            connectionDate: DateTime.parse(row['connection_date']! as String),
            price: (row['price']! as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<ConnectionEditData> connectionEditData(String connectionId) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'connections',
      where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
      whereArgs: [connectionId, orgId],
      limit: 1,
    );
    if (rows.isEmpty) throw ArgumentError('Подключение не найдено');
    final row = rows.single;
    final usage = await db.query(
      'connection_materials',
      columns: ['material_id', 'quantity'],
      where: 'connection_id = ? AND deleted_at IS NULL',
      whereArgs: [connectionId],
    );
    return ConnectionEditData(
      warehouseId: row['warehouse_id']! as String,
      connectionType: row['connection_type']! as String,
      connectionDate: DateTime.parse(row['connection_date']! as String),
      price: (row['price']! as num).toDouble(),
      officeAmount: (row['office_amount']! as num).toDouble(),
      installerAmount: (row['installer_amount']! as num).toDouble(),
      comment: row['comment'] as String?,
      materials: {
        for (final item in usage)
          item['material_id']! as String: (item['quantity']! as num).toDouble(),
      },
    );
  }

  Future<void> deleteConnection(String connectionId) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final connectionRows = await transaction.query(
        'connections',
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [connectionId, orgId],
        limit: 1,
      );
      if (connectionRows.isEmpty) {
        throw ArgumentError('Подключение не найдено');
      }
      final connection = connectionRows.single;
      final inventoryRows = await transaction.query(
        'inventory_transactions',
        where:
            'connection_id = ? AND operation_type = ? AND deleted_at IS NULL',
        whereArgs: [connectionId, 'CONNECTION'],
      );
      for (final original in inventoryRows) {
        final returnRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'warehouse_id': original['warehouse_id'],
          'provider_id': original['provider_id'],
          'material_id': original['material_id'],
          'connection_id': connectionId,
          'operation_type': 'RETURN',
          'quantity': -(original['quantity']! as num).toDouble(),
          'comment': 'Отмена подключения',
          'occurred_at': now,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('inventory_transactions', returnRow);
        await _queueRow(
          transaction,
          orgId,
          'inventory_transaction',
          returnRow,
          now,
        );
      }
      Future<void> softDelete(String table, String entityType) async {
        final rows = await transaction.query(
          table,
          where: table == 'connections'
              ? 'id = ?'
              : '${table == 'connection_materials' ? 'connection_id' : 'connection_id'} = ? AND deleted_at IS NULL',
          whereArgs: [connectionId],
        );
        for (final row in rows) {
          await transaction.update(
            table,
            {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          await _enqueue(
            transaction,
            organizationId: orgId,
            entityType: entityType,
            entityId: row['id']! as String,
            operation: 'delete',
            payload: {...row, 'deleted_at': now},
            now: now,
          );
        }
      }

      await softDelete('connection_materials', 'connection_material');
      await softDelete('finance_transactions', 'finance_transaction');
      await softDelete('connections', 'connection');
      // Preserve the original connection row in the delete payload.
      assert(connection['id'] == connectionId);
    });
  }

  Future<void> updateConnection({
    required String connectionId,
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
    if (materials.any((item) => item.quantity <= 0)) {
      throw ArgumentError('Количество материала должно быть больше нуля');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        '''
        SELECT connection.*, client.provider_id
        FROM connections connection
        JOIN clients client ON client.id = connection.client_id
        WHERE connection.id = ? AND connection.organization_id = ?
          AND connection.deleted_at IS NULL
        ''',
        [connectionId, orgId],
      );
      if (rows.isEmpty) throw ArgumentError('Подключение не найдено');
      final oldInventory = await transaction.query(
        'inventory_transactions',
        where:
            'connection_id = ? AND operation_type = ? AND deleted_at IS NULL',
        whereArgs: [connectionId, 'CONNECTION'],
      );
      for (final original in oldInventory) {
        final reversal = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'warehouse_id': original['warehouse_id'],
          'provider_id': original['provider_id'],
          'material_id': original['material_id'],
          'connection_id': connectionId,
          'operation_type': 'RETURN',
          'quantity': -(original['quantity']! as num).toDouble(),
          'comment': 'Пересчёт подключения',
          'occurred_at': now,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('inventory_transactions', reversal);
        await _queueRow(
          transaction,
          orgId,
          'inventory_transaction',
          reversal,
          now,
        );
      }
      for (final table in ['connection_materials', 'finance_transactions']) {
        final oldRows = await transaction.query(
          table,
          where: 'connection_id = ? AND deleted_at IS NULL',
          whereArgs: [connectionId],
        );
        for (final old in oldRows) {
          await transaction.update(
            table,
            {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
            where: 'id = ?',
            whereArgs: [old['id']],
          );
          await _enqueue(
            transaction,
            organizationId: orgId,
            entityType: table == 'connection_materials'
                ? 'connection_material'
                : 'finance_transaction',
            entityId: old['id']! as String,
            operation: 'delete',
            payload: {...old, 'deleted_at': now},
            now: now,
          );
        }
      }
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
      final version = (rows.single['version']! as num).toInt() + 1;
      final connectionRow = <String, Object?>{
        ...rows.single,
        'warehouse_id': warehouseId,
        'connection_type': connectionType,
        'connection_date': connectionDate.toIso8601String().substring(0, 10),
        'price': price,
        'office_amount': officeAmount,
        'installer_amount': installerAmount,
        'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
        'updated_at': now,
        'version': version,
        'sync_state': 'pending',
      }..remove('provider_id');
      await transaction.update(
        'connections',
        connectionRow,
        where: 'id = ?',
        whereArgs: [connectionId],
      );
      await _queueRow(transaction, orgId, 'connection', connectionRow, now);
      final providerId = rows.single['provider_id']! as String;
      for (final material in materials) {
        final usage = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'connection_id': connectionId,
          'material_id': material.materialId,
          'quantity': material.quantity,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        final movement = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'warehouse_id': warehouseId,
          'provider_id': providerId,
          'material_id': material.materialId,
          'connection_id': connectionId,
          'operation_type': 'CONNECTION',
          'quantity': -material.quantity,
          'comment': comment,
          'occurred_at': connectionDate.toUtc().toIso8601String(),
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('connection_materials', usage);
        await transaction.insert('inventory_transactions', movement);
        await _queueRow(transaction, orgId, 'connection_material', usage, now);
        await _queueRow(
          transaction,
          orgId,
          'inventory_transaction',
          movement,
          now,
        );
      }
      for (final accrual in [
        (
          amount: installerAmount,
          to: 'INSTALLER',
          label: 'Начисление монтажнику',
        ),
        (amount: officeAmount, to: 'OFFICE', label: 'Начисление офису'),
      ]) {
        if (accrual.amount <= 0) continue;
        final finance = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'provider_id': providerId,
          'connection_id': connectionId,
          'transaction_type': 'CONNECTION',
          'accrual_to': accrual.to,
          'amount': accrual.amount,
          'comment': accrual.label,
          'occurred_at': connectionDate.toUtc().toIso8601String(),
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('finance_transactions', finance);
        await _queueRow(
          transaction,
          orgId,
          'finance_transaction',
          finance,
          now,
        );
      }
    });
  }

  Future<String> addClient({
    required String providerId,
    required String contractNumber,
    required String login,
    required String address,
    String? phone,
    String? comment,
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
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
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

  Future<void> updateClient({
    required String clientId,
    required String providerId,
    required String contractNumber,
    required String login,
    required String address,
    String? phone,
    String? comment,
  }) async {
    final cleanContract = contractNumber.trim();
    final cleanLogin = login.trim();
    final cleanAddress = address.trim();
    if (cleanContract.isEmpty || cleanLogin.isEmpty || cleanAddress.isEmpty) {
      throw ArgumentError('Заполните договор, логин и адрес');
    }
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'clients',
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [clientId, orgId],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Клиент не найден');
      final duplicate = await transaction.query(
        'clients',
        columns: ['id'],
        where:
            'organization_id = ? AND id <> ? AND deleted_at IS NULL '
            'AND (contract_number = ? OR login = ?)',
        whereArgs: [orgId, clientId, cleanContract, cleanLogin],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw ArgumentError('Клиент с таким договором или логином уже есть');
      }
      final row = <String, Object?>{
        ...rows.single,
        'provider_id': providerId,
        'contract_number': cleanContract,
        'login': cleanLogin,
        'address': cleanAddress,
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
        'updated_at': now,
        'version': (rows.single['version']! as num).toInt() + 1,
        'sync_state': 'pending',
      };
      await transaction.update(
        'clients',
        row,
        where: 'id = ?',
        whereArgs: [clientId],
      );
      await _queueRow(transaction, orgId, 'client', row, now);
    });
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

  Future<void> addInventoryOperation({
    required String warehouseId,
    required String materialId,
    required String operationType,
    required double quantity,
    String adjustmentDirection = 'plus',
    String? comment,
  }) async {
    const supported = {
      'ISSUE_TO_THIRD_PARTY',
      'RETURN',
      'WRITE_OFF',
      'ADJUSTMENT',
    };
    if (!supported.contains(operationType)) {
      throw ArgumentError('Некорректный тип складской операции');
    }
    if (quantity <= 0) {
      throw ArgumentError('Количество должно быть больше нуля');
    }
    if (!{'plus', 'minus'}.contains(adjustmentDirection)) {
      throw ArgumentError('Некорректное направление корректировки');
    }
    final isNegative =
        operationType == 'ISSUE_TO_THIRD_PARTY' ||
        operationType == 'WRITE_OFF' ||
        (operationType == 'ADJUSTMENT' && adjustmentDirection == 'minus');
    final signedQuantity = isNegative ? -quantity : quantity;
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      if (isNegative) {
        final available = await _balanceInTransaction(
          transaction,
          organizationId: orgId,
          warehouseId: warehouseId,
          materialId: materialId,
        );
        if (available + 0.000001 < quantity) {
          throw StateError(
            'Недостаточно на складе. Остаток: $available, требуется: $quantity',
          );
        }
      }
      final row = <String, Object?>{
        'id': _uuid.v7(),
        'organization_id': orgId,
        'warehouse_id': warehouseId,
        'material_id': materialId,
        'operation_type': operationType,
        'quantity': signedQuantity,
        'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
        'occurred_at': now,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'sync_state': 'pending',
      };
      await transaction.insert('inventory_transactions', row);
      await _queueRow(transaction, orgId, 'inventory_transaction', row, now);
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

  Future<FinanceSummary> financeSummary({
    String? providerId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final from = dateFrom == null
        ? null
        : DateTime(
            dateFrom.year,
            dateFrom.month,
            dateFrom.day,
          ).toUtc().toIso8601String();
    final toExclusive = dateTo == null
        ? null
        : DateTime(
            dateTo.year,
            dateTo.month,
            dateTo.day + 1,
          ).toUtc().toIso8601String();
    Future<double> sum(String condition, {bool cumulative = false}) async {
      final where = [
        'organization_id = ?',
        'deleted_at IS NULL',
        if (providerId != null) 'provider_id = ?',
        if (!cumulative && from != null) 'occurred_at >= ?',
        if (toExclusive != null) 'occurred_at < ?',
      ].join(' AND ');
      final arguments = <Object?>[
        orgId,
        ?providerId,
        if (!cumulative) ?from,
        ?toExclusive,
      ];
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM($condition), 0) AS amount
        FROM finance_transactions
        WHERE $where
        ''', arguments);
      return (rows.single['amount']! as num).toDouble();
    }

    final customerReceived = await sum(
      "CASE WHEN transaction_type = 'CONNECTION' AND amount > 0 THEN amount ELSE 0 END",
    );
    final installerAccrued = await sum(
      "CASE WHEN transaction_type IN ('CONNECTION', 'EXTRA_WORK') "
      "AND accrual_to = 'INSTALLER' AND amount > 0 THEN amount ELSE 0 END",
    );
    final officeAccrued = await sum(
      "CASE WHEN transaction_type = 'CONNECTION' AND accrual_to = 'OFFICE' AND amount > 0 THEN amount ELSE 0 END",
    );
    final extraWorkIncome = await sum(
      "CASE WHEN transaction_type = 'EXTRA_WORK' AND amount > 0 THEN amount ELSE 0 END",
    );
    final paidFromOffice = await sum(
      "CASE WHEN transaction_type = 'PAYMENT_FROM_OFFICE' THEN amount ELSE 0 END",
    );
    final paidToOffice = await sum(
      "CASE WHEN transaction_type = 'PAYMENT_TO_OFFICE' THEN ABS(amount) ELSE 0 END",
    );
    final paidFromOfficeBalance = await sum(
      "CASE WHEN transaction_type = 'PAYMENT_FROM_OFFICE' THEN amount ELSE 0 END",
      cumulative: true,
    );
    final paidToOfficeBalance = await sum(
      "CASE WHEN transaction_type = 'PAYMENT_TO_OFFICE' THEN ABS(amount) ELSE 0 END",
      cumulative: true,
    );
    final adjustments = await sum(
      "CASE WHEN transaction_type = 'ADJUSTMENT' THEN amount ELSE 0 END",
      cumulative: true,
    );
    final extraWorkInstaller = await sum(
      "CASE WHEN transaction_type = 'EXTRA_WORK' AND accrual_to = 'INSTALLER' AND amount > 0 THEN amount ELSE 0 END",
      cumulative: true,
    );
    final officeAccruedBalance = await sum(
      "CASE WHEN transaction_type = 'CONNECTION' AND accrual_to = 'OFFICE' AND amount > 0 THEN amount ELSE 0 END",
      cumulative: true,
    );
    final expenseFrom = dateFrom?.toIso8601String().substring(0, 10);
    final expenseTo = dateTo?.toIso8601String().substring(0, 10);
    final expenseWhere = [
      'organization_id = ?',
      "paid_by = 'INSTALLER'",
      'deleted_at IS NULL',
      if (providerId != null) 'provider_id = ?',
      if (expenseFrom != null) 'expense_date >= ?',
      if (expenseTo != null) 'expense_date <= ?',
    ].join(' AND ');
    final expenseRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS amount FROM expenses
      WHERE $expenseWhere
      ''',
      [orgId, ?providerId, ?expenseFrom, ?expenseTo],
    );
    final installerExpenses = (expenseRows.single['amount']! as num).toDouble();
    final allExpenseWhere = [
      'organization_id = ?',
      'deleted_at IS NULL',
      if (providerId != null) 'provider_id = ?',
      if (expenseFrom != null) 'expense_date >= ?',
      if (expenseTo != null) 'expense_date <= ?',
    ].join(' AND ');
    final allExpenseRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS amount FROM expenses
      WHERE $allExpenseWhere
      ''',
      [orgId, ?providerId, ?expenseFrom, ?expenseTo],
    );
    final expensesTotal = (allExpenseRows.single['amount']! as num).toDouble();
    final debtExpenseWhere = [
      'organization_id = ?',
      "paid_by = 'INSTALLER'",
      'deleted_at IS NULL',
      if (providerId != null) 'provider_id = ?',
      if (expenseTo != null) 'expense_date <= ?',
    ].join(' AND ');
    final debtExpenseRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS amount FROM expenses
      WHERE $debtExpenseWhere
      ''',
      [orgId, ?providerId, ?expenseTo],
    );
    final debtInstallerExpenses = (debtExpenseRows.single['amount']! as num)
        .toDouble();
    final balance =
        extraWorkInstaller +
        debtInstallerExpenses -
        paidFromOfficeBalance +
        adjustments -
        officeAccruedBalance +
        paidToOfficeBalance;
    final incomeTotal = customerReceived + extraWorkIncome;
    return FinanceSummary(
      customerReceived: customerReceived,
      installerAccrued: installerAccrued,
      officeAccrued: officeAccrued,
      extraWorkIncome: extraWorkIncome,
      incomeTotal: incomeTotal,
      expensesTotal: expensesTotal,
      profit: incomeTotal - expensesTotal,
      paidToOffice: paidToOffice,
      paidFromOffice: paidFromOffice,
      balance: balance,
      availableCash:
          customerReceived + paidFromOffice - paidToOffice - installerExpenses,
    );
  }

  Future<List<FinanceJournalItem>> financeJournal({
    String? providerId,
    String? transactionType,
    DateTime? dateFrom,
    DateTime? dateTo,
    String search = '',
  }) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final from = dateFrom == null
        ? null
        : DateTime(
            dateFrom.year,
            dateFrom.month,
            dateFrom.day,
          ).toUtc().toIso8601String();
    final toExclusive = dateTo == null
        ? null
        : DateTime(
            dateTo.year,
            dateTo.month,
            dateTo.day + 1,
          ).toUtc().toIso8601String();
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
        ${transactionType == null ? '' : 'AND transaction_row.transaction_type = ?'}
        ${from == null ? '' : 'AND transaction_row.occurred_at >= ?'}
        ${toExclusive == null ? '' : 'AND transaction_row.occurred_at < ?'}
      ORDER BY transaction_row.occurred_at DESC, transaction_row.created_at DESC
      ''',
      [orgId, ?providerId, ?transactionType, ?from, ?toExclusive],
    );
    final result = rows
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
    final normalized = search.trim().toLowerCase();
    if (normalized.isEmpty) return result;
    return result
        .where(
          (item) =>
              item.type.toLowerCase().contains(normalized) ||
              (item.providerName?.toLowerCase().contains(normalized) ??
                  false) ||
              (item.comment?.toLowerCase().contains(normalized) ?? false),
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
          'extra_work_id': workId,
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
      SELECT work.id, work.amount, work.work_date, work.comment,
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
            id: row['id']! as String,
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
      SELECT expense.id, expense.category, expense.description, expense.amount,
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
            id: row['id']! as String,
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

  Future<ExtraWorkEditData> extraWorkEditData(String extraWorkId) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'extra_works',
      where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
      whereArgs: [extraWorkId, orgId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError('Дополнительная работа не найдена');
    }
    final row = rows.single;
    final usages = await db.query(
      'extra_work_materials',
      columns: ['material_id', 'quantity'],
      where: 'extra_work_id = ? AND deleted_at IS NULL',
      whereArgs: [extraWorkId],
    );
    return ExtraWorkEditData(
      providerId: row['provider_id']! as String,
      workTypeId: row['work_type_id']! as String,
      workDate: DateTime.parse(row['work_date']! as String),
      amount: (row['amount']! as num).toDouble(),
      warehouseId: row['warehouse_id'] as String?,
      materials: {
        for (final usage in usages)
          usage['material_id']! as String: (usage['quantity']! as num)
              .toDouble(),
      },
      comment: row['comment'] as String?,
    );
  }

  Future<ExpenseEditData> expenseEditData(String expenseId) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'expenses',
      where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
      whereArgs: [expenseId, orgId],
      limit: 1,
    );
    if (rows.isEmpty) throw ArgumentError('Расход не найден');
    final row = rows.single;
    return ExpenseEditData(
      providerId: row['provider_id']! as String,
      category: row['category']! as String,
      description: row['description']! as String,
      amount: (row['amount']! as num).toDouble(),
      paidBy: row['paid_by']! as String,
      expenseDate: DateTime.parse(row['expense_date']! as String),
      comment: row['comment'] as String?,
    );
  }

  Future<void> updateExpense({
    required String expenseId,
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
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'expenses',
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [expenseId, orgId],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Расход не найден');
      final oldFinance = await transaction.query(
        'finance_transactions',
        where: 'expense_id = ? AND deleted_at IS NULL',
        whereArgs: [expenseId],
      );
      for (final old in oldFinance) {
        await transaction.update(
          'finance_transactions',
          {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
          where: 'id = ?',
          whereArgs: [old['id']],
        );
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: 'finance_transaction',
          entityId: old['id']! as String,
          operation: 'delete',
          payload: {...old, 'deleted_at': now},
          now: now,
        );
      }
      final expenseRow = <String, Object?>{
        ...rows.single,
        'provider_id': providerId,
        'category': category,
        'description': description.trim(),
        'amount': amount,
        'paid_by': paidBy,
        'expense_date': expenseDate.toIso8601String().substring(0, 10),
        'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
        'updated_at': now,
        'version': (rows.single['version']! as num).toInt() + 1,
        'sync_state': 'pending',
      };
      await transaction.update(
        'expenses',
        expenseRow,
        where: 'id = ?',
        whereArgs: [expenseId],
      );
      await _queueRow(transaction, orgId, 'expense', expenseRow, now);
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
      await transaction.insert('finance_transactions', financeRow);
      await _queueRow(
        transaction,
        orgId,
        'finance_transaction',
        financeRow,
        now,
      );
    });
  }

  Future<void> updateExtraWork({
    required String extraWorkId,
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
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'extra_works',
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [extraWorkId, orgId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw ArgumentError('Дополнительная работа не найдена');
      }
      final oldWork = rows.single;
      final oldUsages = await transaction.query(
        'extra_work_materials',
        where: 'extra_work_id = ? AND deleted_at IS NULL',
        whereArgs: [extraWorkId],
      );
      final oldWarehouseId = oldWork['warehouse_id'] as String?;
      if (oldUsages.isNotEmpty && oldWarehouseId == null) {
        throw StateError('У дополнительной работы не указан склад');
      }
      for (final usage in oldUsages) {
        final reversal = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'warehouse_id': oldWarehouseId,
          'provider_id': oldWork['provider_id'],
          'material_id': usage['material_id'],
          'extra_work_id': extraWorkId,
          'operation_type': 'RETURN',
          'quantity': (usage['quantity']! as num).toDouble(),
          'comment': 'Пересчёт дополнительной работы',
          'occurred_at': now,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('inventory_transactions', reversal);
        await _queueRow(
          transaction,
          orgId,
          'inventory_transaction',
          reversal,
          now,
        );
      }
      for (final table in ['extra_work_materials', 'finance_transactions']) {
        final oldRows = await transaction.query(
          table,
          where: 'extra_work_id = ? AND deleted_at IS NULL',
          whereArgs: [extraWorkId],
        );
        for (final old in oldRows) {
          await transaction.update(
            table,
            {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
            where: 'id = ?',
            whereArgs: [old['id']],
          );
          await _enqueue(
            transaction,
            organizationId: orgId,
            entityType: table == 'extra_work_materials'
                ? 'extra_work_material'
                : 'finance_transaction',
            entityId: old['id']! as String,
            operation: 'delete',
            payload: {...old, 'deleted_at': now},
            now: now,
          );
        }
      }
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
      final workRow = <String, Object?>{
        ...oldWork,
        'provider_id': providerId,
        'work_type_id': workTypeId,
        'warehouse_id': warehouseId,
        'work_date': workDate.toIso8601String().substring(0, 10),
        'amount': amount,
        'installer_amount': amount,
        'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
        'updated_at': now,
        'version': (oldWork['version']! as num).toInt() + 1,
        'sync_state': 'pending',
      };
      await transaction.update(
        'extra_works',
        workRow,
        where: 'id = ?',
        whereArgs: [extraWorkId],
      );
      await _queueRow(transaction, orgId, 'extra_work', workRow, now);
      for (final material in materials) {
        final usageRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'extra_work_id': extraWorkId,
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
          'extra_work_id': extraWorkId,
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
          'extra_work_id': extraWorkId,
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

  Future<void> deleteExtraWork(String extraWorkId) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final works = await transaction.query(
        'extra_works',
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [extraWorkId, orgId],
        limit: 1,
      );
      if (works.isEmpty) {
        throw ArgumentError('Дополнительная работа не найдена');
      }
      final work = works.single;
      final warehouseId = work['warehouse_id'] as String?;
      final usages = await transaction.query(
        'extra_work_materials',
        where: 'extra_work_id = ? AND deleted_at IS NULL',
        whereArgs: [extraWorkId],
      );
      if (usages.isNotEmpty && warehouseId == null) {
        throw StateError('У дополнительной работы не указан склад');
      }
      for (final usage in usages) {
        final returnRow = <String, Object?>{
          'id': _uuid.v7(),
          'organization_id': orgId,
          'warehouse_id': warehouseId,
          'provider_id': work['provider_id'],
          'material_id': usage['material_id'],
          'extra_work_id': extraWorkId,
          'operation_type': 'RETURN',
          'quantity': (usage['quantity']! as num).toDouble(),
          'comment': 'Отмена дополнительной работы',
          'occurred_at': now,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'sync_state': 'pending',
        };
        await transaction.insert('inventory_transactions', returnRow);
        await _queueRow(
          transaction,
          orgId,
          'inventory_transaction',
          returnRow,
          now,
        );
      }

      Future<void> softDelete(
        String table,
        String entityType,
        String foreignKey,
      ) async {
        final rows = await transaction.query(
          table,
          where: '$foreignKey = ? AND deleted_at IS NULL',
          whereArgs: [extraWorkId],
        );
        for (final row in rows) {
          await transaction.update(
            table,
            {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          await _enqueue(
            transaction,
            organizationId: orgId,
            entityType: entityType,
            entityId: row['id']! as String,
            operation: 'delete',
            payload: {...row, 'deleted_at': now},
            now: now,
          );
        }
      }

      await softDelete(
        'extra_work_materials',
        'extra_work_material',
        'extra_work_id',
      );
      await softDelete(
        'finance_transactions',
        'finance_transaction',
        'extra_work_id',
      );
      await transaction.update(
        'extra_works',
        {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
        where: 'id = ?',
        whereArgs: [extraWorkId],
      );
      await _enqueue(
        transaction,
        organizationId: orgId,
        entityType: 'extra_work',
        entityId: extraWorkId,
        operation: 'delete',
        payload: {...work, 'deleted_at': now},
        now: now,
      );
    });
  }

  Future<void> deleteExpense(String expenseId) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final expenses = await transaction.query(
        'expenses',
        where: 'id = ? AND organization_id = ? AND deleted_at IS NULL',
        whereArgs: [expenseId, orgId],
        limit: 1,
      );
      if (expenses.isEmpty) throw ArgumentError('Расход не найден');
      final expense = expenses.single;
      final financeRows = await transaction.query(
        'finance_transactions',
        where: 'expense_id = ? AND deleted_at IS NULL',
        whereArgs: [expenseId],
      );
      for (final row in financeRows) {
        await transaction.update(
          'finance_transactions',
          {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        await _enqueue(
          transaction,
          organizationId: orgId,
          entityType: 'finance_transaction',
          entityId: row['id']! as String,
          operation: 'delete',
          payload: {...row, 'deleted_at': now},
          now: now,
        );
      }
      await transaction.update(
        'expenses',
        {'deleted_at': now, 'updated_at': now, 'sync_state': 'pending'},
        where: 'id = ?',
        whereArgs: [expenseId],
      );
      await _enqueue(
        transaction,
        organizationId: orgId,
        entityType: 'expense',
        entityId: expenseId,
        operation: 'delete',
        payload: {...expense, 'deleted_at': now},
        now: now,
      );
    });
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

  Future<List<SyncQueueItem>> syncQueue({int limit = 200}) async {
    final db = await database.instance;
    final orgId = await organizationId;
    final rows = await db.query(
      'sync_queue',
      where: 'organization_id = ?',
      whereArgs: [orgId],
      orderBy: 'created_at',
      limit: limit,
    );
    return rows.map((row) {
      final payload = Map<String, Object?>.from(
        jsonDecode(row['payload']! as String) as Map,
      );
      return SyncQueueItem(
        entityType: row['entity_type']! as String,
        entityId: row['entity_id']! as String,
        operation: row['operation']! as String,
        version: (payload['version'] as num?)?.toInt() ?? 1,
        payload: payload,
      );
    }).toList();
  }

  Future<void> acknowledgeSync(String entityType, String entityId) async {
    final db = await database.instance;
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }

  Future<void> markSyncError(
    String entityType,
    String entityId,
    String error,
  ) async {
    final db = await database.instance;
    await db.rawUpdate(
      '''
      UPDATE sync_queue SET attempts = attempts + 1, last_error = ?
      WHERE entity_type = ? AND entity_id = ?
      ''',
      [error, entityType, entityId],
    );
  }

  Future<int> syncCursor() async {
    final db = await database.instance;
    final row = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['sync_cursor'],
      limit: 1,
    );
    return row.isEmpty ? 0 : int.tryParse(row.single['value']! as String) ?? 0;
  }

  Future<void> applyRemoteChanges(
    List<Map<String, Object?>> changes,
    int cursor,
  ) async {
    final db = await database.instance;
    final orgId = await organizationId;
    const tables = {
      'provider': 'providers',
      'providers': 'providers',
      'warehouse': 'warehouses',
      'warehouses': 'warehouses',
      'material': 'materials',
      'materials': 'materials',
      'user': 'users',
      'client': 'clients',
      'connection': 'connections',
      'connection_material': 'connection_materials',
      'inventory_transaction': 'inventory_transactions',
      'finance_transaction': 'finance_transactions',
      'extra_work_type': 'extra_work_types',
      'extra_work_types': 'extra_work_types',
      'extra_work': 'extra_works',
      'extra_work_material': 'extra_work_materials',
      'expense': 'expenses',
    };
    await db.transaction((transaction) async {
      for (final change in changes) {
        final table = tables[change['entity_type']];
        if (table == null) continue;
        final payload = Map<String, Object?>.from(change['payload']! as Map);
        if (payload.containsKey('organization_id')) {
          payload['organization_id'] = orgId;
        }
        if (change['operation'] == 'delete') {
          await transaction.update(
            table,
            {'deleted_at': DateTime.now().toUtc().toIso8601String()},
            where: 'id = ?',
            whereArgs: [change['entity_id']],
          );
        } else {
          await transaction.insert(
            table,
            payload,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await transaction.insert('app_settings', {
        'key': 'sync_cursor',
        'value': cursor.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
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
