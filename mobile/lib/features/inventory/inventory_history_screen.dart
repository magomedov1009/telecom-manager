import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class InventoryHistoryScreen extends StatefulWidget {
  const InventoryHistoryScreen({super.key, required this.repository});

  final LocalRepository repository;

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  late Future<List<InventoryHistoryItem>> history;
  late Future<(List<LookupItem>, List<LookupItem>)> options;
  String? warehouseId;
  String? materialId;
  String? operationType;

  static const operationLabels = {
    'RECEIPT': 'Приход',
    'CONNECTION': 'Подключение',
    'TRANSFER_IN': 'Перемещение: приход',
    'TRANSFER_OUT': 'Перемещение: расход',
    'RETURN': 'Возврат',
    'ISSUE_TO_THIRD_PARTY': 'Выдача третьему лицу',
    'WRITE_OFF': 'Списание',
    'ADJUSTMENT': 'Корректировка',
  };

  @override
  void initState() {
    super.initState();
    options = Future.wait([
      widget.repository.warehouses(),
      widget.repository.materials(),
    ]).then((rows) => (rows[0], rows[1]));
    reload();
  }

  void reload() {
    setState(
      () => history = widget.repository.inventoryHistory(
        warehouseId: warehouseId,
        materialId: materialId,
        operationType: operationType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('История склада')),
    body: Column(
      children: [
        FutureBuilder<(List<LookupItem>, List<LookupItem>)>(
          future: options,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filter(
                    label: 'Склад',
                    value: warehouseId,
                    items: snapshot.data!.$1,
                    onChanged: (value) {
                      warehouseId = value;
                      reload();
                    },
                  ),
                  _filter(
                    label: 'Позиция',
                    value: materialId,
                    items: snapshot.data!.$2,
                    onChanged: (value) {
                      materialId = value;
                      reload();
                    },
                  ),
                  _filter(
                    label: 'Операция',
                    value: operationType,
                    items: operationLabels.entries
                        .map((item) => LookupItem(item.key, item.value))
                        .toList(),
                    onChanged: (value) {
                      operationType = value;
                      reload();
                    },
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: FutureBuilder<List<InventoryHistoryItem>>(
            future: history,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(child: Text('Операции не найдены'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = snapshot.data![index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          item.quantity > 0
                              ? Icons.south_west
                              : Icons.north_east,
                        ),
                      ),
                      title: Text(item.materialName),
                      subtitle: Text(
                        '${item.warehouseName} · '
                        '${operationLabels[item.operationType] ?? item.operationType}'
                        '${item.comment?.isNotEmpty == true ? '\n${item.comment}' : ''}',
                      ),
                      isThreeLine: item.comment?.isNotEmpty == true,
                      trailing: Text(
                        '${item.quantity > 0 ? '+' : ''}${item.quantity}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: item.quantity > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _filter({
    required String label,
    required String? value,
    required List<LookupItem> items,
    required ValueChanged<String?> onChanged,
  }) => SizedBox(
    width: 180,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Все')),
        ...items.map(
          (item) => DropdownMenuItem(value: item.id, child: Text(item.name)),
        ),
      ],
      onChanged: onChanged,
    ),
  );
}
