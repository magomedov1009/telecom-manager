import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/repositories/local_repository.dart';

class FiberWorkScreen extends StatefulWidget {
  const FiberWorkScreen({super.key, required this.repository});

  final LocalRepository repository;

  @override
  State<FiberWorkScreen> createState() => _FiberWorkScreenState();
}

class _FiberWorkScreenState extends State<FiberWorkScreen> {
  late Future<List<FiberWorkLogItem>> _logs;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _logs = widget.repository.fiberWorkLogs());

  Future<void> _edit([FiberWorkLogItem? log]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _FiberWorkEditor(repository: widget.repository, initial: log),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(FiberWorkLogItem log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text('Она исчезнет из журнала кабеля и сварок.'),
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
    if (confirmed != true) return;
    await widget.repository.deleteFiberWorkLog(log.id);
    if (mounted) _reload();
  }

  Future<void> _shareObjectReport(FiberWorkLogItem log) async {
    try {
      final document = pw.Document();
      final splicesByClosure = <String, int>{};
      for (final splice in log.splices) {
        final closure = splice['closure']?.toString() ?? 'Без названия';
        splicesByClosure.update(
          closure,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      final mapImage = log.mapData?['image'] is String
          ? await _renderFiberMap(log.mapData!, log.cableSpans)
          : null;
      pw.Font? font;
      for (final path in [
        '/system/fonts/Roboto-Regular.ttf',
        '/system/fonts/NotoSans-Regular.ttf',
      ]) {
        final candidate = File(path);
        if (await candidate.exists()) {
          font = pw.Font.ttf(
            ByteData.sublistView(await candidate.readAsBytes()),
          );
          break;
        }
      }
      final theme = font == null
          ? null
          : pw.ThemeData.withFont(base: font, bold: font);
      document.addPage(
        pw.MultiPage(
          theme: theme,
          build: (_) => [
            pw.Text(
              'Отчёт по объекту: ${log.objectName}',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Дата: ${_formatFiberDate(log.workDate)}'),
            pw.SizedBox(height: 14),
            pw.Text(
              'ИТОГО ДЛЯ СДАЧИ',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Общий метраж кабеля: ${_meters(log.totalCableMeters)} м'),
            pw.Text('Всего сварено волокон: ${log.totalSplices}'),
            pw.SizedBox(height: 14),
            pw.Header(level: 1, text: 'Итоги по муфтам'),
            if (splicesByClosure.isEmpty)
              pw.Text('Сварок нет')
            else
              pw.TableHelper.fromTextArray(
                headers: const ['Муфта', 'Сварено волокон'],
                data: splicesByClosure.entries
                    .map((entry) => [entry.key, entry.value.toString()])
                    .toList(),
              ),
            pw.SizedBox(height: 14),
            if (mapImage != null) ...[
              pw.Header(level: 1, text: 'Черновая схема объекта'),
              pw.Image(
                pw.MemoryImage(mapImage),
                fit: pw.BoxFit.contain,
                width: 500,
              ),
              pw.SizedBox(height: 14),
            ],
            pw.Header(level: 1, text: 'Участки кабеля'),
            if (log.cableSpans.isEmpty)
              pw.Text('Участков нет')
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'Кабель',
                  'От муфты',
                  'До муфты',
                  'Метраж',
                  'Волокон',
                ],
                data: log.cableSpans
                    .map(
                      (row) => [
                        row['cable_mark']?.toString() ?? '',
                        row['from_closure']?.toString() ?? '',
                        row['to_closure']?.toString() ?? '',
                        '${_meters((row['length_m'] as num?)?.toDouble() ?? 0)} м',
                        row['fiber_count']?.toString() ?? '',
                      ],
                    )
                    .toList(),
              ),
            pw.SizedBox(height: 14),
            pw.Header(level: 1, text: 'Сваренные волокна'),
            if (log.splices.isEmpty)
              pw.Text('Сварок нет')
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'Муфта',
                  'Кабель',
                  '№ волокна',
                  'Цвет',
                  'Соединение',
                ],
                data: log.splices
                    .map(
                      (row) => [
                        row['closure']?.toString() ?? '',
                        row['cable_mark']?.toString() ?? '',
                        row['fiber_number']?.toString() ?? '',
                        row['fiber_color_name']?.toString() ?? '',
                        row['connected_cable_mark'] == null
                            ? ''
                            : '${row['connected_cable_mark']} · №${row['connected_fiber_number'] ?? ''}',
                      ],
                    )
                    .toList(),
              ),
            if ((log.notes ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Header(level: 1, text: 'Примечание'),
              pw.Text(log.notes!),
            ],
          ],
        ),
      );
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/object-report-${log.id}.pdf');
      await file.writeAsBytes(await document.save());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Отчёт по объекту ${log.objectName}',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сформировать отчёт: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: const Text(
        'Кабель и сварки',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Шпаргалка цветов',
          onPressed: () => _showColorGuide(context),
          icon: const Icon(Icons.palette_outlined),
        ),
      ],
    ),
    body: FutureBuilder<List<FiberWorkLogItem>>(
      future: _logs,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs = snapshot.data!;
        if (logs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Здесь ведётся отдельный учёт кабеля и сварок.\nДобавь объект, чтобы начать.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: logs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final log = logs[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.cable_outlined)),
                title: Text(
                  log.objectName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 5,
                    children: [
                      _SummaryChip(
                        icon: Icons.linear_scale,
                        text: '${_meters(log.totalCableMeters)} м',
                      ),
                      _SummaryChip(
                        icon: Icons.device_hub_outlined,
                        text: '${log.totalSplices} сварок',
                      ),
                      Text(
                        _formatFiberDate(log.workDate),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => value == 'delete'
                      ? _delete(log)
                      : value == 'report'
                      ? _shareObjectReport(log)
                      : _edit(log),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Открыть / изменить'),
                    ),
                    PopupMenuItem(
                      value: 'report',
                      child: Text('Отчёт по объекту (PDF)'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
                onTap: () => _edit(log),
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Новый объект'),
    ),
  );
}

class _FiberWorkEditor extends StatefulWidget {
  const _FiberWorkEditor({required this.repository, this.initial});
  final LocalRepository repository;
  final FiberWorkLogItem? initial;

  @override
  State<_FiberWorkEditor> createState() => _FiberWorkEditorState();
}

class _FiberWorkEditorState extends State<_FiberWorkEditor> {
  late final TextEditingController _object;
  late final TextEditingController _notes;
  late DateTime _date;
  late List<Map<String, Object?>> _spans;
  late List<Map<String, Object?>> _splices;
  Map<String, Object?>? _mapData;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _object = TextEditingController(text: widget.initial?.objectName ?? '');
    _notes = TextEditingController(text: widget.initial?.notes ?? '');
    _date = widget.initial?.workDate ?? DateTime.now();
    _spans =
        widget.initial?.cableSpans.map(Map<String, Object?>.from).toList() ??
        [];
    _splices =
        widget.initial?.splices.map(Map<String, Object?>.from).toList() ?? [];
    _mapData = widget.initial?.mapData == null
        ? null
        : Map<String, Object?>.from(widget.initial!.mapData!);
  }

  @override
  void dispose() {
    _object.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _totalMeters => _spans.fold(
    0,
    (sum, row) => sum + ((row['length_m'] as num?)?.toDouble() ?? 0),
  );

  Future<void> _editMap() async {
    final closures = <String>{
      for (final span in _spans) ...[
        span['from_closure']?.toString() ?? '',
        span['to_closure']?.toString() ?? '',
      ],
      for (final splice in _splices) splice['closure']?.toString() ?? '',
    }..removeWhere((value) => value.trim().isEmpty);
    if (closures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Сначала добавь участок кабеля или сварку с названием муфты',
          ),
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => FiberMapEditor(
          closures: closures.toList()..sort(),
          spans: _spans,
          initial: _mapData,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _mapData = result);
  }

  Future<void> _addSpan([int? index]) async {
    final initial = index == null ? null : _spans[index];
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _SpanDialog(initial: initial),
    );
    if (result == null) return;
    final cableMark = result['cable_mark']?.toString();
    final duplicateMark = _spans.asMap().entries.any(
      (entry) =>
          entry.key != index &&
          entry.value['cable_mark']?.toString() == cableMark,
    );
    if (duplicateMark) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Метка кабеля должна быть уникальной внутри объекта'),
          ),
        );
      }
      return;
    }
    setState(() {
      if (index == null) {
        _spans.add(result);
      } else {
        _spans[index] = result;
        final mark = result['cable_mark'];
        _splices = _splices.map((splice) {
          if (splice['cable_mark'] == initial?['cable_mark']) {
            return {...splice, 'cable_mark': mark};
          }
          return splice;
        }).toList();
      }
    });
  }

  Future<void> _addSplice([int? index]) async {
    if (_spans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавь отрезок кабеля')),
      );
      return;
    }
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _SpliceDialog(
        spans: _spans,
        initial: index == null ? null : _splices[index],
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _splices.add(result);
      } else {
        _splices[index] = result;
      }
    });
  }

  Future<void> _save() async {
    if (_object.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажи объект или монтажку')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.saveFiberWorkLog(
        id: widget.initial?.id,
        objectName: _object.text,
        workDate: _date,
        cableSpans: _spans,
        splices: _splices,
        mapData: _mapData,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Invalid argument(s): ', ''),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .94,
      maxChildSize: .98,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initial == null
                ? 'Новый кабельный журнал'
                : 'Журнал объекта',
          ),
          actions: [
            IconButton(
              tooltip: 'Цветовая шпаргалка',
              onPressed: () => _showColorGuide(context),
              icon: const Icon(Icons.palette_outlined),
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Сохранить'),
            ),
          ],
        ),
        body: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            TextField(
              controller: _object,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Объект / монтажка',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_month),
              label: Text('Дата: ${_formatFiberDate(_date)}'),
            ),
            const SizedBox(height: 18),
            _sectionHeading(
              context,
              'Отрезки кабеля',
              '${_meters(_totalMeters)} м',
            ),
            const SizedBox(height: 8),
            if (_spans.isEmpty)
              const _EmptyHint('Добавь участок от муфты до муфты'),
            ..._spans.asMap().entries.map((entry) {
              final i = entry.key;
              final span = entry.value;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.cable_outlined),
                  title: Text(
                    '${span['from_closure']} → ${span['to_closure']}',
                  ),
                  subtitle: Text(
                    '${span['cable_mark']} · ${_meters((span['length_m'] as num).toDouble())} м · ${(span['fiber_count'] as num).toInt()} волокон',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      final removed = _spans.removeAt(i);
                      _splices.removeWhere(
                        (s) => s['cable_mark'] == removed['cable_mark'],
                      );
                    }),
                  ),
                  onTap: () => _addSpan(i),
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () => _addSpan(),
              icon: const Icon(Icons.add),
              label: const Text('Добавить отрезок'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _editMap,
              icon: const Icon(Icons.map_outlined),
              label: Text(
                _mapData?['image'] == null
                    ? 'Схема на скриншоте карты'
                    : 'Изменить схему на карте',
              ),
            ),
            const SizedBox(height: 20),
            _sectionHeading(
              context,
              'Сварки по муфтам',
              '${_splices.length} волокон',
            ),
            const SizedBox(height: 8),
            if (_splices.isEmpty)
              const _EmptyHint('Каждая запись — одно сваренное волокно'),
            ..._splices.asMap().entries.map((entry) {
              final i = entry.key;
              final splice = entry.value;
              final color = _colorFor(splice['fiber_color']?.toString());
              final destination = splice['connected_cable_mark']?.toString();
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color,
                    child: Text(
                      '${splice['fiber_number']}',
                      style: TextStyle(color: _contrast(color)),
                    ),
                  ),
                  title: Text(
                    '${splice['closure']} · ${splice['fiber_color_name'] ?? 'волокно'}',
                  ),
                  subtitle: Text(
                    '${splice['cable_mark']} · волокно №${splice['fiber_number']}${destination == null || destination.isEmpty ? '' : ' → $destination, №${splice['connected_fiber_number']}'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _splices.removeAt(i)),
                  ),
                  onTap: () => _addSplice(i),
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () => _addSplice(),
              icon: const Icon(Icons.add),
              label: const Text('Отметить сваренное волокно'),
            ),
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ИТОГО ДЛЯ СДАЧИ',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Сварено волокон: ${_splices.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Кабель: ${_meters(_totalMeters)} м',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Примечание (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Сохраняю…' : 'Сохранить журнал'),
            ),
          ],
        ),
      ),
    ),
  );
}

