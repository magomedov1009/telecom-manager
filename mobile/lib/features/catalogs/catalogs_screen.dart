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
    if (!mounted || providers.isEmpty) return;
    final name = TextEditingController();
    String providerId = providers.first.id;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новый склад'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: providerId,
                decoration: const InputDecoration(labelText: 'Провайдер'),
                items: providers
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => providerId = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final value = name.text;
    name.dispose();
    if (saved != true) return;
    await _run(
      () => widget.repository.addWarehouse(name: value, providerId: providerId),
    );
  }

  Future<void> _addMaterial() async {
    final name = TextEditingController();
    String itemType = 'MATERIAL';
    String unit = 'шт.';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новая позиция'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: itemType,
                decoration: const InputDecoration(labelText: 'Тип'),
                items: const [
                  DropdownMenuItem(value: 'MATERIAL', child: Text('Материал')),
                  DropdownMenuItem(
                    value: 'EQUIPMENT',
                    child: Text('Оборудование'),
                  ),
                ],
                onChanged: (value) => setDialogState(() => itemType = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Единица'),
                items: const [
                  DropdownMenuItem(value: 'шт.', child: Text('Штуки')),
                  DropdownMenuItem(value: 'м', child: Text('Метры')),
                ],
                onChanged: (value) => setDialogState(() => unit = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final value = name.text;
    name.dispose();
    if (saved == true) {
      await _run(
        () => widget.repository.addMaterial(
          name: value,
          itemType: itemType,
          unitName: unit,
        ),
      );
    }
  }

  Future<void> _addWorkType() async {
    final name = TextEditingController();
    final price = TextEditingController(text: '0');
    bool requiresMaterials = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новый вид допработы'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Цена по умолчанию',
                ),
              ),
              CheckboxListTile(
                value: requiresMaterials,
                title: const Text('Использует материалы'),
                onChanged: (value) =>
                    setDialogState(() => requiresMaterials = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final cleanName = name.text;
    final defaultPrice = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    name.dispose();
    price.dispose();
    if (saved == true) {
      await _run(
        () => widget.repository.addExtraWorkType(
          name: cleanName,
          defaultPrice: defaultPrice,
          requiresMaterials: requiresMaterials,
        ),
      );
    }
  }
}
