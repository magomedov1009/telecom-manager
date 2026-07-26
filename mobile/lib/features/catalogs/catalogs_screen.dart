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
          _managedSection(
            'Провайдеры',
            Icons.business_outlined,
            widget.repository.providerCatalog(),
            () => _addProvider(),
            _editProvider,
            (item) => _run(() => widget.repository.toggleProvider(item.id)),
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
          _managedSection(
            'Виды допработ',
            Icons.build_outlined,
            widget.repository.extraWorkTypeCatalog(),
            () => _addWorkType(),
            _editWorkType,
            (item) =>
                _run(() => widget.repository.toggleExtraWorkType(item.id)),
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

  Widget _managedSection(
    String title,
    IconData icon,
    Future<List<CatalogItem>> future,
    VoidCallback add,
    ValueChanged<CatalogItem> edit,
    ValueChanged<CatalogItem> toggle,
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
            FutureBuilder<List<CatalogItem>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(
                  children: snapshot.data!
                      .map(
                        (item) => ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                            [
                              if (item.description?.isNotEmpty == true)
                                item.description!,
                              item.isActive ? 'Активен' : 'Отключён',
                            ].join(' · '),
                          ),
                          leading: Icon(
                            item.isActive
                                ? Icons.check_circle_outline
                                : Icons.pause_circle_outline,
                            color: item.isActive ? Colors.green : Colors.grey,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') edit(item);
                              if (value == 'toggle') toggle(item);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Редактировать'),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                  item.isActive ? 'Отключить' : 'Включить',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
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
    await _providerDialog();
  }

  Future<void> _editProvider(CatalogItem item) async {
    await _providerDialog(item);
  }

  Future<void> _providerDialog([CatalogItem? initial]) async {
    final name = TextEditingController(text: initial?.name ?? '');
    final description = TextEditingController(text: initial?.description ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          initial == null ? 'Новый провайдер' : 'Редактирование провайдера',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Описание'),
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
    );
    final cleanName = name.text;
    final cleanDescription = description.text;
    name.dispose();
    description.dispose();
    if (saved != true) return;
    await _run(
      () => initial == null
          ? widget.repository.addProvider(
              cleanName,
              description: cleanDescription,
            )
          : widget.repository.updateProvider(
              providerId: initial.id,
              name: cleanName,
              description: cleanDescription,
            ),
    );
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

  Future<void> _editWorkType(CatalogItem item) => _addWorkType(item);

  Future<void> _addWorkType([CatalogItem? initial]) async {
    final name = TextEditingController(text: initial?.name ?? '');
    final description = TextEditingController(text: initial?.description ?? '');
    final price = TextEditingController(
      text: (initial?.defaultPrice ?? 0).toString(),
    );
    final officeAmount = TextEditingController(
      text: (initial?.defaultOfficeAmount ?? 0).toString(),
    );
    bool requiresMaterials = initial?.requiresMaterials ?? false;
    bool requiresEquipment = initial?.requiresEquipment ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            initial == null
                ? 'Новый вид допработы'
                : 'Редактирование вида допработы',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Описание'),
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
              TextField(
                controller: officeAmount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Доля офиса по умолчанию',
                ),
              ),
              CheckboxListTile(
                value: requiresMaterials,
                title: const Text('Использует материалы'),
                onChanged: (value) =>
                    setDialogState(() => requiresMaterials = value ?? false),
              ),
              CheckboxListTile(
                value: requiresEquipment,
                title: const Text('Использует оборудование'),
                onChanged: (value) =>
                    setDialogState(() => requiresEquipment = value ?? false),
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
    final cleanDescription = description.text;
    final defaultPrice = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    final defaultOfficeAmount =
        double.tryParse(officeAmount.text.replaceAll(',', '.')) ?? 0;
    name.dispose();
    description.dispose();
    price.dispose();
    officeAmount.dispose();
    if (saved == true) {
      await _run(
        () => initial == null
            ? widget.repository.addExtraWorkType(
                name: cleanName,
                description: cleanDescription,
                defaultPrice: defaultPrice,
                defaultOfficeAmount: defaultOfficeAmount,
                requiresMaterials: requiresMaterials,
                requiresEquipment: requiresEquipment,
              )
            : widget.repository.updateExtraWorkType(
                workTypeId: initial.id,
                name: cleanName,
                description: cleanDescription,
                defaultPrice: defaultPrice,
                defaultOfficeAmount: defaultOfficeAmount,
                requiresMaterials: requiresMaterials,
                requiresEquipment: requiresEquipment,
              ),
      );
    }
  }
}