class FiberMapEditor extends StatefulWidget {
  const FiberMapEditor({
    super.key,
    required this.closures,
    required this.spans,
    this.initial,
  });

  final List<String> closures;
  final List<Map<String, Object?>> spans;
  final Map<String, Object?>? initial;

  @override
  State<FiberMapEditor> createState() => _FiberMapEditorState();
}

class _FiberMapEditorState extends State<FiberMapEditor> {
  final _picker = ImagePicker();
  late Map<String, Object?> _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initial == null
        ? <String, Object?>{'markers': <String, Object?>{}}
        : Map<String, Object?>.from(widget.initial!);
    _data['markers'] = _markerMap;
  }

  Map<String, Object?> get _markerMap {
    final value = _data['markers'];
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  Future<void> _pickBackground() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 78,
      );
      if (file == null) return;
      setState(() => _loading = true);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();
      setState(() {
        _data['image'] = base64Encode(bytes);
        _data['aspect'] = image.width / image.height;
        _data['markers'] = <String, Object?>{};
        image.dispose();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть изображение: $error')),
        );
      }
    }
  }

  Future<void> _placeMarker(Offset localPosition, Size size) async {
    final markers = _markerMap;
    final unplaced = widget.closures
        .where((name) => !markers.containsKey(name))
        .toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Какую муфту отметить здесь?')),
            ...widget.closures.map(
              (name) => ListTile(
                leading: Icon(
                  markers.containsKey(name)
                      ? Icons.location_on
                      : Icons.add_location_alt_outlined,
                ),
                title: Text(name),
                subtitle: unplaced.contains(name)
                    ? null
                    : const Text('Перенести метку сюда'),
                onTap: () => Navigator.pop(context, name),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final next = _markerMap;
    next[selected] = <String, Object?>{
      'x': (localPosition.dx / size.width).clamp(0.0, 1.0),
      'y': (localPosition.dy / size.height).clamp(0.0, 1.0),
    };
    setState(() => _data['markers'] = next);
  }

  @override
  Widget build(BuildContext context) {
    final encoded = _data['image']?.toString();
    final markers = _markerMap;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Черновая схема объекта'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _data),
            child: const Text('Готово'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Выбери скриншот гибридной карты, затем нажимай на нём и отмечай муфты. Участки кабеля соединятся автоматически. Метраж берётся из журнала, не измеряется по картинке.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: encoded == null
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _pickBackground,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Выбрать скриншот карты'),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final aspect =
                          (_data['aspect'] as num?)?.toDouble() ?? 1.4;
                      final width = constraints.maxWidth;
                      final height = width / aspect;
                      return InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        constrained: false,
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) => _placeMarker(
                              details.localPosition,
                              Size(width, height),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  base64Decode(encoded),
                                  fit: BoxFit.fill,
                                ),
                                CustomPaint(
                                  painter: _FiberMapPainter(
                                    markers: markers,
                                    spans: widget.spans,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (encoded != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Отмечено муфт: ${markers.length} из ${widget.closures.length}',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _pickBackground,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Сменить карту'),
                      ),
                    ],
                  ),
                  if (markers.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: markers.keys
                          .map(
                            (name) => InputChip(
                              label: Text(name),
                              onDeleted: () => setState(() {
                                final next = _markerMap..remove(name);
                                _data['markers'] = next;
                              }),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FiberMapPainter extends CustomPainter {
  const _FiberMapPainter({
    required this.markers,
    required this.spans,
    this.scale = 1,
  });
  final Map<String, Object?> markers;
  final List<Map<String, Object?>> spans;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    Offset? point(String? name) {
      final value = markers[name];
      if (value is! Map) return null;
      return Offset(
        ((value['x'] as num?)?.toDouble() ?? 0) * size.width,
        ((value['y'] as num?)?.toDouble() ?? 0) * size.height,
      );
    }

    final line = Paint()
      ..color = const Color(0xffef4444)
      ..strokeWidth = 4 * scale
      ..strokeCap = StrokeCap.round;
    for (final span in spans) {
      final start = point(span['from_closure']?.toString());
      final end = point(span['to_closure']?.toString());
      if (start == null || end == null) continue;
      canvas.drawLine(start, end, line);
      final label = TextPainter(
        text: TextSpan(
          text:
              '${span['cable_mark']} · ${_meters((span['length_m'] as num?)?.toDouble() ?? 0)} м',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12 * scale,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 4 * scale)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * .45);
      label.paint(
        canvas,
        Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2),
      );
    }
    for (final entry in markers.entries) {
      final location = point(entry.key);
      if (location == null) continue;
      canvas.drawCircle(location, 12 * scale, Paint()..color = Colors.white);
      canvas.drawCircle(
        location,
        9 * scale,
        Paint()..color = const Color(0xff2563eb),
      );
      final label = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12 * scale,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 5 * scale)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * .5);
      label.paint(canvas, location + Offset(12 * scale, -20 * scale));
    }
  }

  @override
  bool shouldRepaint(covariant _FiberMapPainter oldDelegate) =>
      oldDelegate.markers != markers || oldDelegate.spans != spans;
}

Future<Uint8List> _renderFiberMap(
  Map<String, Object?> data,
  List<Map<String, Object?>> spans,
) async {
  final codec = await ui.instantiateImageCodec(
    base64Decode(data['image']! as String),
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  codec.dispose();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  canvas.drawImageRect(image, bounds, bounds, Paint());
  final markerValue = data['markers'];
  final markers = markerValue is Map
      ? Map<String, Object?>.from(markerValue)
      : <String, Object?>{};
  _FiberMapPainter(
    markers: markers,
    spans: spans,
    scale: math.min(image.width, image.height) / 400,
  ).paint(canvas, Size(image.width.toDouble(), image.height.toDouble()));
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(image.width, image.height);
  final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  rendered.dispose();
  picture.dispose();
  if (png == null) throw StateError('Не удалось подготовить схему для отчёта');
  return png.buffer.asUint8List();
}

class _SpanDialog extends StatefulWidget {
  const _SpanDialog({this.initial});
  final Map<String, Object?>? initial;

  @override
  State<_SpanDialog> createState() => _SpanDialogState();
}

class _SpanDialogState extends State<_SpanDialog> {
  late final TextEditingController _mark, _from, _to, _meters, _count;
  late List<String> _colors;

  @override
  void initState() {
    super.initState();
    final row = widget.initial;
    _mark = TextEditingController(text: row?['cable_mark']?.toString() ?? '');
    _from = TextEditingController(text: row?['from_closure']?.toString() ?? '');
    _to = TextEditingController(text: row?['to_closure']?.toString() ?? '');
    _meters = TextEditingController(text: row?['length_m']?.toString() ?? '');
    _count = TextEditingController(
      text: row?['fiber_count']?.toString() ?? '12',
    );
    final saved = (row?['fiber_colors'] as List?)
        ?.map((e) => e.toString())
        .toList();
    _colors = saved ?? fiberColors.take(12).map((e) => e.id).toList();
  }

  @override
  void dispose() {
    _mark.dispose();
    _from.dispose();
    _to.dispose();
    _meters.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Отрезок кабеля'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _mark,
              decoration: const InputDecoration(labelText: 'Метка кабеля'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    decoration: const InputDecoration(labelText: 'От муфты'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _to,
                    decoration: const InputDecoration(labelText: 'До муфты'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _meters,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Метраж (м)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Волокон'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Цвета волокон по фактическому порядку',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Отметь цвета, которые есть в этом кабеле. Они будут пронумерованы подряд; отсутствующие цвета пропускаются.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 215,
              child: ListView(
                children: fiberColors
                    .map(
                      (fiber) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _colors.contains(fiber.id),
                        secondary: CircleAvatar(
                          radius: 10,
                          backgroundColor: fiber.color,
                        ),
                        title: Text(fiber.name),
                        subtitle: _colors.contains(fiber.id)
                            ? Text('Позиция ${_colors.indexOf(fiber.id) + 1}')
                            : null,
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _colors.add(fiber.id);
                          } else {
                            _colors.remove(fiber.id);
                          }
                          _colors.sort(
                            (a, b) => fiberColors
                                .indexWhere((x) => x.id == a)
                                .compareTo(
                                  fiberColors.indexWhere((x) => x.id == b),
                                ),
                          );
                          final count = _colors.length;
                          if (_count.text.isEmpty ||
                              int.tryParse(_count.text) == 12) {
                            _count.text = '$count';
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          final length = double.tryParse(
            _meters.text.trim().replaceAll(',', '.'),
          );
          final count = int.tryParse(_count.text.trim());
          if (_mark.text.trim().isEmpty ||
              _from.text.trim().isEmpty ||
              _to.text.trim().isEmpty ||
              length == null ||
              length <= 0 ||
              count == null ||
              count <= 0 ||
              _colors.length < count) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Заполни метку, муфты, метраж, число волокон и достаточно цветов',
                ),
              ),
            );
            return;
          }
          final chosen = _colors.take(count).toList();
          Navigator.pop(context, {
            'cable_mark': _mark.text.trim(),
            'from_closure': _from.text.trim(),
            'to_closure': _to.text.trim(),
            'length_m': length,
            'fiber_count': count,
            'fiber_colors': chosen,
          });
        },
        child: const Text('Готово'),
      ),
    ],
  );
}

