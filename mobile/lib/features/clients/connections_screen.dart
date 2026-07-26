import 'package:flutter/material.dart';
import '../../core/repositories/local_repository.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });
  final LocalRepository repository;
  final VoidCallback onChanged;
  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late Future<List<ConnectionListItem>> data;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() => data = widget.repository.connections());
  static const labels = {
    'NEW': 'Новое подключение',
    'RECONNECT': 'Переподключение',
    'ONU_REPLACE': 'Замена ONU',
    'CABLE_REPLACE': 'Замена кабеля',
    'WITHOUT_MATERIALS': 'Без материалов',
    'CUSTOM': 'Другое',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подключения')),
    body: FutureBuilder<List<ConnectionListItem>>(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('Подключений пока нет'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = snapshot.data![index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.router_outlined)),
                title: Text(item.clientLogin),
                subtitle: Text(
                  '${item.providerName} · ${labels[item.connectionType] ?? item.connectionType}\n${item.address}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'edit') {
                      final saved = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => _EditConnectionSheet(
                          repository: widget.repository,
                          item: item,
                        ),
                      );
                      if (saved == true) {
                        widget.onChanged();
                        reload();
                      }
                    } else {
                      await remove(item);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Изменить')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> remove(ConnectionListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подключение?'),
        content: const Text(
          'Материалы вернутся на склад, финансовые начисления будут отменены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.repository.deleteConnection(item.id);
      widget.onChanged();
      reload();
    }
  }
}

class _EditConnectionSheet extends StatefulWidget {
  const _EditConnectionSheet({required this.repository, required this.item});
  final LocalRepository repository;
  final ConnectionListItem item;
  @override
  State<_EditConnectionSheet> createState() => _EditConnectionSheetState();
}

class _EditConnectionSheetState extends State<_EditConnectionSheet> {
  final price = TextEditingController();
  final office = TextEditingController();
  final installer = TextEditingController();
  final comment = TextEditingController();
  final quantities = <String, TextEditingController>{};
  late Future<(ConnectionEditData, List<LookupItem>, List<LookupItem>)> data;
  String? warehouseId;
  String connectionType = 'NEW';
  DateTime connectionDate = DateTime.now();
  bool initialized = false, saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    data =
        Future.wait([
          widget.repository.connectionEditData(widget.item.id),
          widget.repository.warehouses(),
          widget.repository.materials(),
        ]).then(
          (items) => (
            items[0] as ConnectionEditData,
            items[1] as List<LookupItem>,
            items[2] as List<LookupItem>,
          ),
        );
  }

  @override
  void dispose() {
    price.dispose();
    office.dispose();
    installer.dispose();
    comment.dispose();
    for (final controller in quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void initialize(ConnectionEditData current, List<LookupItem> materials) {
    if (initialized) return;
    initialized = true;
    warehouseId = current.warehouseId;
    connectionType = current.connectionType;
    connectionDate = current.connectionDate;
    price.text = '${current.price}';
    office.text = '${current.officeAmount}';
    installer.text = '${current.installerAmount}';
    comment.text = current.comment ?? '';
    for (final material in materials) {
      quantities[material.id] = TextEditingController(
        text: current.materials[material.id] == null
            ? ''
            : '${current.materials[material.id]}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: FutureBuilder<(ConnectionEditData, List<LookupItem>, List<LookupItem>)>(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        initialize(snapshot.data!.$1, snapshot.data!.$3);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Изменить подключение',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: connectionType,
                decoration: const InputDecoration(
                  labelText: 'Тип',
                  border: OutlineInputBorder(),
                ),
                items:
                    const {
                          'NEW': 'Новое подключение',
                          'RECONNECT': 'Переподключение',
                          'ONU_REPLACE': 'Замена ONU',
                          'CABLE_REPLACE': 'Замена кабеля',
                          'WITHOUT_MATERIALS': 'Без материалов',
                          'CUSTOM': 'Другое',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() => connectionType = v!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: warehouseId,
                decoration: const InputDecoration(
                  labelText: 'Склад',
                  border: OutlineInputBorder(),
                ),
                items: snapshot.data!.$2
                    .map(
                      (e) => DropdownMenuItem(value: e.id, child: Text(e.name)),
                    )
                    .toList(),
                onChanged: (v) => warehouseId = v,
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Дата подключения'),
                subtitle: Text(
                  '${connectionDate.day}.${connectionDate.month}.${connectionDate.year}',
                ),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: connectionDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null) {
                    setState(() => connectionDate = selected);
                  }
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _number(price, 'Стоимость')),
                  const SizedBox(width: 6),
                  Expanded(child: _number(office, 'Офис')),
                  const SizedBox(width: 6),
                  Expanded(child: _number(installer, 'Монтажник')),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Материалы',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...snapshot.data!.$3.map(
                (material) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _number(quantities[material.id]!, material.name),
                ),
              ),
              TextField(
                controller: comment,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Сохранение…' : 'Сохранить изменения'),
              ),
            ],
          ),
        );
      },
    ),
  );

  TextField _number(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );
  double parse(String value) =>
      double.tryParse(value.replaceAll(',', '.')) ?? 0;

  Future<void> save() async {
    if (warehouseId == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.updateConnection(
        connectionId: widget.item.id,
        warehouseId: warehouseId!,
        connectionType: connectionType,
        connectionDate: connectionDate,
        price: parse(price.text),
        officeAmount: parse(office.text),
        installerAmount: parse(installer.text),
        materials: quantities.entries
            .map(
              (e) => ConnectionMaterialInput(
                materialId: e.key,
                quantity: parse(e.value.text),
              ),
            )
            .where((e) => e.quantity > 0)
            .toList(),
        comment: comment.text,
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
