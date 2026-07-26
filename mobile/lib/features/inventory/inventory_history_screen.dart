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
  String? itemType;
  DateTime? dateFrom;
  DateTime? dateTo;
  final search = TextEditingController();

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
        itemType: itemType,
        dateFrom: dateFrom,
        dateTo: dateTo,
        search: search.text,
      ),
    );
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> selectDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: from
          ? (dateFrom ?? dateTo ?? DateTime.now())
          : (dateTo ?? dateFrom ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (from) {
        dateFrom = selected;
        if (dateTo != null && selected.isAfter(dateTo!)) dateTo = selected;
      } else {
        dateTo = selected;
        if (dateFrom != null && selected.isBefore(dateFrom!)) {
          dateFrom = selected;
        }
      }
    });
    reload();
  }

  void resetFilters() {
    search.clear();
    warehouseId = null;
    materialId = null;
    operationType = null;
    itemType = null;
    dateFrom = null;
    dateTo = null;
    reload();
  }

  String shortDate(DateTime? value) => value == null
      ? 'не выбрана'
      : '${value.day.toString().padLeft(2, '0')}.'
            '${value.month.toString().padLeft(2, '0')}.${value.year}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('История склада'),
      actions: [
        IconButton(
          tooltip: 'Сбросить фильтры',
          onPressed: resetFilters,
          icon: const Icon(Icons.filter_alt_off_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: search,
            decoration: const InputDecoration(
              labelText: 'Поиск',
              hintText: 'Материал, склад или комментарий',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => reload(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => selectDate(from: true),
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text('С ${shortDate(dateFrom)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => selectDate(from: false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('По ${shortDate(dateTo)}'),
                ),
              ),
            ],
          ),
        ),
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
                  _filter(
                    label: 'Тип позиции',
                    value: itemType,
                    items: const [
                      LookupItem('MATERIAL', 'Материалы'),
                      LookupItem('EQUIPMENT', 'Оборудование'),
                    ],
                    onChanged: (value) {
                      itemType = value;
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
      key: ValueKey('$label-$value'),
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