class _SpliceDialog extends StatefulWidget {
  const _SpliceDialog({required this.spans, this.initial});
  final List<Map<String, Object?>> spans;
  final Map<String, Object?>? initial;

  @override
  State<_SpliceDialog> createState() => _SpliceDialogState();
}

class _SpliceDialogState extends State<_SpliceDialog> {
  late final TextEditingController _closure, _otherCable, _otherFiber;
  late String _mark;
  late int _fiber;

  Map<String, Object?> get _span => widget.spans.firstWhere(
    (s) => s['cable_mark'] == _mark,
    orElse: () => widget.spans.first,
  );
  List<String> get _colors =>
      ((_span['fiber_colors'] as List?)?.map((e) => e.toString()).toList() ??
      fiberColors
          .take((_span['fiber_count'] as num).toInt())
          .map((e) => e.id)
          .toList());
  _FiberColor get _selectedColor => fiberColors.firstWhere(
    (e) => e.id == (_fiber <= _colors.length ? _colors[_fiber - 1] : ''),
    orElse: () => fiberColors.first,
  );

  @override
  void initState() {
    super.initState();
    final first = widget.spans.first;
    _mark =
        widget.initial?['cable_mark']?.toString() ??
        first['cable_mark'].toString();
    final maxFiber =
        (widget.spans.firstWhere(
                  (s) => s['cable_mark'] == _mark,
                  orElse: () => first,
                )['fiber_count']
                as num)
            .toInt();
    _fiber = math.min(
      (widget.initial?['fiber_number'] as num?)?.toInt() ?? 1,
      maxFiber,
    );
    _closure = TextEditingController(
      text: widget.initial?['closure']?.toString() ?? '',
    );
    _otherCable = TextEditingController(
      text: widget.initial?['connected_cable_mark']?.toString() ?? '',
    );
    _otherFiber = TextEditingController(
      text: widget.initial?['connected_fiber_number']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _closure.dispose();
    _otherCable.dispose();
    _otherFiber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Сваренное волокно'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _closure,
            decoration: const InputDecoration(labelText: 'Муфта'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _mark,
            decoration: const InputDecoration(labelText: 'Кабель'),
            items: widget.spans
                .map(
                  (span) => DropdownMenuItem(
                    value: span['cable_mark']!.toString(),
                    child: Text(span['cable_mark']!.toString()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _mark = value;
                _fiber = math.min(
                  _fiber,
                  (_span['fiber_count'] as num).toInt(),
                );
              });
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: _fiber,
            decoration: InputDecoration(
              labelText: 'Номер волокна · ${_selectedColor.name}',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(14),
                child: CircleAvatar(
                  backgroundColor: _selectedColor.color,
                  radius: 8,
                ),
              ),
            ),
            items: List.generate(
              (_span['fiber_count'] as num).toInt(),
              (i) => DropdownMenuItem(
                value: i + 1,
                child: Text(
                  '№ ${i + 1} · ${i < _colors.length ? fiberColors.firstWhere((c) => c.id == _colors[i], orElse: () => fiberColors.first).name : 'цвет не задан'}',
                ),
              ),
            ),
            onChanged: (value) {
              if (value != null) setState(() => _fiber = value);
            },
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _otherCable,
                  decoration: const InputDecoration(
                    labelText: 'Сварено с кабелем (необязательно)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _otherFiber,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '№ волокна'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (_closure.text.trim().isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Укажи муфту')));
            return;
          }
          Navigator.pop(context, {
            'closure': _closure.text.trim(),
            'cable_mark': _mark,
            'fiber_number': _fiber,
            'fiber_color': _selectedColor.id,
            'fiber_color_name': _selectedColor.name,
            'connected_cable_mark': _otherCable.text.trim().isEmpty
                ? null
                : _otherCable.text.trim(),
            'connected_fiber_number': int.tryParse(_otherFiber.text.trim()),
          });
        },
        child: const Text('Записать сварку'),
      ),
    ],
  );
}

