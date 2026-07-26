import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final LocalRepository repository;
  final VoidCallback onChanged;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late Future<(FinanceSummary, List<FinanceJournalItem>)> data;
  String? providerId;
  String? transactionType;
  DateTime? dateFrom;
  DateTime? dateTo;
  final search = TextEditingController();

  static const labels = {
    'CONNECTION': 'Подключение',
    'EXTRA_WORK': 'Допработа',
    'EXPENSE': 'Расход',
    'PAYMENT_TO_OFFICE': 'Передача в офис',
    'PAYMENT_FROM_OFFICE': 'Выплата офисом',
    'ADJUSTMENT': 'Корректировка',
  };

  @override
  void initState() {
    super.initState();
    reload(notify: false);
  }

  void reload({bool notify = true}) {
    setState(() {
      data =
          Future.wait([
            widget.repository.financeSummary(
              providerId: providerId,
              dateFrom: dateFrom,
              dateTo: dateTo,
            ),
            widget.repository.financeJournal(
              providerId: providerId,
              transactionType: transactionType,
              dateFrom: dateFrom,
              dateTo: dateTo,
              search: search.text,
            ),
          ]).then((items) {
            return (
              items[0] as FinanceSummary,
              items[1] as List<FinanceJournalItem>,
            );
          });
    });
    if (notify) widget.onChanged();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> showFilters() async {
    final providers = await widget.repository.providers();
    if (!mounted) return;
    var selectedProvider = providerId;
    var selectedType = transactionType;
    var selectedFrom = dateFrom;
    var selectedTo = dateTo;
    final searchController = TextEditingController(text: search.text);
    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickDate(bool from) async {
            final value = await showDatePicker(
              context: context,
              initialDate: from
                  ? (selectedFrom ?? selectedTo ?? DateTime.now())
                  : (selectedTo ?? selectedFrom ?? DateTime.now()),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (value == null) return;
            setDialogState(() {
              if (from) {
                selectedFrom = value;
                if (selectedTo != null && value.isAfter(selectedTo!)) {
                  selectedTo = value;
                }
              } else {
                selectedTo = value;
                if (selectedFrom != null && value.isBefore(selectedFrom!)) {
                  selectedFrom = value;
                }
              }
            });
          }

          String date(DateTime? value) => value == null
              ? 'Не выбрана'
              : '${value.day}.${value.month}.${value.year}';
          return AlertDialog(
            title: const Text('Фильтры финансов'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Поиск в журнале',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedProvider,
                    decoration: const InputDecoration(
                      labelText: 'Провайдер',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Все')),
                      ...providers.map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => selectedProvider = value,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Тип операции',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Все')),
                      ...labels.entries.map(
                        (item) => DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                      ),
                    ],
                    onChanged: (value) => selectedType = value,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Дата начала'),
                    subtitle: Text(date(selectedFrom)),
                    trailing: const Icon(Icons.date_range_outlined),
                    onTap: () => pickDate(true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Дата окончания'),
                    subtitle: Text(date(selectedTo)),
                    trailing: const Icon(Icons.event_outlined),
                    onTap: () => pickDate(false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  searchController.clear();
                  selectedProvider = null;
                  selectedType = null;
                  selectedFrom = null;
                  selectedTo = null;
                  Navigator.pop(context, true);
                },
                child: const Text('Сбросить'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Применить'),
              ),
            ],
          );
        },
      ),
    );
    if (applied == true) {
      providerId = selectedProvider;
      transactionType = selectedType;
      dateFrom = selectedFrom;
      dateTo = selectedTo;
      search.text = searchController.text;
      reload(notify: false);
    }
    searchController.dispose();
  }

  String money(double value) =>
      '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} ₽';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Финансы',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Фильтры',
            onPressed: showFilters,
            icon: const Icon(Icons.filter_alt_outlined),
          ),
        ],
      ),
      body: FutureBuilder<(FinanceSummary, List<FinanceJournalItem>)>(
        future: data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.data!.$1;
          final journal = snapshot.data!.$2;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              Card(
                color: summary.balance >= 0
                    ? const Color(0xFFECFDF3)
                    : const Color(0xFFFFF1F0),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.balance >= 0
                            ? 'Офис должен мне'
                            : 'Я должен офису',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        money(
                          summary.balance >= 0
                              ? summary.officeOwesMe
                              : summary.iOweOffice,
                        ),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (providerId != null ||
                  transactionType != null ||
                  dateFrom != null ||
                  dateTo != null ||
                  search.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.filter_alt_outlined),
                    title: const Text('Фильтры применены'),
                    subtitle: Text(
                      [
                        if (dateFrom != null)
                          'с ${dateFrom!.day}.${dateFrom!.month}.${dateFrom!.year}',
                        if (dateTo != null)
                          'по ${dateTo!.day}.${dateTo!.month}.${dateTo!.year}',
                        if (transactionType != null)
                          labels[transactionType] ?? transactionType!,
                        if (search.text.isNotEmpty) '«${search.text}»',
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: 'Изменить',
                      onPressed: showFilters,
                      icon: const Icon(Icons.tune),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.45,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  _FinanceMetric(
                    label: 'Получено от клиентов',
                    value: money(summary.customerReceived),
                  ),
                  _FinanceMetric(
                    label: 'Начислено офису',
                    value: money(summary.officeAccrued),
                  ),
                  _FinanceMetric(
                    label: 'Начислено монтажнику',
                    value: money(summary.installerAccrued),
                  ),
                  _FinanceMetric(
                    label: 'Доход от допработ',
                    value: money(summary.extraWorkIncome),
                  ),
                  _FinanceMetric(
                    label: 'Общий доход',
                    value: money(summary.incomeTotal),
                  ),
                  _FinanceMetric(
                    label: 'Расходы',
                    value: money(summary.expensesTotal),
                  ),
                  _FinanceMetric(
                    label: 'Чистая прибыль',
                    value: money(summary.profit),
                  ),
                  _FinanceMetric(
                    label: 'Передано в офис',
                    value: money(summary.paidToOffice),
                  ),
                  _FinanceMetric(
                    label: 'Доступно наличных',
                    value: money(summary.availableCash),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Журнал операций',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (journal.isEmpty)
                const Card(child: ListTile(title: Text('Операций пока нет'))),
              ...journal.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          item.amount < 0 ? Icons.north_east : Icons.south_west,
                        ),
                      ),
                      title: Text(labels[item.type] ?? item.type),
                      subtitle: Text(
                        [
                          if (item.providerName != null) item.providerName!,
                          if (item.comment != null) item.comment!,
                        ].join(' · '),
                      ),
                      trailing: Text(
                        money(item.amount.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: item.amount < 0
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) =>
                _FinanceOperationSheet(repository: widget.repository),
          );
          if (saved == true) reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Операция'),
      ),
    );
  }
}

