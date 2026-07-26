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
  ReportSummary? lastSummary;

  (DateTime?, DateTime?) dates() {
    final now = DateTime.now();
    return switch (period) {
      'today' => (
        DateTime(now.year, now.month, now.day),
        DateTime(now.year, now.month, now.day),
      ),
      'month' => (
        DateTime(now.year, now.month),
        DateTime(now.year, now.month, now.day),
      ),
      _ => (null, null),
    };
  }

  Future<ReportSummary> load() {
    final range = dates();
    return widget.repository.reportSummary(
      dateFrom: range.$1,
      dateTo: range.$2,
      providerId: providerId,
    );
  }

  String money(double value) => '${value.toStringAsFixed(2)} ₽';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Отчёты'),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: 'Экспорт CSV',
          onPressed: lastSummary == null ? null : export,
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'today', label: Text('Сегодня')),
            ButtonSegment(value: 'month', label: Text('Месяц')),
            ButtonSegment(value: 'all', label: Text('Всё время')),
          ],
          selected: {period},
          onSelectionChanged: (value) => setState(() => period = value.first),
        ),
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
        const SizedBox(height: 18),
        FutureBuilder<ReportSummary>(
          future: load(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            lastSummary = data;
            return Column(
              children: [
                _row(
                  'Подключения',
                  '${data.connections} · ${money(data.connectionAmount)}',
                ),
                _row(
                  'Дополнительные работы',
                  '${data.extraWorks} · ${money(data.extraWorkAmount)}',
                ),
                _row('Общий доход', money(data.income)),
                _row('Расходы', money(data.expenses)),
                _row('Прибыль', money(data.profit), important: true),
                _row('Списано материалов', data.materialSpent.toString()),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _row(String label, String value, {bool important = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      color: important ? const Color(0xFFECFDF3) : null,
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: important ? 19 : 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );

  Future<void> export() async {
    final data = lastSummary!;
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/telecom-manager-report.csv');
    await file.writeAsString(
      '\uFEFFПоказатель;Значение\n'
      'Подключения;${data.connections}\n'
      'Сумма подключений;${data.connectionAmount}\n'
      'Допработы;${data.extraWorks}\n'
      'Сумма допработ;${data.extraWorkAmount}\n'
      'Расходы;${data.expenses}\n'
      'Прибыль;${data.profit}\n'
      'Списано материалов;${data.materialSpent}\n',
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Отчёт Telecom Manager'),
    );
  }
}
