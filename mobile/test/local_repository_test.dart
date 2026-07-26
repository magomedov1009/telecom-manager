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
    expect(summary.pendingChanges, 10);
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

  test('all manual inventory operations preserve stock mathematics', () async {
    final warehouse = (await repository.warehouses()).first;
    final material = (await repository.materials()).first;
    await repository.addReceipt(
      warehouseId: warehouse.id,
      materialId: material.id,
      quantity: 10,
    );
    await repository.addInventoryOperation(
      warehouseId: warehouse.id,
      materialId: material.id,
      operationType: 'ISSUE_TO_THIRD_PARTY',
      quantity: 2,
    );
    await repository.addInventoryOperation(
      warehouseId: warehouse.id,
      materialId: material.id,
      operationType: 'RETURN',
      quantity: 1,
    );
    await repository.addInventoryOperation(
      warehouseId: warehouse.id,
      materialId: material.id,
      operationType: 'WRITE_OFF',
      quantity: 3,
      comment: 'Повреждённый кабель',
    );
    await repository.addInventoryOperation(
      warehouseId: warehouse.id,
      materialId: material.id,
      operationType: 'ADJUSTMENT',
      quantity: 4,
      adjustmentDirection: 'plus',
    );
    await repository.addInventoryOperation(
      warehouseId: warehouse.id,
      materialId: material.id,
      operationType: 'ADJUSTMENT',
      quantity: 2,
      adjustmentDirection: 'minus',
    );

    final balance = (await repository.materialBalancesForWarehouse(
      warehouse.id,
    )).singleWhere((item) => item.materialId == material.id);
    expect(balance.quantity, 8);
    expect(
      (await repository.inventoryHistory())
          .map((item) => item.operationType)
          .toSet(),
      containsAll({
        'RECEIPT',
        'ISSUE_TO_THIRD_PARTY',
        'RETURN',
        'WRITE_OFF',
        'ADJUSTMENT',
      }),
    );
    final writeOffs = await repository.inventoryHistory(
      warehouseId: warehouse.id,
      materialId: material.id,
      operationType: 'WRITE_OFF',
      dateFrom: DateTime.now(),
      dateTo: DateTime.now(),
      search: 'повреждённый',
    );
    expect(writeOffs, hasLength(1));
    expect(writeOffs.single.quantity, -3);
    final itemType = (await repository.inventoryBalances())
        .singleWhere((item) => item.materialId == material.id)
        .itemType;
    expect(
      await repository.inventoryHistory(
        operationType: 'WRITE_OFF',
        itemType: itemType,
      ),
      hasLength(1),
    );
    expect(
      await repository.inventoryHistory(
        dateFrom: DateTime.now().add(const Duration(days: 1)),
      ),
      isEmpty,
    );
    expect(
      (await repository.reportSummary(
        dateFrom: DateTime.now(),
        dateTo: DateTime.now(),
      )).materialSpent,
      3,
    );
    final owner = (await repository.providers()).singleWhere(
      (item) => item.name == warehouse.name,
    );
    final inventoryReport = await repository.reportDetails(
      section: 'inventory',
      dateFrom: DateTime.now(),
      dateTo: DateTime.now(),
      providerId: owner.id,
      search: material.name,
    );
    expect(inventoryReport, hasLength(1));
    expect(inventoryReport.single.subtitle, contains('Приход: 15.00'));
    expect(inventoryReport.single.subtitle, contains('Расход: 7.00'));
    expect(inventoryReport.single.value, 8);
  });

  test(
    'negative manual inventory operation rolls back when stock is low',
    () async {
      final warehouse = (await repository.warehouses()).first;
      final material = (await repository.materials()).first;
      final before = await repository.pendingChanges();

      await expectLater(
        repository.addInventoryOperation(
          warehouseId: warehouse.id,
          materialId: material.id,
          operationType: 'WRITE_OFF',
          quantity: 1,
        ),
        throwsStateError,
      );

      expect(await repository.pendingChanges(), before);
      expect(await repository.inventoryHistory(), isEmpty);
    },
  );

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
    expect(await repository.connections(clientId: clientId), hasLength(1));
    expect(await repository.pendingChanges(), pendingBefore + 5);
  });

  test(
    'client search covers login contract address phone and provider',
    () async {
      final provider = (await repository.providers()).first;
      await repository.addClient(
        providerId: provider.id,
        contractNumber: 'CN-7788',
        login: 'needle-login',
        address: 'Улица Поисковая 10',
        phone: '+79991234567',
      );

      expect(await repository.clients(query: 'needle'), hasLength(1));
      expect(await repository.clients(query: '7788'), hasLength(1));
      expect(await repository.clients(query: 'поисковая'), hasLength(1));
      expect(await repository.clients(query: '999123'), hasLength(1));
      expect(await repository.clients(query: provider.name), hasLength(1));
      expect(await repository.clients(query: 'не существует'), isEmpty);
    },
  );

  test('editing client preserves history and queues comment changes', () async {
    final providers = await repository.providers();
    final warehouse = (await repository.warehouses()).first;
    final clientId = await repository.addClient(
      providerId: providers.first.id,
      contractNumber: 'EDIT-1',
      login: 'old-login',
      address: 'Старый адрес',
    );
    await repository.addConnection(
      clientId: clientId,
      warehouseId: warehouse.id,
      connectionType: 'WITHOUT_MATERIALS',
      connectionDate: DateTime(2026, 7, 27),
      price: 0,
      officeAmount: 0,
      installerAmount: 0,
      materials: const [],
    );
    final before = await repository.pendingChanges();

    await repository.updateClient(
      clientId: clientId,
      providerId: providers.last.id,
      contractNumber: 'EDIT-2',
      login: 'new-login',
      address: 'Новый адрес',
      phone: '+70000000000',
      comment: 'Позвонить заранее',
    );

    final client = (await repository.clients(query: 'заранее')).single;
    expect(client.id, clientId);
    expect(client.providerId, providers.last.id);
    expect(client.contractNumber, 'EDIT-2');
    expect(client.comment, 'Позвонить заранее');
    expect(client.connections, 1);
    expect(await repository.connections(clientId: clientId), hasLength(1));
    expect(await repository.pendingChanges(), before);
    final queued = (await repository.syncQueue()).singleWhere(
      (item) => item.entityType == 'client' && item.entityId == clientId,
    );
    expect(queued.payload['comment'], 'Позвонить заранее');
    expect(queued.version, 2);
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
      expect(
        (await repository.inventoryBalances(
          warehouseId: source.id,
        )).singleWhere((item) => item.materialId == material.id).quantity,
        6,
      );
      expect(
        (await repository.inventoryBalances(
          warehouseId: destination.id,
        )).singleWhere((item) => item.materialId == material.id).quantity,
        4,
      );

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
      expect(summary.installerAccrued, 1000);
      expect(summary.officeAccrued, 500);
      expect(summary.incomeTotal, 1500);
      expect(summary.expensesTotal, 0);
      expect(summary.profit, 1500);
      expect(summary.iOweOffice, 500);
      expect(summary.availableCash, 1500);

      await repository.addManualFinanceTransaction(
        transactionType: 'PAYMENT_TO_OFFICE',
        amount: 300,
        providerId: provider.id,
        comment: 'Оплата офиса',
      );
      summary = await repository.financeSummary();
      expect(summary.paidToOffice, 300);
      expect(summary.iOweOffice, 200);
      expect(summary.availableCash, 1200);
      expect((await repository.financeJournal()).length, 3);

      final today = DateTime.now();
      final period = await repository.financeSummary(
        providerId: provider.id,
        dateFrom: today,
        dateTo: today,
      );
      expect(period.customerReceived, 0);
      expect(period.paidToOffice, 300);
      expect(period.iOweOffice, 200);
      expect(period.availableCash, -300);
      final filteredJournal = await repository.financeJournal(
        providerId: provider.id,
        transactionType: 'PAYMENT_TO_OFFICE',
        dateFrom: today,
        dateTo: today,
        search: 'оплата',
      );
      expect(filteredJournal, hasLength(1));
      expect(filteredJournal.single.amount, -300);
    },
  );

  test('deleting connection restores stock and reverses finance', () async {
    final provider = (await repository.providers()).first;
    final warehouse = (await repository.warehouses()).first;
    final material = (await repository.materials()).first;
    await repository.addReceipt(
      warehouseId: warehouse.id,
      materialId: material.id,
      quantity: 5,
    );
    final clientId = await repository.addClient(
      providerId: provider.id,
      contractNumber: 'delete-1',
      login: 'delete-client',
      address: 'Удаление',
    );
    final connectionId = await repository.addConnection(
      clientId: clientId,
      warehouseId: warehouse.id,
      connectionType: 'NEW',
      connectionDate: DateTime(2026, 7, 26),
      price: 1000,
      officeAmount: 300,
      installerAmount: 700,
      materials: [
        ConnectionMaterialInput(materialId: material.id, quantity: 2),
      ],
    );
    expect(
      (await repository.materialBalancesForWarehouse(
        warehouse.id,
      )).singleWhere((item) => item.materialId == material.id).quantity,
      3,
    );
    expect((await repository.financeSummary()).customerReceived, 1000);

    await repository.deleteConnection(connectionId);

    expect(await repository.connections(), isEmpty);
    expect(
      (await repository.materialBalancesForWarehouse(
        warehouse.id,
      )).singleWhere((item) => item.materialId == material.id).quantity,
      5,
    );
    expect((await repository.financeSummary()).customerReceived, 0);
  });

  test(
    'editing connection atomically recalculates stock and finance',
    () async {
      final provider = (await repository.providers()).first;
      final warehouse = (await repository.warehouses()).first;
      final material = (await repository.materials()).first;
      await repository.addReceipt(
        warehouseId: warehouse.id,
        materialId: material.id,
        quantity: 5,
      );
      final clientId = await repository.addClient(
        providerId: provider.id,
        contractNumber: 'edit-1',
        login: 'edit-client',
        address: 'Редактирование',
      );
      final connectionId = await repository.addConnection(
        clientId: clientId,
        warehouseId: warehouse.id,
        connectionType: 'NEW',
        connectionDate: DateTime(2026, 7, 26),
        price: 1000,
        officeAmount: 300,
        installerAmount: 700,
        materials: [
          ConnectionMaterialInput(materialId: material.id, quantity: 2),
        ],
      );

      await repository.updateConnection(
        connectionId: connectionId,
        warehouseId: warehouse.id,
        connectionType: 'RECONNECT',
        connectionDate: DateTime(2026, 7, 27),
        price: 600,
        officeAmount: 100,
        installerAmount: 500,
        materials: [
          ConnectionMaterialInput(materialId: material.id, quantity: 1),
        ],
      );

      expect(
        (await repository.materialBalancesForWarehouse(
          warehouse.id,
        )).singleWhere((item) => item.materialId == material.id).quantity,
        4,
      );
      final finance = await repository.financeSummary();
      expect(finance.customerReceived, 600);
      expect(finance.officeAccrued, 100);
      expect(
        (await repository.connections()).single.connectionType,
        'RECONNECT',
      );
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
    expect(summary.expensesTotal, 500);
    expect(summary.profit, -500);
    expect((await repository.expenses()).single.description, 'Бензин');
  });

  test('deleting expense reverses installer debt and cash impact', () async {
    final provider = (await repository.providers()).first;
    await repository.addExpense(
      providerId: provider.id,
      category: 'fuel',
      description: 'Бензин',
      amount: 500,
      paidBy: 'INSTALLER',
      expenseDate: DateTime(2026, 7, 26),
    );
    final expense = (await repository.expenses()).single;

    await repository.deleteExpense(expense.id);

    final summary = await repository.financeSummary();
    expect(summary.officeOwesMe, 0);
    expect(summary.availableCash, 0);
    expect(await repository.expenses(), isEmpty);
  });

  test('editing expense atomically recalculates finance', () async {
    final provider = (await repository.providers()).first;
    await repository.addExpense(
      providerId: provider.id,
      category: 'fuel',
      description: 'Бензин',
      amount: 500,
      paidBy: 'INSTALLER',
      expenseDate: DateTime(2026, 7, 26),
    );
    final expense = (await repository.expenses()).single;

    await repository.updateExpense(
      expenseId: expense.id,
      providerId: provider.id,
      category: 'tools',
      description: 'Инструмент',
      amount: 300,
      paidBy: 'OFFICE',
      expenseDate: DateTime(2026, 7, 27),
    );

    final summary = await repository.financeSummary();
    expect(summary.officeOwesMe, 0);
    expect(summary.availableCash, 0);
    final changed = (await repository.expenses()).single;
    expect(changed.description, 'Инструмент');
    expect(changed.amount, 300);
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
      final summary = await repository.financeSummary();
      expect(summary.officeOwesMe, 700);
      expect(summary.extraWorkIncome, 700);
      expect(summary.incomeTotal, 700);
      expect(summary.profit, 700);
    },
  );

  test(
    'deleting extra work restores stock and reverses installer income',
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
      final work = (await repository.extraWorks()).single;

      await repository.deleteExtraWork(work.id);

      final balance = (await repository.materialBalancesForWarehouse(
        warehouse.id,
      )).singleWhere((item) => item.materialId == material.id);
      expect(balance.quantity, 8);
      expect((await repository.financeSummary()).officeOwesMe, 0);
      expect(await repository.extraWorks(), isEmpty);
    },
  );

  test('editing extra work atomically recalculates stock and income', () async {
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
    final work = (await repository.extraWorks()).single;

    await repository.updateExtraWork(
      extraWorkId: work.id,
      providerId: provider.id,
      workTypeId: workType.id,
      workDate: DateTime(2026, 7, 28),
      amount: 400,
      warehouseId: warehouse.id,
      materials: [
        ConnectionMaterialInput(materialId: material.id, quantity: 1),
      ],
    );

    final balance = (await repository.materialBalancesForWarehouse(
      warehouse.id,
    )).singleWhere((item) => item.materialId == material.id);
    expect(balance.quantity, 7);
    expect((await repository.financeSummary()).officeOwesMe, 400);
    expect((await repository.extraWorks()).single.amount, 400);
  });

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

  test(
    'provider and work type updates preserve history and active lists',
    () async {
      await repository.addProvider('Новый провайдер', description: 'Описание');
      var provider = (await repository.providerCatalog()).singleWhere(
        (item) => item.name == 'Новый провайдер',
      );
      await repository.updateProvider(
        providerId: provider.id,
        name: 'Обновлённый провайдер',
        description: 'Новое описание',
      );
      await repository.toggleProvider(provider.id);
      provider = (await repository.providerCatalog()).singleWhere(
        (item) => item.id == provider.id,
      );
      expect(provider.name, 'Обновлённый провайдер');
      expect(provider.description, 'Новое описание');
      expect(provider.isActive, isFalse);
      expect(
        (await repository.providers()).any((item) => item.id == provider.id),
        isFalse,
      );

      await repository.addExtraWorkType(
        name: 'Настройка',
        description: 'Первичное описание',
        defaultPrice: 100,
        defaultOfficeAmount: 20,
        requiresMaterials: true,
      );
      var workType = (await repository.extraWorkTypeCatalog()).singleWhere(
        (item) => item.name == 'Настройка',
      );
      await repository.updateExtraWorkType(
        workTypeId: workType.id,
        name: 'Точная настройка',
        description: 'Обновлено',
        defaultPrice: 200,
        defaultOfficeAmount: 50,
        requiresMaterials: false,
        requiresEquipment: true,
      );
      await repository.toggleExtraWorkType(workType.id);
      workType = (await repository.extraWorkTypeCatalog()).singleWhere(
        (item) => item.id == workType.id,
      );
      expect(workType.defaultPrice, 200);
      expect(workType.defaultOfficeAmount, 50);
      expect(workType.requiresEquipment, isTrue);
      expect(workType.isActive, isFalse);
      expect(
        (await repository.extraWorkTypes()).any(
          (item) => item.id == workType.id,
        ),
        isFalse,
      );
      final queued = await repository.syncQueue();
      expect(
        queued
            .singleWhere(
              (item) =>
                  item.entityType == 'provider' && item.entityId == provider.id,
            )
            .version,
        3,
      );
      expect(
        queued
            .singleWhere(
              (item) =>
                  item.entityType == 'extra_work_type' &&
                  item.entityId == workType.id,
            )
            .version,
        3,
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

  test('report period includes boundary dates and provider filter', () async {
    final provider = (await repository.providers()).first;
    final warehouse = (await repository.warehouses()).first;
    final workType = (await repository.extraWorkTypes()).first;
    final clientId = await repository.addClient(
      providerId: provider.id,
      contractNumber: '4001',
      login: 'report-client',
      address: 'Отчёт',
    );
    await repository.addConnection(
      clientId: clientId,
      warehouseId: warehouse.id,
      connectionType: 'WITHOUT_MATERIALS',
      connectionDate: DateTime(2026, 7, 1),
      price: 1500,
      officeAmount: 500,
      installerAmount: 1000,
      materials: const [],
    );
    await repository.addExtraWork(
      providerId: provider.id,
      workTypeId: workType.id,
      workDate: DateTime(2026, 7, 31),
      amount: 700,
    );
    await repository.addExpense(
      providerId: provider.id,
      category: 'fuel',
      description: 'Топливо',
      amount: 200,
      paidBy: 'OFFICE',
      expenseDate: DateTime(2026, 7, 31),
    );
    final report = await repository.reportSummary(
      dateFrom: DateTime(2026, 7, 1),
      dateTo: DateTime(2026, 7, 31),
      providerId: provider.id,
    );
    expect(report.connections, 1);
    expect(report.extraWorks, 1);
    expect(report.income, 2200);
    expect(report.expenses, 200);
    expect(report.profit, 2000);
    expect(
      await repository.reportDetails(
        section: 'connections',
        dateFrom: DateTime(2026, 7, 1),
        dateTo: DateTime(2026, 7, 31),
        providerId: provider.id,
        search: 'report-client',
      ),
      hasLength(1),
    );
    expect(
      await repository.reportDetails(
        section: 'connections',
        dateFrom: DateTime(2026, 7, 1),
        dateTo: DateTime(2026, 7, 31),
        search: 'нет такого клиента',
      ),
      isEmpty,
    );
    expect(
      await repository.reportDetails(
        section: 'expenses',
        dateFrom: DateTime(2026, 7, 1),
        dateTo: DateTime(2026, 7, 31),
        providerId: provider.id,
      ),
      hasLength(1),
    );
    expect(
      await repository.reportDetails(
        section: 'providers',
        dateFrom: DateTime(2026, 7, 1),
        dateTo: DateTime(2026, 7, 31),
        providerId: provider.id,
      ),
      hasLength(1),
    );
    expect(
      await repository.reportDetails(
        section: 'finance',
        dateFrom: DateTime(2026, 7, 1),
        dateTo: DateTime(2026, 7, 31),
        providerId: provider.id,
      ),
      hasLength(4),
    );
  });

  test('organizations isolate business data and users', () async {
    final originalId = await repository.organizationId;
    final newId = await repository.addOrganization('Другой город');
    expect(newId, isNot(originalId));
    expect((await repository.dashboardSummary()).providers, 0);
    expect((await repository.users()).single.role, 'admin');
    await repository.addProvider('Городской провайдер');
    expect((await repository.providers()).single.name, 'Городской провайдер');

    await repository.switchOrganization(originalId);
    expect((await repository.providers()).length, 2);
    expect((await repository.users()).single.username, 'admin');
    expect(await repository.authenticate('admin', 'wrong'), isNull);
    expect((await repository.authenticate('admin', '0000'))?.role, 'admin');
    await repository.addUser(
      username: 'installer1',
      fullName: 'Монтажник Один',
      role: 'installer',
      password: '1234',
    );
    expect(
      (await repository.authenticate('installer1', '1234'))?.role,
      'installer',
    );
    final installer = (await repository.users()).singleWhere(
      (user) => user.username == 'installer1',
    );
    await repository.authenticate('admin', '0000');
    await repository.toggleUser(installer.id);
    expect(await repository.authenticate('installer1', '1234'), isNull);
    await repository.toggleUser(installer.id);
    await repository.changeUserPassword(installer.id, '5678');
    expect(await repository.authenticate('installer1', '1234'), isNull);
    expect(
      (await repository.authenticate('installer1', '5678'))?.role,
      'installer',
    );
  });
}