class _FinanceMetric extends StatelessWidget {
  const _FinanceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54)),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceOperationSheet extends StatefulWidget {
  const _FinanceOperationSheet({required this.repository});

  final LocalRepository repository;

  @override
  State<_FinanceOperationSheet> createState() => _FinanceOperationSheetState();
}

class _FinanceOperationSheetState extends State<_FinanceOperationSheet> {
  final amount = TextEditingController();
  final comment = TextEditingController();
  late Future<List<LookupItem>> providers;
  String type = 'PAYMENT_TO_OFFICE';
  String? providerId;
  bool saving = false;
  String? error;

  static const types = {
    'PAYMENT_TO_OFFICE': 'Передал деньги в офис',
    'PAYMENT_FROM_OFFICE': 'Офис выплатил мне',
    'ADJUSTMENT': 'Корректировка долга',
  };

  @override
  void initState() {
    super.initState();
    providers = widget.repository.providers();
  }

  @override
  void dispose() {
    amount.dispose();
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Финансовая операция',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(
                labelText: 'Тип операции',
                border: OutlineInputBorder(),
              ),
              items: types.entries
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.key,
                      child: Text(item.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => type = value!,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<LookupItem>>(
              future: providers,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return DropdownButtonFormField<String?>(
                  initialValue: providerId,
                  decoration: const InputDecoration(
                    labelText: 'Провайдер (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Без провайдера'),
                    ),
                    ...snapshot.data!.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => providerId = value,
                );
              },
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            TextField(
              controller: comment,
              decoration: const InputDecoration(
                labelText: 'Комментарий',
                border: OutlineInputBorder(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Сохранение…' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> save() async {
    final value = double.tryParse(amount.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => error = 'Введите сумму больше нуля');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.addManualFinanceTransaction(
        transactionType: type,
        amount: value,
        providerId: providerId,
        comment: comment.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      setState(() {
        saving = false;
        error = exception.toString();
      });
    }
  }
}
