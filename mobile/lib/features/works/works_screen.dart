import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class WorksScreen extends StatefulWidget {
  const WorksScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final LocalRepository repository;
  final VoidCallback onChanged;

  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends State<WorksScreen> {
  late Future<(List<ExtraWorkItem>, List<ExpenseItem>)> data;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    reload(notify: false);
  }

  void reload({bool notify = true}) {
    setState(() {
      data =
          Future.wait([
            widget.repository.extraWorks(),
            widget.repository.expenses(),
          ]).then(
            (items) => (
              items[0] as List<ExtraWorkItem>,
              items[1] as List<ExpenseItem>,
            ),
          );
    });
    if (notify) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Работы',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Допработы'),
                  icon: Icon(Icons.build_outlined),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Расходы'),
                  icon: Icon(Icons.receipt_long_outlined),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (value) => setState(() => tab = value.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<(List<ExtraWorkItem>, List<ExpenseItem>)>(
              future: data,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final count = tab == 0
                    ? snapshot.data!.$1.length
                    : snapshot.data!.$2.length;
                if (count == 0) {
                  return const Center(child: Text('Записей пока нет'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  itemCount: count,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (tab == 0) {
                      final item = snapshot.data!.$1[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.build_outlined),
                          ),
                          title: Text(item.typeName),
                          subtitle: Text(
                            '${item.providerName} · ${item.workDate.day}.${item.workDate.month}.${item.workDate.year}',
                          ),
                          trailing: Text(
                            '${item.amount.toStringAsFixed(0)} ₽',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      );
                    }
                    final item = snapshot.data!.$2[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long_outlined),
                        ),
                        title: Text(item.description),
                        subtitle: Text(
                          '${item.providerName} · ${item.paidBy == 'INSTALLER' ? 'Монтажник' : 'Офис'}',
                        ),
                        trailing: Text(
                          '${item.amount.toStringAsFixed(0)} ₽',
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => tab == 0
                ? _ExtraWorkSheet(repository: widget.repository)
                : _ExpenseSheet(repository: widget.repository),
          );
          if (saved == true) reload();
        },
        icon: const Icon(Icons.add),
        label: Text(tab == 0 ? 'Допработа' : 'Расход'),
      ),
    );
  }
}

class _ExtraWorkSheet extends StatefulWidget {
  const _ExtraWorkSheet({required this.repository});
  final LocalRepository repository;
  @override
  State<_ExtraWorkSheet> createState() => _ExtraWorkSheetState();
}

class _ExtraWorkSheetState extends State<_ExtraWorkSheet> {
  final amount = TextEditingController();
  final quantity = TextEditingController();
  final comment = TextEditingController();
  String? providerId, typeId, warehouseId, materialId, error;
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    quantity.dispose();
    comment.dispose();
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
      child: FutureBuilder<List<List<LookupItem>>>(
        future: Future.wait([
          widget.repository.providers(),
          widget.repository.extraWorkTypes(),
          widget.repository.warehouses(),
          widget.repository.materials(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final providers = snapshot.data![0],
              types = snapshot.data![1],
              warehouses = snapshot.data![2],
              materials = snapshot.data![3];
          providerId ??= providers.firstOrNull?.id;
          typeId ??= types.firstOrNull?.id;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Новая допработа',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                _lookup(
                  'Провайдер',
                  providerId,
                  providers,
                  (v) => providerId = v,
                ),
                const SizedBox(height: 10),
                _lookup('Вид работы', typeId, types, (v) => typeId = v),
                const SizedBox(height: 10),
                _number(amount, 'Стоимость, ₽'),
                const SizedBox(height: 16),
                const Text(
                  'Материал (необязательно)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _lookup(
                  'Склад',
                  warehouseId,
                  warehouses,
                  (v) => warehouseId = v,
                  optional: true,
                ),
                const SizedBox(height: 10),
                _lookup(
                  'Материал',
                  materialId,
                  materials,
                  (v) => materialId = v,
                  optional: true,
                ),
                const SizedBox(height: 10),
                _number(quantity, 'Количество'),
                const SizedBox(height: 10),
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
                  child: Text(saving ? 'Сохранение…' : 'Сохранить'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _lookup(
    String label,
    String? value,
    List<LookupItem> items,
    ValueChanged<String?> changed, {
    bool optional = false,
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      if (optional)
        const DropdownMenuItem(value: null, child: Text('Не использовать')),
      ...items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))),
    ],
    onChanged: changed,
  );
  Widget _number(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
  double parse(String value) =>
      double.tryParse(value.replaceAll(',', '.')) ?? 0;

  Future<void> save() async {
    if (providerId == null || typeId == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final qty = parse(quantity.text);
      await widget.repository.addExtraWork(
        providerId: providerId!,
        workTypeId: typeId!,
        workDate: DateTime.now(),
        amount: parse(amount.text),
        warehouseId: qty > 0 ? warehouseId : null,
        materials: qty > 0 && materialId != null
            ? [ConnectionMaterialInput(materialId: materialId!, quantity: qty)]
            : const [],
        comment: comment.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', '');
      });
    }
  }
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.repository});
  final LocalRepository repository;
  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final description = TextEditingController(),
      amount = TextEditingController(),
      comment = TextEditingController();
  String? providerId, error;
  String category = 'other', paidBy = 'INSTALLER';
  bool saving = false;
  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: FutureBuilder<List<LookupItem>>(
      future: widget.repository.providers(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        providerId ??= snapshot.data!.firstOrNull?.id;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Новый расход',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: providerId,
                decoration: const InputDecoration(
                  labelText: 'Провайдер',
                  border: OutlineInputBorder(),
                ),
                items: snapshot.data!
                    .map(
                      (e) => DropdownMenuItem(value: e.id, child: Text(e.name)),
                    )
                    .toList(),
                onChanged: (v) => providerId = v,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                ),
                items:
                    const {
                          'fuel': 'Бензин',
                          'tools': 'Инструмент',
                          'materials': 'Материалы',
                          'transport': 'Транспорт',
                          'rent': 'Аренда',
                          'other': 'Прочее',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: (v) => category = v!,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Сумма',
                  suffixText: '₽',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'INSTALLER', label: Text('Монтажник')),
                  ButtonSegment(value: 'OFFICE', label: Text('Офис')),
                ],
                selected: {paidBy},
                onSelectionChanged: (v) => setState(() => paidBy = v.first),
              ),
              const SizedBox(height: 10),
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
                child: Text(saving ? 'Сохранение…' : 'Сохранить'),
              ),
            ],
          ),
        );
      },
    ),
  );
  Future<void> save() async {
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (providerId == null || value == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.addExpense(
        providerId: providerId!,
        category: category,
        description: description.text,
        amount: value,
        paidBy: paidBy,
        expenseDate: DateTime.now(),
        comment: comment.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString().replaceFirst('Invalid argument(s): ', '');
      });
    }
  }
}
