import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:telecom_manager_mobile/core/database/app_database.dart';
import 'package:telecom_manager_mobile/core/repositories/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late LocalRepository repository;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: inMemoryDatabasePath,
    );
    repository = LocalRepository(database);
    await repository.initialize();
  });

  tearDown(() => database.close());

  test('seeds an isolated local organization', () async {
    final summary = await repository.dashboardSummary();

    expect(summary.organizationName, 'Локальная организация');
    expect(summary.providers, 2);
    expect(summary.warehouses, 2);
    expect(summary.materials, 2);
    expect(summary.pendingChanges, 7);
  });

  test('receipt updates stock and sync queue atomically', () async {
    final warehouses = await repository.warehouses();
    final materials = await repository.materials();
    final pendingBefore = await repository.pendingChanges();

    await repository.addReceipt(
      warehouseId: warehouses.first.id,
      materialId: materials.first.id,
      quantity: 10,
      comment: 'Первый локальный приход',
    );

    final balances = await repository.inventoryBalances();
    final changed = balances.singleWhere(
      (item) => item.materialId == materials.first.id,
    );
    expect(changed.quantity, 10);
    expect(await repository.pendingChanges(), pendingBefore + 1);
  });
}
