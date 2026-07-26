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
    expect(summary.pendingChanges, 9);
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
    expect(await repository.pendingChanges(), pendingBefore + 5);
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

  test(
    'warehouse transfers create debt and reverse transfer offsets it',
    () async {
      final warehouses = await repository.warehouses();
      final material = (await repository.materials()).first;
      final source = warehouses.first;
      final destination = warehouses.last;
      await repository.addReceipt(
        warehouseId: source.id,
        materialId: material.id,
        quantity: 10,
      );

      await repository.addTransfer(
        sourceWarehouseId: source.id,
        destinationWarehouseId: destination.id,
        materialId: material.id,
        quantity: 6,
      );
      await repository.addTransfer(
        sourceWarehouseId: destination.id,
        destinationWarehouseId: source.id,
        materialId: material.id,
        quantity: 2,
      );

      final debt = (await repository.materialSettlements()).single;
      expect(debt.quantity, 4);
      expect(debt.materialName, material.name);

      await repository.addTransfer(
        sourceWarehouseId: destination.id,
        destinationWarehouseId: source.id,
        materialId: material.id,
        quantity: 4,
      );
      expect(await repository.materialSettlements(), isEmpty);
    },
  );

  test(
    'connection with another provider warehouse creates material debt',
    () async {
      final providers = await repository.providers();
      final warehouses = await repository.warehouses();
      final material = (await repository.materials()).first;
      final warehouse = warehouses.first;
      final clientProvider = providers.singleWhere(
        (item) => item.name != warehouse.name,
      );
      await repository.addReceipt(
        warehouseId: warehouse.id,
        materialId: material.id,
        quantity: 5,
      );
      final clientId = await repository.addClient(
        providerId: clientProvider.id,
        contractNumber: '2001',
        login: 'foreign-provider-client',
        address: 'Адрес другого провайдера',
      );

      await repository.addConnection(
        clientId: clientId,
        warehouseId: warehouse.id,
        connectionType: 'NEW',
        connectionDate: DateTime(2026, 7, 26),
        price: 0,
        officeAmount: 0,
        installerAmount: 0,
        materials: [
          ConnectionMaterialInput(materialId: material.id, quantity: 2),
        ],
      );

      final debt = (await repository.materialSettlements()).single;
      expect(debt.creditorName, warehouse.name);
      expect(debt.debtorName, clientProvider.name);
      expect(debt.quantity, 2);
    },
  );

  test(
    'finance debt follows website connection and office payment formula',
    () async {
      final provider = (await repository.providers()).first;
      final warehouse = (await repository.warehouses()).first;
      final clientId = await repository.addClient(
        providerId: provider.id,
        contractNumber: '3001',
        login: 'finance-client',
        address: 'Финансовый тест',
      );
      await repository.addConnection(
        clientId: clientId,
        warehouseId: warehouse.id,
        connectionType: 'WITHOUT_MATERIALS',
        connectionDate: DateTime(2026, 7, 26),
        price: 1500,
        officeAmount: 500,
        installerAmount: 1000,
        materials: const [],
      );

      var summary = await repository.financeSummary();
      expect(summary.customerReceived, 1500);
      expect(summary.officeAccrued, 500);
      expect(summary.iOweOffice, 500);
      expect(summary.availableCash, 1500);

      await repository.addManualFinanceTransaction(
        transactionType: 'PAYMENT_TO_OFFICE',
        amount: 300,
        providerId: provider.id,
      );
      summary = await repository.financeSummary();
      expect(summary.paidToOffice, 300);
      expect(summary.iOweOffice, 200);
      expect(summary.availableCash, 1200);
      expect((await repository.financeJournal()).length, 3);
    },
  );

  test('installer expense increases office debt and reduces cash', () async {
    final provider = (await repository.providers()).first;
    await repository.addExpense(
      providerId: provider.id,
      category: 'fuel',
      description: 'Бензин',
      amount: 500,
      paidBy: 'INSTALLER',
      expenseDate: DateTime(2026, 7, 26),
    );

    final summary = await repository.financeSummary();
    expect(summary.officeOwesMe, 500);
    expect(summary.availableCash, -500);
    expect((await repository.expenses()).single.description, 'Бензин');
  });

  test(
    'extra work atomically writes off stock and accrues installer income',
    () async {
      final provider = (await repository.providers()).first;
      final warehouse = (await repository.warehouses()).first;
      final material = (await repository.materials()).first;
      final workType = (await repository.extraWorkTypes()).first;
      await repository.addReceipt(
        warehouseId: warehouse.id,
        materialId: material.id,
        quantity: 8,
      );

      await repository.addExtraWork(
        providerId: provider.id,
        workTypeId: workType.id,
        workDate: DateTime(2026, 7, 27),
        amount: 700,
        warehouseId: warehouse.id,
        materials: [
          ConnectionMaterialInput(materialId: material.id, quantity: 3),
        ],
      );

      final balance = (await repository.materialBalancesForWarehouse(
        warehouse.id,
      )).singleWhere((item) => item.materialId == material.id);
      expect(balance.quantity, 5);
      expect((await repository.extraWorks()).single.amount, 700);
      expect((await repository.financeSummary()).officeOwesMe, 700);
    },
  );

  test(
    'catalog additions are queued and duplicate names are rejected',
    () async {
      final before = await repository.pendingChanges();
      await repository.addProvider('Новый провайдер');
      expect(
        (await repository.providers()).any(
          (item) => item.name == 'Новый провайдер',
        ),
        isTrue,
      );
      expect(await repository.pendingChanges(), before + 1);
      await expectLater(
        repository.addProvider('Новый провайдер'),
        throwsArgumentError,
      );
    },
  );

  test('inventory history contains receipts and transfers', () async {
    final warehouses = await repository.warehouses();
    final material = (await repository.materials()).first;
    await repository.addReceipt(
      warehouseId: warehouses.first.id,
      materialId: material.id,
      quantity: 4,
    );
    await repository.addTransfer(
      sourceWarehouseId: warehouses.first.id,
      destinationWarehouseId: warehouses.last.id,
      materialId: material.id,
      quantity: 1,
    );
    expect(await repository.inventoryHistory(), hasLength(3));
  });
}
