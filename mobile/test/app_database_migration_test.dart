import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:telecom_manager_mobile/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('version 8 database gains new columns without losing rows', () async {
    final databasePath = path.join(
      Directory.systemTemp.path,
      'telecom-manager-migration-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final old = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE providers (
              id TEXT PRIMARY KEY,
              organization_id TEXT NOT NULL,
              name TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted_at TEXT,
              version INTEGER NOT NULL DEFAULT 1,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');
          await db.execute('''
            CREATE TABLE extra_work_types (
              id TEXT PRIMARY KEY,
              organization_id TEXT NOT NULL,
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
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');
          await db.execute('''
            CREATE TABLE users (
              id TEXT PRIMARY KEY,
              organization_id TEXT NOT NULL,
              username TEXT NOT NULL,
              full_name TEXT NOT NULL,
              role TEXT NOT NULL,
              password_hash TEXT,
              password_salt TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
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
              organization_id TEXT NOT NULL,
              provider_id TEXT NOT NULL,
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
          await db.insert('clients', {
            'id': 'client-1',
            'organization_id': 'org-1',
            'provider_id': 'provider-1',
            'contract_number': '100',
            'login': 'client',
            'address': 'Адрес',
            'created_at': '2026-07-27T00:00:00Z',
            'updated_at': '2026-07-27T00:00:00Z',
          });
        },
      ),
    );
    await old.close();

    final appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: databasePath,
    );
    final upgraded = await appDatabase.instance;
    final columns = await upgraded.rawQuery('PRAGMA table_info(clients)');
    final providerColumns = await upgraded.rawQuery(
      'PRAGMA table_info(providers)',
    );
    final workTypeColumns = await upgraded.rawQuery(
      'PRAGMA table_info(extra_work_types)',
    );
    final userColumns = await upgraded.rawQuery('PRAGMA table_info(users)');
    final rows = await upgraded.query('clients');

    expect(columns.map((row) => row['name']), contains('comment'));
    expect(providerColumns.map((row) => row['name']), contains('description'));
    expect(
      workTypeColumns.map((row) => row['name']),
      contains('default_office_amount'),
    );
    expect(userColumns.map((row) => row['name']), contains('manager_id'));
    expect(userColumns.map((row) => row['name']), contains('comment'));
    expect(userColumns.map((row) => row['name']), contains('last_login_at'));
    expect(rows.single['id'], 'client-1');
    expect(rows.single['comment'], isNull);

    await appDatabase.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });
}