class _FiberColor {
  const _FiberColor(this.id, this.name, this.color);
  final String id;
  final String name;
  final Color color;
}

const fiberColors = <_FiberColor>[
  _FiberColor('blue', 'Синий', Color(0xFF1565C0)),
  _FiberColor('green', 'Зелёный', Color(0xFF43A047)),
  _FiberColor('yellow', 'Жёлтый', Color(0xFFFFD600)),
  _FiberColor('red', 'Красный', Color(0xFFE53935)),
  _FiberColor('natural', 'Неокрашенный', Color(0xFFE0D9C8)),
  _FiberColor('orange', 'Оранжевый', Color(0xFFFB8C00)),
  _FiberColor('gray', 'Серый', Color(0xFF757575)),
  _FiberColor('violet', 'Фиолетовый', Color(0xFF8E24AA)),
  _FiberColor('pink', 'Розовый', Color(0xFFF48FB1)),
  _FiberColor('brown', 'Коричневый', Color(0xFF795548)),
  _FiberColor('turquoise', 'Бирюзовый', Color(0xFF26A69A)),
  _FiberColor('black', 'Чёрный', Color(0xFF212121)),
  _FiberColor('white', 'Белый', Color(0xFFF5F5F5)),
  _FiberColor('salad', 'Салатовый', Color(0xFF9CCC65)),
  _FiberColor('olive', 'Оливковый', Color(0xFF827717)),
  _FiberColor('beige', 'Бежевый', Color(0xFFD7CCC8)),
  _FiberColor('light_blue', 'Голубой', Color(0xFF29B6F6)),
  _FiberColor('lime', 'Лайм', Color(0xFFD4E157)),
  _FiberColor('purple', 'Пурпурный', Color(0xFFAB47BC)),
  _FiberColor('lilac', 'Лиловый', Color(0xFFCE93D8)),
  _FiberColor('red_lilac', 'Красно-лиловый', Color(0xFFAD1457)),
  _FiberColor('aquamarine', 'Аквамарин', Color(0xFF80CBC4)),
  _FiberColor('burgundy', 'Бордовый', Color(0xFF880E4F)),
  _FiberColor('indigo', 'Индиго', Color(0xFF5E35B1)),
];

