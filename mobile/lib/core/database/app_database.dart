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
        version: 2,
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
}
