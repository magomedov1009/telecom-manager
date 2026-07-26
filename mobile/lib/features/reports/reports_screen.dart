import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
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
  String section = 'connections';
  String? providerId;
  DateTime? customFrom;
  DateTime? customTo;
  final search = TextEditingController();
  ReportSummary? lastSummary;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

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
      'custom' => (customFrom, customTo),
      _ => (null, null),
    };
  }

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

  String shortDate(DateTime? value) => value == null
      ? 'Выбрать'
      : '${value.day.toString().padLeft(2, '0')}.'
            '${value.month.toString().padLeft(2, '0')}.${value.year}';

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
        PopupMenuButton<String>(
          enabled: lastSummary != null,
          tooltip: 'Экспорт',
          icon: const Icon(Icons.ios_share_outlined),
          onSelected: export,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'csv', child: Text('CSV')),
            PopupMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
            PopupMenuItem(value: 'pdf', child: Text('PDF')),
          ],
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
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
            DropdownMenuItem(value: 'week', child: Text('Неделя')),
            DropdownMenuItem(value: 'month', child: Text('Месяц')),
            DropdownMenuItem(
              value: 'custom',
              child: Text('Произвольный период'),
            ),
            DropdownMenuItem(value: 'all', child: Text('За всё время')),
          ],
          onChanged: (value) => setState(() {
            period = value!;
            if (period == 'custom' && customFrom == null && customTo == null) {
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
                child: OutlinedButton.icon(
                  onPressed: () => selectCustomDate(from: true),
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text('С ${shortDate(customFrom)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => selectCustomDate(from: false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('По ${shortDate(customTo)}'),
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
        const SizedBox(height: 18),
        TextField(
          controller: search,
          decoration: const InputDecoration(
            labelText: 'Поиск в детализации',
            hintText: 'Договор, адрес, материал или комментарий',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: section,
          decoration: const InputDecoration(
            labelText: 'Детализация',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'providers', child: Text('Провайдеры')),
            DropdownMenuItem(value: 'connections', child: Text('Подключения')),
            DropdownMenuItem(value: 'works', child: Text('Допработы')),
            DropdownMenuItem(value: 'expenses', child: Text('Расходы')),
            DropdownMenuItem(
              value: 'inventory',
              child: Text('Складские списания'),
            ),
            DropdownMenuItem(
              value: 'material_settlements',
              child: Text('Долги материалов'),
            ),
            DropdownMenuItem(value: 'finance', child: Text('Финансы')),
          ],
          onChanged: (value) => setState(() => section = value!),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<ReportDetailItem>>(
          future: widget.repository.reportDetails(
            section: section,
            dateFrom: dates().$1,
            dateTo: dates().$2,
            providerId: providerId,
            search: search.text,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            if (snapshot.data!.isEmpty) {
              return const Card(
                child: ListTile(title: Text('Нет записей за период')),
              );
            }
            return Column(
              children: snapshot.data!
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          title: Text(item.title),
                          subtitle: Text(item.subtitle),
                          trailing: Text(
                            item.value.toStringAsFixed(2),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
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

  Future<void> export(String format) async {
    final data = lastSummary!;
    final range = dates();
    final details = await widget.repository.reportDetails(
      section: section,
      dateFrom: range.$1,
      dateTo: range.$2,
      providerId: providerId,
      search: search.text,
    );
    final directory = await getTemporaryDirectory();
    final baseName =
        'telecom-manager-report-${DateTime.now().millisecondsSinceEpoch}';
    late final File file;
    if (format == 'xlsx') {
      file = File('${directory.path}/$baseName.xlsx');
      final workbook = Excel.createExcel();
      final sheet = workbook['Отчёт'];
      workbook.delete('Sheet1');
      sheet.appendRow([TextCellValue('Показатель'), TextCellValue('Значение')]);
      for (final row in _summaryRows(data)) {
        sheet.appendRow([TextCellValue(row.$1), TextCellValue(row.$2)]);
      }
      sheet.appendRow([]);
      sheet.appendRow([
        TextCellValue('Название'),
        TextCellValue('Описание'),
        TextCellValue('Значение'),
      ]);
      for (final item in details) {
        sheet.appendRow([
          TextCellValue(item.title),
          TextCellValue(item.subtitle),
          DoubleCellValue(item.value),
        ]);
      }
      await file.writeAsBytes(workbook.encode()!);
    } else if (format == 'pdf') {
      file = File('${directory.path}/$baseName.pdf');
      final document = pw.Document();
      final font = await _loadPdfFont();
      document.addPage(
        pw.MultiPage(
          theme: font == null
              ? null
              : pw.ThemeData.withFont(base: font, bold: font),
          build: (_) => [
            pw.Header(level: 0, text: 'Telecom Manager — отчёт'),
            pw.TableHelper.fromTextArray(
              headers: const ['Показатель', 'Значение'],
              data: _summaryRows(data).map((row) => [row.$1, row.$2]).toList(),
            ),
            pw.SizedBox(height: 18),
            pw.Header(level: 1, text: 'Детализация'),
            pw.TableHelper.fromTextArray(
              headers: const ['Название', 'Описание', 'Значение'],
              data: details
                  .map(
                    (item) => [
                      item.title,
                      item.subtitle,
                      item.value.toStringAsFixed(2),
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );
      await file.writeAsBytes(await document.save());
    } else {
      file = File('${directory.path}/$baseName.csv');
      final buffer = StringBuffer('\uFEFFПоказатель;Значение\n');
      for (final row in _summaryRows(data)) {
        buffer.writeln('${_csv(row.$1)};${_csv(row.$2)}');
      }
      buffer.writeln();
      buffer.writeln('Название;Описание;Значение');
      for (final item in details) {
        buffer.writeln(
          '${_csv(item.title)};${_csv(item.subtitle)};${item.value}',
        );
      }
      await file.writeAsString(buffer.toString());
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Отчёт Telecom Manager'),
    );
  }

  List<(String, String)> _summaryRows(ReportSummary data) => [
    ('Подключения', data.connections.toString()),
    ('Сумма подключений', data.connectionAmount.toStringAsFixed(2)),
    ('Допработы', data.extraWorks.toString()),
    ('Сумма допработ', data.extraWorkAmount.toStringAsFixed(2)),
    ('Общий доход', data.income.toStringAsFixed(2)),
    ('Расходы', data.expenses.toStringAsFixed(2)),
    ('Прибыль', data.profit.toStringAsFixed(2)),
    ('Списано материалов', data.materialSpent.toString()),
  ];

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  Future<pw.Font?> _loadPdfFont() async {
    const candidates = [
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      r'C:\Windows\Fonts\arial.ttf',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      return pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(bytes)));
    }
    return null;
  }
}