const moduleColors = <_FiberColor>[
  _FiberColor('module_red', 'Красный', Color(0xFFE53935)),
  _FiberColor('module_orange', 'Оранжевый', Color(0xFFFB8C00)),
  _FiberColor('module_yellow', 'Жёлтый', Color(0xFFFFD600)),
  _FiberColor('module_green', 'Зелёный', Color(0xFF43A047)),
  _FiberColor('module_blue', 'Синий', Color(0xFF1565C0)),
  _FiberColor('module_natural_1', 'Натуральный 1', Color(0xFFE0D9C8)),
  _FiberColor('module_natural_2', 'Натуральный 2', Color(0xFFD6D0C4)),
  _FiberColor('module_natural_3', 'Натуральный 3', Color(0xFFCAC5B9)),
  _FiberColor('module_natural_4', 'Натуральный 4', Color(0xFFBDB8AC)),
];

Color _colorFor(String? id) => fiberColors
    .firstWhere((e) => e.id == id, orElse: () => fiberColors.first)
    .color;
Color _contrast(Color color) =>
    color.computeLuminance() > .48 ? Colors.black : Colors.white;
String _meters(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
String _formatFiberDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

Widget _sectionHeading(BuildContext context, String title, String trailing) =>
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(trailing, style: Theme.of(context).textTheme.labelLarge),
      ],
    );

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(text),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

void _showColorGuide(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'Цвета оптических волокон',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ...fiberColors.asMap().entries.map(
            (entry) => ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: entry.value.color,
                child: Text(
                  '${entry.key + 1}',
                  style: TextStyle(
                    color: _contrast(entry.value.color),
                    fontSize: 11,
                  ),
                ),
              ),
              title: Text(entry.value.name),
            ),
          ),
          const Divider(),
          Text('Цвета модулей', style: Theme.of(context).textTheme.titleLarge),
          ...moduleColors.asMap().entries.map(
            (entry) => ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: entry.value.color,
                child: Text(
                  '${entry.key + 1}',
                  style: TextStyle(
                    color: _contrast(entry.value.color),
                    fontSize: 11,
                  ),
                ),
              ),
              title: Text(entry.value.name),
            ),
          ),
        ],
      ),
    ),
  );
}
