import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, this.overridePath})
    : factory = factory ?? databaseFactory;

  final DatabaseFactory factory;
  final String? overridePath;
  Database? _database;

  Future<Database> get instance async {
    if (_database != null) return _database!;
    final databasePath =
        overridePath ??
        path.join(await getDatabasesPath(), 'telecom_manager.db');
    _database = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE organizations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        mode TEXT NOT NULL DEFAULT 'local',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE providers (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending',
        UNIQUE (organization_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE warehouses (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        provider_id TEXT REFERENCES providers(id),
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending',
        UNIQUE (organization_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE materials (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        name TEXT NOT NULL,
        item_type TEXT NOT NULL,
        unit_name TEXT NOT NULL,
        category TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending',
        UNIQUE (organization_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE inventory_transactions (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id),
        counterpart_warehouse_id TEXT REFERENCES warehouses(id),
        provider_id TEXT REFERENCES providers(id),
        material_id TEXT NOT NULL REFERENCES materials(id),
        connection_id TEXT,
        operation_type TEXT NOT NULL,
        quantity REAL NOT NULL CHECK (quantity <> 0),
        comment TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE clients (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        provider_id TEXT NOT NULL REFERENCES providers(id),
        contract_number TEXT,
        login TEXT,
        address TEXT NOT NULL,
        phone TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE connections (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        client_id TEXT NOT NULL REFERENCES clients(id),
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id),
        connection_type TEXT NOT NULL,
        connection_date TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        office_amount REAL NOT NULL DEFAULT 0,
        installer_amount REAL NOT NULL DEFAULT 0,
        comment TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await _createConnectionMaterials(db);
    await _createFinanceTables(db);
    await _createWorkAndExpenseTables(db);
    await db.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        UNIQUE (entity_type, entity_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX ix_inventory_org_material ON inventory_transactions(organization_id, material_id)',
    );
    await db.execute(
      'CREATE INDEX ix_inventory_connection ON inventory_transactions(connection_id)',
    );
    await db.execute(
      'CREATE INDEX ix_sync_queue_created ON sync_queue(created_at)',
    );
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createConnectionMaterials(db);
      await db.execute(
        'CREATE INDEX ix_clients_org_provider ON clients(organization_id, provider_id)',
      );
      await db.execute(
        'CREATE INDEX ix_connections_org_date ON connections(organization_id, connection_date)',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE inventory_transactions ADD COLUMN connection_id TEXT',
      );
      await db.execute(
        'CREATE INDEX ix_inventory_connection ON inventory_transactions(connection_id)',
      );
    }
    if (oldVersion < 4) {
      await _createFinanceTables(db);
    }
    if (oldVersion < 5) {
      await _createWorkAndExpenseTables(db);
    }
  }

  Future<void> _createConnectionMaterials(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS connection_materials (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        connection_id TEXT NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
        material_id TEXT NOT NULL REFERENCES materials(id),
        quantity REAL NOT NULL CHECK (quantity > 0),
        comment TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_connection_materials_connection ON connection_materials(connection_id)',
    );
  }

  Future<void> _createFinanceTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS finance_transactions (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        provider_id TEXT REFERENCES providers(id),
        connection_id TEXT REFERENCES connections(id) ON DELETE CASCADE,
        expense_id TEXT,
        extra_work_id TEXT,
        transaction_type TEXT NOT NULL,
        accrual_to TEXT,
        amount REAL NOT NULL CHECK (amount <> 0),
        comment TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_finance_org_date ON finance_transactions(organization_id, occurred_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_finance_provider ON finance_transactions(provider_id)',
    );
  }

  Future<void> _createWorkAndExpenseTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS extra_work_types (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        name TEXT NOT NULL,
        description TEXT,
        default_price REAL,
        requires_materials INTEGER NOT NULL DEFAULT 0,
        requires_equipment INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending',
        UNIQUE (organization_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS extra_works (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        provider_id TEXT NOT NULL REFERENCES providers(id),
        work_type_id TEXT NOT NULL REFERENCES extra_work_types(id),
        warehouse_id TEXT REFERENCES warehouses(id),
        work_date TEXT NOT NULL,
        amount REAL NOT NULL CHECK (amount >= 0),
        office_amount REAL NOT NULL DEFAULT 0,
        installer_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'completed',
        comment TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS extra_work_materials (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        extra_work_id TEXT NOT NULL REFERENCES extra_works(id) ON DELETE CASCADE,
        material_id TEXT NOT NULL REFERENCES materials(id),
        quantity REAL NOT NULL CHECK (quantity > 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        provider_id TEXT NOT NULL REFERENCES providers(id),
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        paid_by TEXT NOT NULL,
        expense_date TEXT NOT NULL,
        comment TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_extra_works_org_date ON extra_works(organization_id, work_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_expenses_org_date ON expenses(organization_id, expense_date)',
    );
  }
}
