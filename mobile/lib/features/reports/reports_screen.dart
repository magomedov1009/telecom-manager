import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/repositories/local_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repository});

  final LocalRepository repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String period = 'month';
  String? providerId;
  DateTime? customFrom;
  DateTime? customTo;
  List<ProviderManagementReport>? lastReports;

  (DateTime?, DateTime?) dates() {
    final now = DateTime.now();
    return switch (period) {
      'today' => (
        DateTime(now.year, now.month, now.day),
        DateTime(now.year, now.month, now.day),
      ),
      'yesterday' => (
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 1)),
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 1)),
      ),
      'week' => (
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1)),
        DateTime(now.year, now.month, now.day),
      ),
      'month' => (
        DateTime(now.year, now.month),
        DateTime(now.year, now.month, now.day),
      ),
      'previous_month' => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
      ),
      'custom' => (customFrom, customTo),
      _ => (null, null),
    };
  }

  Future<List<ProviderManagementReport>> load() {
    final range = dates();
    return widget.repository.providerManagementReports(
      dateFrom: range.$1,
      dateTo: range.$2,
      providerId: providerId,
    );
  }

  String money(double value) => '${value.toStringAsFixed(2)} ₽';
  String quantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
  String shortDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  Future<void> selectCustomDate({required bool from}) async {
    final value = await showDatePicker(
      context: context,
      initialDate: from
          ? (customFrom ?? customTo ?? DateTime.now())
          : (customTo ?? customFrom ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    setState(() {
      if (from) {
        customFrom = value;
        if (customTo != null && value.isAfter(customTo!)) customTo = value;
      } else {
        customTo = value;
        if (customFrom != null && value.isBefore(customFrom!)) {
          customFrom = value;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Отчёт для руководителя'),
      actions: [
        IconButton(
          tooltip: 'Экспорт CSV',
          onPressed: lastReports == null ? null : exportCsv,
          icon: const Icon(Icons.ios_share_outlined),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: period,
          decoration: const InputDecoration(
            labelText: 'Период',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'today', child: Text('Сегодня')),
            DropdownMenuItem(value: 'yesterday', child: Text('Вчера')),
            DropdownMenuItem(value: 'week', child: Text('Текущая неделя')),
            DropdownMenuItem(value: 'month', child: Text('Текущий месяц')),
            DropdownMenuItem(
              value: 'previous_month',
              child: Text('Прошлый месяц'),
            ),
            DropdownMenuItem(
              value: 'custom',
              child: Text('Произвольный период'),
            ),
            DropdownMenuItem(value: 'all', child: Text('За всё время')),
          ],
          onChanged: (value) => setState(() {
            period = value!;
            if (period == 'custom' && customFrom == null) {
              final now = DateTime.now();
              customFrom = DateTime(now.year, now.month, now.day);
              customTo = customFrom;
            }
          }),
        ),
        if (period == 'custom') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => selectCustomDate(from: true),
                  child: Text(
                    'С ${customFrom == null ? 'выбрать' : shortDate(customFrom!)}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => selectCustomDate(from: false),
                  child: Text(
                    'По ${customTo == null ? 'выбрать' : shortDate(customTo!)}',
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FutureBuilder<List<LookupItem>>(
          future: widget.repository.providers(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return DropdownButtonFormField<String?>(
              initialValue: providerId,
              decoration: const InputDecoration(
                labelText: 'Провайдер',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Все провайдеры'),
                ),
                ...snapshot.data!.map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                ),
              ],
              onChanged: (value) => setState(() => providerId = value),
            );
          },
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<ProviderManagementReport>>(
          future: load(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Не удалось построить отчёт: ${snapshot.error}'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            lastReports = snapshot.data!;
            if (snapshot.data!.isEmpty) {
              return const Card(child: ListTile(title: Text('Нет данных')));
            }
            return Column(children: snapshot.data!.map(providerCard).toList());
          },
        ),
      ],
    ),
  );

  Widget providerCard(ProviderManagementReport report) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.providerName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          metric('Подключений за период', report.connections.length.toString()),
          metric('Стоимость подключений', money(report.connectionTotal)),
          metric('Доход офиса', money(report.officeIncome)),
          metric('Доля монтажника', money(report.installerIncome), muted: true),
          metric(
            'Расходы, ещё не возмещённые офисом',
            '− ${money(report.installerPaidExpenses)}',
          ),
          metric(
            'Итог офиса за период',
            money(report.officeResult),
            important: true,
          ),
          if (report.unpaidExtraWorks > 0)
            metric(
              'Невыплаченные допработы за период',
              money(report.unpaidExtraWorks),
            ),
          const Divider(height: 28),
          Text(
            'Кто кому должен',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (report.officeOwesInstaller == 0 &&
              report.installerOwesOffice == 0)
            const Text(
              'Долгов нет',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          if (report.officeOwesInstaller > 0)
            Text(
              'Офис должен монтажнику ${money(report.officeOwesInstaller)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          if (report.installerOwesOffice > 0)
            Text(
              'Монтажник должен офису ${money(report.installerOwesOffice)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          const Divider(height: 28),
          Text(
            'Использовано материалов',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (report.materials.isEmpty) const Text('Материалы не списывались'),
          ...report.materials.map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              trailing: Text(
                '${quantity(item.quantity)} ${item.unitName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const Divider(height: 28),
          Text(
            'Подключения',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (report.connections.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Подключений за период нет'),
            ),
          ...report.connections.map(connectionCard),
        ],
      ),
    ),
  );

  Widget connectionCard(ManagementConnectionItem item) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.login.isEmpty ? 'Без логина' : item.login} · ${shortDate(item.date)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        if (item.address.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(item.address),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(item.connectionType),
        ),
        const SizedBox(height: 7),
        Text('Стоимость: ${money(item.price)}'),
        Text(
          'Офису: ${money(item.officeAmount)} · Монтажнику: ${money(item.installerAmount)}',
        ),
      ],
    ),
  );

  Widget metric(
    String label,
    String value, {
    bool important = false,
    bool muted = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: muted
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: important ? 17 : 14,
          ),
        ),
      ],
    ),
  );

  Future<void> exportCsv() async {
    final reports = lastReports;
    if (reports == null) return;
    final buffer = StringBuffer('\uFEFFПровайдер;Показатель;Значение\n');
    for (final report in reports) {
      void row(String label, Object value) => buffer.writeln(
        '${csv(report.providerName)};${csv(label)};${csv(value.toString())}',
      );
      row('Подключений', report.connections.length);
      row('Стоимость подключений', report.connectionTotal);
      row('Доход офиса', report.officeIncome);
      row('Доля монтажника', report.installerIncome);
      row('Расходы, не возмещённые офисом', report.installerPaidExpenses);
      row('Итог офиса', report.officeResult);
      row('Офис должен монтажнику', report.officeOwesInstaller);
      row('Монтажник должен офису', report.installerOwesOffice);
      for (final material in report.materials) {
        row(
          'Материал: ${material.name} (${material.unitName})',
          material.quantity,
        );
      }
      for (final connection in report.connections) {
        buffer.writeln(
          '${csv(report.providerName)};${csv('Подключение ${connection.login} ${shortDate(connection.date)}')};${csv('Всего ${connection.price}, офис ${connection.officeAmount}, монтажник ${connection.installerAmount}')}',
        );
      }
    }
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/telecom-manager-report-${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(buffer.toString());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Отчёт Telecom Manager'),
    );
  }

  String csv(String value) => '"${value.replaceAll('"', '""')}"';
}
