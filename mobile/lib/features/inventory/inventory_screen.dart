import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

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
        label: const Text('Приход'),
      ),
    );
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
  bool saving = false;

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
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Добавить приход',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
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
                        await widget.repository.addReceipt(
                          warehouseId: warehouseId!,
                          materialId: materialId!,
                          quantity: value,
                          comment: commentController.text,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      },
                child: Text(saving ? 'Сохранение…' : 'Сохранить локально'),
              ),
            ],
          );
        },
      ),
    );
  }
}
