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

  test('connection writes off material and queues related records', () async {
    final provider = (await repository.providers()).first;
    final warehouse = (await repository.warehouses()).first;
    final material = (await repository.materials()).first;
    await repository.addReceipt(
      warehouseId: warehouse.id,
      materialId: material.id,
      quantity: 10,
    );
    final clientId = await repository.addClient(
      providerId: provider.id,
      contractNumber: '1001',
      login: 'client-1001',
      address: 'Тестовый адрес',
    );
    final pendingBefore = await repository.pendingChanges();

    await repository.addConnection(
      clientId: clientId,
      warehouseId: warehouse.id,
      connectionType: 'NEW',
      connectionDate: DateTime(2026, 7, 26),
      price: 1500,
      officeAmount: 500,
      installerAmount: 1000,
      materials: [
        ConnectionMaterialInput(materialId: material.id, quantity: 3),
      ],
    );

    final balance = (await repository.materialBalancesForWarehouse(
      warehouse.id,
    )).singleWhere((item) => item.materialId == material.id);
    final client = (await repository.clients()).single;
    expect(balance.quantity, 7);
    expect(client.connections, 1);
    expect(await repository.pendingChanges(), pendingBefore + 3);
  });

  test('insufficient stock rolls back the whole connection', () async {
    final provider = (await repository.providers()).first;
    final warehouse = (await repository.warehouses()).first;
    final material = (await repository.materials()).first;
    final clientId = await repository.addClient(
      providerId: provider.id,
      contractNumber: '1002',
      login: 'client-1002',
      address: 'Другой адрес',
    );
    final pendingBefore = await repository.pendingChanges();

    await expectLater(
      repository.addConnection(
        clientId: clientId,
        warehouseId: warehouse.id,
        connectionType: 'NEW',
        connectionDate: DateTime(2026, 7, 26),
        price: 1000,
        officeAmount: 0,
        installerAmount: 1000,
        materials: [
          ConnectionMaterialInput(materialId: material.id, quantity: 1),
        ],
      ),
      throwsStateError,
    );

    expect((await repository.clients()).single.connections, 0);
    expect(await repository.pendingChanges(), pendingBefore);
  });
}
