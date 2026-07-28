import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

const expenseCategories = {
  'fuel': 'Бензин',
  'tools': 'Инструмент',
  'materials': 'Материалы',
  'transport': 'Транспорт',
  'rent': 'Аренда',
  'other': 'Прочее',
};

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
  final search = TextEditingController();
  int tab = 0;
  String? providerId;
  String? category;
  DateTime? dateFrom;
  DateTime? dateTo;

  @override
  void initState() {
    super.initState();
    reload(notify: false);
  }

  void reload({bool notify = true}) {
    setState(() {
      data =
          Future.wait([
            widget.repository.extraWorks(
              search: search.text,
              providerId: providerId,
              dateFrom: dateFrom,
              dateTo: dateTo,
            ),
            widget.repository.expenses(
              search: search.text,
              category: category,
              dateFrom: dateFrom,
              dateTo: dateTo,
            ),
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
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<bool> confirmDelete(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: const Text(
              'Связанные начисления будут отменены. Списанные материалы вернутся на склад.',
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
        ) ??
        false;
  }

  Future<void> deleteExtraWork(ExtraWorkItem item) async {
    if (!await confirmDelete('Удалить дополнительную работу?')) return;
    try {
      await widget.repository.deleteExtraWork(item.id);
      if (!mounted) return;
      reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дополнительная работа удалена')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> deleteExpense(ExpenseItem item) async {
    if (!await confirmDelete('Удалить расход?')) return;
    try {
      await widget.repository.deleteExpense(item.id);
      if (!mounted) return;
      reload();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Расход удалён')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> editExtraWork(ExtraWorkItem item) async {
    try {
      final initial = await widget.repository.extraWorkEditData(item.id);
      if (!mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ExtraWorkSheet(
          repository: widget.repository,
          editId: item.id,
          initial: initial,
        ),
      );
      if (saved == true) reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> editExpense(ExpenseItem item) async {
    try {
      final initial = await widget.repository.expenseEditData(item.id);
      if (!mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ExpenseSheet(
          repository: widget.repository,
          editId: item.id,
          initial: initial,
        ),
      );
      if (saved == true) reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
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
              onSelectionChanged: (value) {
                setState(() => tab = value.first);
                reload(notify: false);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _filters(),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${item.amount.toStringAsFixed(0)} ₽',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Действия',
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    editExtraWork(item);
                                  }
                                  if (value == 'delete') {
                                    deleteExtraWork(item);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Редактировать'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Удалить'),
                                  ),
                                ],
                              ),
                            ],
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
                        title: Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.providerName} · ${item.paidBy == 'INSTALLER' ? 'Монтажник' : 'Офис'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${item.amount.toStringAsFixed(0)} ₽',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Действия',
                              onSelected: (value) {
                                if (value == 'edit') editExpense(item);
                                if (value == 'delete') deleteExpense(item);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Редактировать'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить'),
                                ),
                              ],
                            ),
                          ],
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

  Widget _filters() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Поиск и фильтры'),
    leading: const Icon(Icons.filter_alt_outlined),
    children: [
      TextField(
        controller: search,
        decoration: InputDecoration(
          labelText: 'Поиск',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            onPressed: () {
              search.clear();
              reload(notify: false);
            },
            icon: const Icon(Icons.clear),
          ),
        ),
        onSubmitted: (_) => reload(notify: false),
      ),
      const SizedBox(height: 8),
      if (tab == 0)
        FutureBuilder<List<LookupItem>>(
          future: widget.repository.providers(),
          builder: (context, snapshot) => DropdownButtonFormField<String?>(
            initialValue: providerId,
            decoration: const InputDecoration(labelText: 'Провайдер'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Все')),
              for (final item in snapshot.data ?? const <LookupItem>[])
                DropdownMenuItem<String?>(
                  value: item.id,
                  child: Text(item.name),
                ),
            ],
            onChanged: (value) => setState(() => providerId = value),
          ),
        )
      else
        DropdownButtonFormField<String?>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Категория'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Все')),
            for (final item in expenseCategories.entries)
              DropdownMenuItem<String?>(
                value: item.key,
                child: Text(item.value),
              ),
          ],
          onChanged: (value) => setState(() => category = value),
        ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _DateButton(
              label: 'С',
              value: dateFrom,
              onChanged: (value) => setState(() => dateFrom = value),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _DateButton(
              label: 'По',
              value: dateTo,
              onChanged: (value) => setState(() => dateTo = value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                search.clear();
                setState(() {
                  providerId = null;
                  category = null;
                  dateFrom = null;
                  dateTo = null;
                });
                reload(notify: false);
              },
              child: const Text('Сбросить'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => reload(notify: false),
              child: const Text('Применить'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );
}

class _ExtraWorkSheet extends StatefulWidget {
  const _ExtraWorkSheet({required this.repository, this.editId, this.initial});
  final LocalRepository repository;
  final String? editId;
  final ExtraWorkEditData? initial;
  @override
  State<_ExtraWorkSheet> createState() => _ExtraWorkSheetState();
}

class _ExtraWorkSheetState extends State<_ExtraWorkSheet> {
  final amount = TextEditingController();
  final comment = TextEditingController();
  final materialRows = <_MaterialDraft>[];
  String? providerId, typeId, warehouseId, error;
  late DateTime workDate;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    workDate = initial?.workDate ?? DateTime.now();
    if (initial == null) {
      materialRows.add(_MaterialDraft());
      return;
    }
    providerId = initial.providerId;
    typeId = initial.workTypeId;
    warehouseId = initial.warehouseId;
    amount.text = initial.amount.toString();
    materialRows.addAll(
      initial.materials.entries.map(
        (entry) => _MaterialDraft(
          materialId: entry.key,
          quantity: entry.value.toString(),
        ),
      ),
    );
    comment.text = initial.comment ?? '';
  }

  @override
  void dispose() {
    amount.dispose();
    comment.dispose();
    for (final row in materialRows) {
      row.dispose();
    }
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
                Text(
                  widget.editId == null
                      ? 'Новая допработа'
                      : 'Редактирование допработы',
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
                _DateButton(
                  label: 'Дата работы',
                  value: workDate,
                  onChanged: (value) => setState(() => workDate = value),
                ),
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
                for (var index = 0; index < materialRows.length; index++) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _lookup(
                          'Материал ${index + 1}',
                          materialRows[index].materialId,
                          materials,
                          (value) => materialRows[index].materialId = value,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _number(
                          materialRows[index].quantity,
                          'Количество',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Удалить строку',
                        onPressed: () => setState(() {
                          materialRows.removeAt(index).dispose();
                        }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => materialRows.add(_MaterialDraft())),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить материал'),
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
      final materials = [
        for (final row in materialRows)
          if (row.materialId != null && parse(row.quantity.text) > 0)
            ConnectionMaterialInput(
              materialId: row.materialId!,
              quantity: parse(row.quantity.text),
            ),
      ];
      if (widget.editId == null) {
        await widget.repository.addExtraWork(
          providerId: providerId!,
          workTypeId: typeId!,
          workDate: workDate,
          amount: parse(amount.text),
          warehouseId: materials.isNotEmpty ? warehouseId : null,
          materials: materials,
          comment: comment.text,
        );
      } else {
        await widget.repository.updateExtraWork(
          extraWorkId: widget.editId!,
          providerId: providerId!,
          workTypeId: typeId!,
          workDate: workDate,
          amount: parse(amount.text),
          warehouseId: materials.isNotEmpty ? warehouseId : null,
          materials: materials,
          comment: comment.text,
        );
      }
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

class _MaterialDraft {
  _MaterialDraft({this.materialId, String quantity = ''})
    : quantity = TextEditingController(text: quantity);

  String? materialId;
  final TextEditingController quantity;

  void dispose() => quantity.dispose();
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.repository, this.editId, this.initial});
  final LocalRepository repository;
  final String? editId;
  final ExpenseEditData? initial;
  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final description = TextEditingController(),
      amount = TextEditingController(),
      comment = TextEditingController();
  String? providerId, error;
  String category = 'other', paidBy = 'INSTALLER';
  late DateTime expenseDate;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    expenseDate = initial?.expenseDate ?? DateTime.now();
    if (initial == null) return;
    providerId = initial.providerId;
    category = initial.category;
    paidBy = initial.paidBy;
    description.text = initial.description;
    amount.text = initial.amount.toString();
    comment.text = initial.comment ?? '';
  }

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
              Text(
                widget.editId == null
                    ? 'Новый расход'
                    : 'Редактирование расхода',
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
              _DateButton(
                label: 'Дата расхода',
                value: expenseDate,
                onChanged: (value) => setState(() => expenseDate = value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                ),
                items: expenseCategories.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
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
      if (widget.editId == null) {
        await widget.repository.addExpense(
          providerId: providerId!,
          category: category,
          description: description.text,
          amount: value,
          paidBy: paidBy,
          expenseDate: expenseDate,
          comment: comment.text,
        );
      } else {
        await widget.repository.updateExpense(
          expenseId: widget.editId!,
          providerId: providerId!,
          category: category,
          description: description.text,
          amount: value,
          paidBy: paidBy,
          expenseDate: expenseDate,
          comment: comment.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString().replaceFirst('Invalid argument(s): ', '');
      });
    }
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final selected = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (selected != null) onChanged(selected);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(
        value == null
            ? 'Не выбрано'
            : '${value!.day.toString().padLeft(2, '0')}.'
                  '${value!.month.toString().padLeft(2, '0')}.${value!.year}',
      ),
    ),
  );
}
