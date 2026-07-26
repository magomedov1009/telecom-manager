import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repository});

  final LocalRepository repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String period = 'all';
  String? providerId;
  DateTime? dateFrom;
  DateTime? dateTo;
  late Future<List<LookupItem>> providers;
  late Future<DashboardSummary> summary;

  static const periodLabels = {
    'all': 'За всё время',
    'today': 'Сегодня',
    'yesterday': 'Вчера',
    'week': 'Эта неделя',
    'month': 'Этот месяц',
    'custom': 'Произвольный период',
  };

  @override
  void initState() {
    super.initState();
    providers = widget.repository.providers();
    refresh();
  }

  void refresh() {
    final range = resolvePeriod();
    summary = widget.repository.dashboardSummary(
      dateFrom: range.$1,
      dateTo: range.$2,
      providerId: providerId,
    );
  }

  (DateTime?, DateTime?) resolvePeriod() {
    final today = DateUtils.dateOnly(DateTime.now());
    switch (period) {
      case 'today':
        return (today, today);
      case 'yesterday':
        final day = today.subtract(const Duration(days: 1));
        return (day, day);
      case 'week':
        return (
          today.subtract(Duration(days: today.weekday - DateTime.monday)),
          today,
        );
      case 'month':
        return (DateTime(today.year, today.month), today);
      case 'custom':
        if (dateFrom == null || dateTo == null) return (today, today);
        return dateFrom!.isAfter(dateTo!)
            ? (dateTo, dateFrom)
            : (dateFrom, dateTo);
      default:
        return (null, null);
    }
  }

  void applyFilters() => setState(refresh);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardSummary>(
      future: summary,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Главный отчёт',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              '${data.organizationName} · ${periodLabels[period]}',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            _filters(),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFEFF4FF),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.smartphone)),
                title: const Text('Локальный режим'),
                subtitle: Text(
                  'Работает без интернета · ${data.pendingChanges} изменений '
                  'ожидают синхронизации',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _metricGrid(data),
            _sectionTitle('Взаиморасчёты'),
            Row(
              children: [
                Expanded(
                  child: _ValueCard(
                    label: 'Офис должен мне',
                    value: money(data.finance.officeOwesMe),
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ValueCard(
                    label: 'Я должен офису',
                    value: money(data.finance.iOweOffice),
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            _sectionTitle('Требует внимания'),
            if (data.attention.isEmpty)
              const Card(
                color: Color(0xFFE8F5E9),
                child: ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Всё в порядке'),
                ),
              )
            else
              ...data.attention.map(
                (warning) => Card(
                  color: const Color(0xFFFFF3E0),
                  child: ListTile(
                    leading: const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                    ),
                    title: Text(warning),
                  ),
                ),
              ),
            _sectionTitle('Дополнительные KPI'),
            _smallGrid([
              ('Средний чек', nullableMoney(data.averageCheck)),
              (
                'Средняя прибыль с подключения',
                nullableMoney(data.averageProfit),
              ),
              (
                'Средний расход на подключение',
                nullableMoney(data.averageExpense),
              ),
              (
                'Средний расход материалов',
                nullableNumber(data.averageMaterialSpent),
              ),
            ]),
            _stockSection(
              'Материалы',
              data.stock.where((item) => item.itemType == 'MATERIAL'),
            ),
            _stockSection(
              'Оборудование',
              data.stock.where((item) => item.itemType == 'EQUIPMENT'),
            ),
            _sectionTitle('Расходы'),
            _smallGrid([
              ('Общие расходы', money(data.finance.expensesTotal)),
              ('Монтажник', money(data.expensesInstaller)),
              ('Офис', money(data.expensesOffice)),
              ('Операций', '${data.expenseOperations}'),
            ]),
            Card(
              child: ListTile(
                title: const Text('Самая крупная статья расходов'),
                subtitle: Text(
                  data.topExpenseCategory == null
                      ? 'Нет расходов'
                      : '${expenseLabel(data.topExpenseCategory!)} — '
                            '${money(data.topExpenseAmount)}',
                ),
              ),
            ),
            _sectionTitle('Последние операции'),
            if (data.events.isEmpty)
              const Card(child: ListTile(title: Text('Операций нет')))
            else
              ...data.events.map(
                (event) => Card(
                  child: ListTile(
                    leading: Icon(
                      event.kind == 'finance'
                          ? Icons.payments_outlined
                          : Icons.inventory_2_outlined,
                    ),
                    title: Text(eventLabel(event.type)),
                    subtitle: Text(
                      '${event.title}\n${formatDate(event.occurredAt)}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      event.kind == 'finance'
                          ? money(event.amount)
                          : number(event.amount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _filters() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: period,
            decoration: const InputDecoration(labelText: 'Период'),
            items: periodLabels.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => period = value!),
          ),
          if (period == 'custom') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'С',
                    value: dateFrom,
                    onChanged: (value) => setState(() => dateFrom = value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateField(
                    label: 'По',
                    value: dateTo,
                    onChanged: (value) => setState(() => dateTo = value),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          FutureBuilder<List<LookupItem>>(
            future: providers,
            builder: (context, snapshot) => DropdownButtonFormField<String?>(
              initialValue: providerId,
              decoration: const InputDecoration(labelText: 'Провайдер'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Все'),
                ),
                for (final provider in snapshot.data ?? const <LookupItem>[])
                  DropdownMenuItem<String?>(
                    value: provider.id,
                    child: Text(provider.name),
                  ),
              ],
              onChanged: (value) => setState(() => providerId = value),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: applyFilters,
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Применить'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _metricGrid(DashboardSummary data) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    childAspectRatio: 1.45,
    children: [
      _MetricCard(label: 'Подключений', value: '${data.connections}'),
      _MetricCard(label: 'Новых клиентов', value: '${data.newClients}'),
      _MetricCard(label: 'Повторных', value: '${data.reconnects}'),
      _MetricCard(
        label: 'Замен оборудования',
        value: '${data.equipmentReplacements}',
      ),
      _MetricCard(
        label: 'Получено от клиентов',
        value: money(data.finance.customerReceived),
      ),
      _MetricCard(
        label: 'Доход монтажника',
        value: money(data.finance.installerAccrued),
      ),
      _MetricCard(
        label: 'Доход офиса',
        value: money(data.finance.officeAccrued),
      ),
      _MetricCard(label: 'Расходы', value: money(data.finance.expensesTotal)),
      _MetricCard(label: 'Чистая прибыль', value: money(data.finance.profit)),
      _MetricCard(label: 'Допработ', value: '${data.extraWorks}'),
      _MetricCard(label: 'Сумма допработ', value: money(data.extraWorkAmount)),
    ],
  );

  Widget _smallGrid(List<(String, String)> values) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    childAspectRatio: 1.8,
    children: [
      for (final item in values) _ValueCard(label: item.$1, value: item.$2),
    ],
  );

  Widget _stockSection(String title, Iterable<DashboardStockItem> items) {
    final rows = items.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        if (rows.isEmpty)
          const Card(child: ListTile(title: Text('Данные не найдены')))
        else
          ...rows.map(
            (item) => Card(
              child: ListTile(
                title: Text(item.name),
                subtitle: Text(
                  'Остаток: ${number(item.balance)} ${item.unitName}',
                ),
                trailing: Text(
                  'Расход\n${number(item.spent)} ${item.unitName}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
    ),
  );

  String number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
  String money(double value) => '${number(value)} ₽';
  String nullableMoney(double? value) => value == null ? '—' : money(value);
  String nullableNumber(double? value) => value == null ? '—' : number(value);

  String formatDate(DateTime value) {
    final date = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String expenseLabel(String value) =>
      const {
        'TRANSPORT': 'Транспорт',
        'MATERIALS': 'Материалы',
        'TOOLS': 'Инструменты',
        'COMMUNICATION': 'Связь',
        'OTHER': 'Другое',
      }[value] ??
      value;

  String eventLabel(String value) =>
      const {
        'CONNECTION': 'Подключение',
        'EXTRA_WORK': 'Дополнительная работа',
        'EXPENSE': 'Расход',
        'PAYMENT_FROM_OFFICE': 'Оплата от офиса',
        'PAYMENT_TO_OFFICE': 'Оплата офису',
        'ADJUSTMENT': 'Корректировка',
        'RECEIPT': 'Приход материалов',
        'TRANSFER_IN': 'Перемещение: приход',
        'TRANSFER_OUT': 'Перемещение: расход',
        'RETURN': 'Возврат',
        'ISSUE_TO_THIRD_PARTY': 'Выдача',
        'WRITE_OFF': 'Списание',
      }[value] ??
      value;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(
            value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
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
      decoration: InputDecoration(labelText: label),
      child: Text(
        value == null
            ? 'Выбрать'
            : '${value!.day.toString().padLeft(2, '0')}.'
                  '${value!.month.toString().padLeft(2, '0')}.${value!.year}',
      ),
    ),
  );
}
