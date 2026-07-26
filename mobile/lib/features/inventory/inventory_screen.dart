import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';
import 'settlements_screen.dart';
import 'inventory_history_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final LocalRepository repository;
  final VoidCallback onChanged;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<InventoryBalance>> balances;

  @override
  void initState() {
    super.initState();
    balances = widget.repository.inventoryBalances();
  }

  void reload() {
    setState(() => balances = widget.repository.inventoryBalances());
    widget.onChanged();
  }

  String quantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Склад',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'История операций',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    InventoryHistoryScreen(repository: widget.repository),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Переместить между складами',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () async {
              final saved = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _TransferSheet(repository: widget.repository),
              );
              if (saved == true) reload();
            },
          ),
          IconButton(
            tooltip: 'Долги провайдеров',
            icon: const Icon(Icons.balance_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    SettlementsScreen(repository: widget.repository),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<InventoryBalance>>(
        future: balances,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = snapshot.data![index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    child: Icon(
                      item.itemType == 'EQUIPMENT'
                          ? Icons.router_outlined
                          : Icons.cable_outlined,
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    item.itemType == 'EQUIPMENT' ? 'Оборудование' : 'Материал',
                  ),
                  trailing: Text(
                    '${quantity(item.quantity)} ${item.unitName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _ReceiptSheet(repository: widget.repository),
          );
          if (saved == true) reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Операция'),
      ),
    );
  }
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.repository});

  final LocalRepository repository;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final quantityController = TextEditingController();
  final commentController = TextEditingController();
  String? sourceId;
  String? destinationId;
  String? materialId;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    quantityController.dispose();
    commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: FutureBuilder<(List<LookupItem>, List<LookupItem>)>(
        future: Future.wait([
          widget.repository.warehouses(),
          widget.repository.materials(),
        ]).then((items) => (items[0], items[1])),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 250,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final warehouses = snapshot.data!.$1;
          final materials = snapshot.data!.$2;
          sourceId ??= warehouses.firstOrNull?.id;
          destinationId ??= warehouses.length > 1 ? warehouses[1].id : null;
          materialId ??= materials.firstOrNull?.id;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Перемещение',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                _warehouseField('Со склада', sourceId, warehouses, (value) {
                  sourceId = value;
                }),
                const SizedBox(height: 12),
                _warehouseField('На склад', destinationId, warehouses, (value) {
                  destinationId = value;
                }),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: materialId,
                  decoration: const InputDecoration(
                    labelText: 'Материал или оборудование',
                    border: OutlineInputBorder(),
                  ),
                  items: materials
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => materialId = value,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Количество',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    labelText: 'Комментарий',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(saving ? 'Перемещение…' : 'Переместить'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  DropdownButtonFormField<String> _warehouseField(
    String label,
    String? value,
    List<LookupItem> warehouses,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: warehouses
          .map(
            (item) => DropdownMenuItem(value: item.id, child: Text(item.name)),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Future<void> save() async {
    final value = double.tryParse(
      quantityController.text.trim().replaceAll(',', '.'),
    );
    if (sourceId == null ||
        destinationId == null ||
        materialId == null ||
        value == null ||
        value <= 0) {
      setState(() => error = 'Проверьте склады, позицию и количество');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.addTransfer(
        sourceWarehouseId: sourceId!,
        destinationWarehouseId: destinationId!,
        materialId: materialId!,
        quantity: value,
        comment: commentController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      setState(() {
        saving = false;
        error = exception
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', '');
      });
    }
  }
}

class _ReceiptSheet extends StatefulWidget {
  const _ReceiptSheet({required this.repository});
  final LocalRepository repository;

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  final quantityController = TextEditingController();
  final commentController = TextEditingController();
  String? warehouseId;
  String? materialId;
  String operation = 'RECEIPT';
  String adjustmentDirection = 'plus';
  bool saving = false;

  static const operations = {
    'RECEIPT': 'Приход',
    'ISSUE_TO_THIRD_PARTY': 'Выдача третьему лицу',
    'RETURN': 'Возврат',
    'WRITE_OFF': 'Списание',
    'ADJUSTMENT': 'Корректировка',
  };

  @override
  void dispose() {
    quantityController.dispose();
    commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: FutureBuilder<(List<LookupItem>, List<LookupItem>)>(
        future: Future.wait([
          widget.repository.warehouses(),
          widget.repository.materials(),
        ]).then((items) => (items[0], items[1])),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final warehouses = snapshot.data!.$1;
          final materials = snapshot.data!.$2;
          warehouseId ??= warehouses.firstOrNull?.id;
          materialId ??= materials.firstOrNull?.id;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Складская операция',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: operation,
                  decoration: const InputDecoration(
                    labelText: 'Операция',
                    border: OutlineInputBorder(),
                  ),
                  items: operations.entries
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => operation = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: warehouseId,
                  decoration: const InputDecoration(
                    labelText: 'Склад',
                    border: OutlineInputBorder(),
                  ),
                  items: warehouses
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => warehouseId = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: materialId,
                  decoration: const InputDecoration(
                    labelText: 'Позиция',
                    border: OutlineInputBorder(),
                  ),
                  items: materials
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => materialId = value,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Количество',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (operation == 'ADJUSTMENT') ...[
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'plus', label: Text('Добавить')),
                      ButtonSegment(value: 'minus', label: Text('Убавить')),
                    ],
                    selected: {adjustmentDirection},
                    onSelectionChanged: (value) =>
                        setState(() => adjustmentDirection = value.first),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    labelText: 'Комментарий',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final value = double.tryParse(
                            quantityController.text.replaceAll(',', '.'),
                          );
                          if (warehouseId == null ||
                              materialId == null ||
                              value == null ||
                              value <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Проверьте склад, позицию и количество',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() => saving = true);
                          try {
                            if (operation == 'RECEIPT') {
                              await widget.repository.addReceipt(
                                warehouseId: warehouseId!,
                                materialId: materialId!,
                                quantity: value,
                                comment: commentController.text,
                              );
                            } else {
                              await widget.repository.addInventoryOperation(
                                warehouseId: warehouseId!,
                                materialId: materialId!,
                                operationType: operation,
                                quantity: value,
                                adjustmentDirection: adjustmentDirection,
                                comment: commentController.text,
                              );
                            }
                          } catch (error) {
                            if (!context.mounted) return;
                            setState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error
                                      .toString()
                                      .replaceFirst('Bad state: ', '')
                                      .replaceFirst(
                                        'Invalid argument(s): ',
                                        '',
                                      ),
                                ),
                              ),
                            );
                            return;
                          }
                          if (context.mounted) Navigator.pop(context, true);
                        },
                  child: Text(saving ? 'Сохранение…' : 'Сохранить локально'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
