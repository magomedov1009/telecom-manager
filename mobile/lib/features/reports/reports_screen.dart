import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  String reportPeriodLabel() {
    final range = dates();
    if (range.$1 == null && range.$2 == null) return 'Период: за всё время';
    if (range.$1 == null) return 'Период: по ${shortDate(range.$2!)}';
    if (range.$2 == null) return 'Период: с ${shortDate(range.$1!)}';
    return 'Период: с ${shortDate(range.$1!)} по ${shortDate(range.$2!)}';
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Отчёт для руководителя'),
      actions: [
        PopupMenuButton<String>(
          enabled: lastReports != null,
          tooltip: 'Экспорт отчёта',
          icon: const Icon(Icons.ios_share_outlined),
          onSelected: export,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'pdf', child: Text('PDF')),
            PopupMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
            PopupMenuItem(value: 'csv', child: Text('CSV')),
          ],
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
        Card(
          child: ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: Text(
              reportPeriodLabel(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Общий итог по провайдерам',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ...snapshot.data!.map(
                  (report) => providerCard(report, summaryOnly: true),
                ),
                const SizedBox(height: 8),
                Text(
                  'Подключения по провайдерам',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ...snapshot.data!.map(
                  (report) => providerCard(report, detailsOnly: true),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget providerCard(
    ProviderManagementReport report, {
    bool summaryOnly = false,
    bool detailsOnly = false,
  }) => Card(
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
          if (!detailsOnly) ...[
            const SizedBox(height: 12),
            metric(
              'Подключений за период',
              report.connections.length.toString(),
            ),
            metric('Стоимость подключений', money(report.connectionTotal)),
            metric('Доход офиса', money(report.officeIncome)),
            metric(
              'Доля монтажника',
              money(report.installerIncome),
              muted: true,
            ),
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
              'Итог взаиморасчёта за выбранный период',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              settlementText(report),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
          if (!summaryOnly) ...[
            const Divider(height: 28),
            Text(
              'Использовано материалов',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            if (report.materials.isEmpty)
              const Text('Материалы не списывались'),
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

  String settlementText(ProviderManagementReport report) {
    final net = report.installerOwesOffice - report.officeOwesInstaller;
    if (net.abs() < 0.005) return 'Взаиморасчёт закрыт — долгов нет';
    return net > 0
        ? 'Итог: монтажник должен офису ${money(net)}'
        : 'Итог: офис должен монтажнику ${money(-net)}';
  }

  List<(String, String)> summaryRows(ProviderManagementReport report) => [
    ('Подключений', report.connections.length.toString()),
    ('Стоимость подключений', money(report.connectionTotal)),
    ('Доход офиса', money(report.officeIncome)),
    ('Доля монтажника', money(report.installerIncome)),
    ('Расходы, не возмещённые офисом', money(report.installerPaidExpenses)),
    ('Невыплаченные допработы', money(report.unpaidExtraWorks)),
    ('Итог офиса за период', money(report.officeResult)),
    ('Итоговый взаиморасчёт', settlementText(report)),
  ];

  Future<void> export(String format) async {
    final reports = lastReports;
    if (reports == null) return;
    final directory = await getTemporaryDirectory();
    final base =
        '${directory.path}/telecom-manager-report-${DateTime.now().millisecondsSinceEpoch}';
    late final File file;
    if (format == 'xlsx') {
      file = File('$base.xlsx');
      final workbook = Excel.createExcel();
      final sheet = workbook['Отчёт'];
      workbook.delete('Sheet1');
      sheet.appendRow([TextCellValue(reportPeriodLabel())]);
      sheet.appendRow([]);
      sheet.appendRow([TextCellValue('ОБЩИЙ ИТОГ ПО ПРОВАЙДЕРАМ')]);
      for (final report in reports) {
        sheet.appendRow([TextCellValue(report.providerName)]);
        sheet.appendRow([
          TextCellValue('Показатель'),
          TextCellValue('Значение'),
        ]);
        for (final row in summaryRows(report)) {
          sheet.appendRow([TextCellValue(row.$1), TextCellValue(row.$2)]);
        }
        sheet.appendRow([]);
      }
      sheet.appendRow([TextCellValue('ПОДКЛЮЧЕНИЯ ПО ПРОВАЙДЕРАМ')]);
      for (final report in reports) {
        sheet.appendRow([TextCellValue(report.providerName)]);
        sheet.appendRow([TextCellValue('Использовано материалов')]);
        for (final material in report.materials) {
          sheet.appendRow([
            TextCellValue(material.name),
            TextCellValue(
              '${quantity(material.quantity)} ${material.unitName}',
            ),
          ]);
        }
        sheet.appendRow([TextCellValue('Подключения')]);
        sheet.appendRow([
          TextCellValue('Дата / клиент'),
          TextCellValue('Адрес'),
          TextCellValue('Стоимость'),
          TextCellValue('Офис'),
          TextCellValue('Монтажник'),
        ]);
        for (final connection in report.connections) {
          sheet.appendRow([
            TextCellValue(
              '${shortDate(connection.date)} · ${connection.login}',
            ),
            TextCellValue(connection.address),
            DoubleCellValue(connection.price),
            DoubleCellValue(connection.officeAmount),
            DoubleCellValue(connection.installerAmount),
          ]);
        }
        sheet.appendRow([]);
      }
      await file.writeAsBytes(workbook.encode()!);
    } else if (format == 'pdf') {
      file = File('$base.pdf');
      final document = pw.Document();
      final font = await loadPdfFont();
      final logoData = await rootBundle.load(
        'assets/branding/telecom-manager-logo.png',
      );
      final logo = pw.MemoryImage(logoData.buffer.asUint8List());
      document.addPage(
        pw.MultiPage(
          theme: font == null
              ? null
              : pw.ThemeData.withFont(base: font, bold: font),
          build: (_) => [
            pw.Row(
              children: [
                pw.Image(logo, width: 42, height: 42),
                pw.SizedBox(width: 12),
                pw.Text(
                  'Telecom Manager — отчёт',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              reportPeriodLabel(),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Header(level: 1, text: 'Общий итог по провайдерам'),
            ...reports.expand((report) => pdfProviderSummary(report)),
            pw.NewPage(),
            pw.Header(level: 1, text: 'Подключения по провайдерам'),
            ...reports.expand((report) => pdfProviderDetails(report)),
          ],
        ),
      );
      await file.writeAsBytes(await document.save());
    } else {
      file = File('$base.csv');
      final buffer = StringBuffer('\uFEFFОтчёт Telecom Manager\n');
      buffer.writeln(reportPeriodLabel());
      buffer.writeln();
      buffer.writeln('ОБЩИЙ ИТОГ ПО ПРОВАЙДЕРАМ');
      for (final report in reports) {
        buffer.writeln(csv(report.providerName));
        buffer.writeln('Показатель;Значение');
        for (final row in summaryRows(report)) {
          buffer.writeln('${csv(row.$1)};${csv(row.$2)}');
        }
        buffer.writeln();
      }
      buffer.writeln('ПОДКЛЮЧЕНИЯ ПО ПРОВАЙДЕРАМ');
      for (final report in reports) {
        buffer.writeln(csv(report.providerName));
        buffer.writeln('Использовано материалов');
        for (final material in report.materials) {
          buffer.writeln(
            '${csv(material.name)};${csv('${quantity(material.quantity)} ${material.unitName}')}',
          );
        }
        buffer.writeln('Подключения');
        buffer.writeln('Дата / клиент;Адрес;Стоимость;Офис;Монтажник');
        for (final connection in report.connections) {
          buffer.writeln(
            '${csv('${shortDate(connection.date)} · ${connection.login}')};'
            '${csv(connection.address)};${connection.price};'
            '${connection.officeAmount};${connection.installerAmount}',
          );
        }
        buffer.writeln();
      }
      await file.writeAsString(buffer.toString());
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Отчёт Telecom Manager'),
    );
  }

  List<pw.Widget> pdfProviderSummary(ProviderManagementReport report) => [
    pw.Header(level: 1, text: report.providerName),
    pw.TableHelper.fromTextArray(
      headers: const ['Показатель', 'Значение'],
      data: summaryRows(report).map((row) => [row.$1, row.$2]).toList(),
      cellAlignment: pw.Alignment.centerLeft,
    ),
    pw.SizedBox(height: 16),
  ];

  List<pw.Widget> pdfProviderDetails(ProviderManagementReport report) => [
    pw.Header(level: 1, text: report.providerName),
    pw.SizedBox(height: 14),
    pw.Text(
      'Использовано материалов',
      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 5),
    if (report.materials.isEmpty)
      pw.Text('Материалы не списывались')
    else
      pw.TableHelper.fromTextArray(
        headers: const ['Материал', 'Количество'],
        data: report.materials
            .map(
              (item) => [
                item.name,
                '${quantity(item.quantity)} ${item.unitName}',
              ],
            )
            .toList(),
      ),
    pw.SizedBox(height: 14),
    pw.Text(
      'Подключения',
      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 5),
    if (report.connections.isEmpty)
      pw.Text('Подключений за период нет')
    else
      pw.TableHelper.fromTextArray(
        headers: const [
          'Дата / клиент',
          'Адрес',
          'Стоимость',
          'Офис',
          'Монтажник',
        ],
        data: report.connections
            .map(
              (item) => [
                '${shortDate(item.date)}\n${item.login}',
                item.address,
                money(item.price),
                money(item.officeAmount),
                money(item.installerAmount),
              ],
            )
            .toList(),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    pw.SizedBox(height: 24),
  ];

  String csv(String value) => '"${value.replaceAll('"', '""')}"';

  Future<pw.Font?> loadPdfFont() async {
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
