import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class CatalogsScreen extends StatefulWidget {
  const CatalogsScreen({super.key, required this.repository});
  final LocalRepository repository;
  @override
  State<CatalogsScreen> createState() => _CatalogsScreenState();
}

class _CatalogsScreenState extends State<CatalogsScreen> {
  int refresh = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Справочники')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(
            'Провайдеры',
            Icons.business_outlined,
            widget.repository.providers(),
            () => _addProvider(),
          ),
          _section(
            'Склады',
            Icons.warehouse_outlined,
            widget.repository.warehouses(),
            () => _addWarehouse(),
          ),
          _section(
            'Материалы',
            Icons.inventory_2_outlined,
            widget.repository.materials(),
            () => _addMaterial(),
          ),
          _section(
            'Виды допработ',
            Icons.build_outlined,
            widget.repository.extraWorkTypes(),
            () => _addWorkType(),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String title,
    IconData icon,
    Future<List<LookupItem>> future,
    VoidCallback add,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: ValueKey('$title-$refresh'),
        child: ExpansionTile(
          leading: Icon(icon),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: add,
          ),
          children: [
            FutureBuilder<List<LookupItem>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(
                  children: snapshot.data!
                      .map((item) => ListTile(title: Text(item.name)))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _nameDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => refresh++);
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
    }
  }

  Future<void> _addProvider() async {
    final name = await _nameDialog('Новый провайдер');
    if (name != null) await _run(() => widget.repository.addProvider(name));
  }

  Future<void> _addWarehouse() async {
    final providers = await widget.repository.providers();
    if (!mounted) return;
    final name = await _nameDialog('Новый склад');
    if (name == null || providers.isEmpty || !mounted) return;
    await _run(
      () => widget.repository.addWarehouse(
        name: name,
        providerId: providers.first.id,
      ),
    );
  }

  Future<void> _addMaterial() async {
    final name = await _nameDialog('Новая позиция');
    if (name != null) {
      await _run(
        () => widget.repository.addMaterial(
          name: name,
          itemType: 'MATERIAL',
          unitName: 'шт.',
        ),
      );
    }
  }

  Future<void> _addWorkType() async {
    final name = await _nameDialog('Новый вид допработы');
    if (name != null) {
      await _run(() => widget.repository.addExtraWorkType(name: name));
    }
  }
}
