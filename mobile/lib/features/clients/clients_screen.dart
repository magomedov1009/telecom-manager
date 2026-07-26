import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';
import 'connections_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final LocalRepository repository;
  final VoidCallback onChanged;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late Future<List<ClientListItem>> clients;

  @override
  void initState() {
    super.initState();
    clients = widget.repository.clients();
  }

  void reload() {
    setState(() => clients = widget.repository.clients());
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Клиенты',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Все подключения',
            icon: const Icon(Icons.router_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ConnectionsScreen(
                  repository: widget.repository,
                  onChanged: reload,
                ),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<ClientListItem>>(
        future: clients,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('Добавьте первого клиента'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final client = snapshot.data![index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(
                    client.login,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${client.providerName} · договор ${client.contractNumber}\n'
                    '${client.address} · подключений: ${client.connections}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton.filledTonal(
                    tooltip: 'Оформить подключение',
                    icon: const Icon(Icons.add_link),
                    onPressed: () async {
                      final saved = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => _ConnectionSheet(
                          repository: widget.repository,
                          client: client,
                        ),
                      );
                      if (saved == true) reload();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _ClientSheet(repository: widget.repository),
          );
          if (saved == true) reload();
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Клиент'),
      ),
    );
  }
}

class _ClientSheet extends StatefulWidget {
  const _ClientSheet({required this.repository});

  final LocalRepository repository;

  @override
  State<_ClientSheet> createState() => _ClientSheetState();
}

class _ClientSheetState extends State<_ClientSheet> {
  final contract = TextEditingController();
  final login = TextEditingController();
  final address = TextEditingController();
  final phone = TextEditingController();
  late Future<List<LookupItem>> providers;
  String? providerId;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    providers = widget.repository.providers();
  }

  @override
  void dispose() {
    contract.dispose();
    login.dispose();
    address.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Новый клиент',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<LookupItem>>(
              future: providers,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                providerId ??= snapshot.data!.firstOrNull?.id;
                return DropdownButtonFormField<String>(
                  initialValue: providerId,
                  decoration: const InputDecoration(
                    labelText: 'Провайдер',
                    border: OutlineInputBorder(),
                  ),
                  items: snapshot.data!
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => providerId = value,
                );
              },
            ),
            const SizedBox(height: 12),
            _field(contract, 'Номер договора'),
            const SizedBox(height: 12),
            _field(login, 'Логин'),
            const SizedBox(height: 12),
            _field(address, 'Адрес'),
            const SizedBox(height: 12),
            _field(phone, 'Телефон', required: false),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving || providerId == null ? null : save,
              child: Text(saving ? 'Сохранение…' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  TextFormField _field(
    TextEditingController controller,
    String label, {
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.addClient(
        providerId: providerId!,
        contractNumber: contract.text,
        login: login.text,
        address: address.text,
        phone: phone.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      setState(() {
        saving = false;
        error = exception.toString().replaceFirst('Invalid argument(s): ', '');
      });
    }
  }
}

class _ConnectionSheet extends StatefulWidget {
  const _ConnectionSheet({required this.repository, required this.client});

  final LocalRepository repository;
  final ClientListItem client;

  @override
  State<_ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<_ConnectionSheet> {
  final price = TextEditingController(text: '0');
  final office = TextEditingController(text: '0');
  final installer = TextEditingController(text: '0');
  final comment = TextEditingController();
  late Future<List<LookupItem>> warehouses;
  List<MaterialBalance> balances = [];
  final quantities = <String, TextEditingController>{};
  String? warehouseId;
  String connectionType = 'NEW';
  bool loadingMaterials = false;
  bool saving = false;
  String? error;

  static const connectionTypes = {
    'NEW': 'Новое подключение',
    'RECONNECT': 'Переподключение',
    'ONU_REPLACE': 'Замена ONU',
    'CABLE_REPLACE': 'Замена кабеля',
    'WITHOUT_MATERIALS': 'Без материалов',
    'CUSTOM': 'Другое',
  };

  @override
  void initState() {
    super.initState();
    warehouses = widget.repository.warehouses();
  }

  @override
  void dispose() {
    price.dispose();
    office.dispose();
    installer.dispose();
    comment.dispose();
    for (final controller in quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> selectWarehouse(String? value) async {
    if (value == null) return;
    setState(() {
      warehouseId = value;
      loadingMaterials = true;
    });
    final result = await widget.repository.materialBalancesForWarehouse(value);
    for (final controller in quantities.values) {
      controller.dispose();
    }
    quantities.clear();
    for (final material in result) {
      quantities[material.materialId] = TextEditingController();
    }
    if (mounted) {
      setState(() {
        balances = result;
        loadingMaterials = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Подключение: ${widget.client.login}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: connectionType,
              decoration: const InputDecoration(
                labelText: 'Тип подключения',
                border: OutlineInputBorder(),
              ),
              items: connectionTypes.entries
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.key,
                      child: Text(item.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => connectionType = value!),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<LookupItem>>(
              future: warehouses,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return DropdownButtonFormField<String>(
                  initialValue: warehouseId,
                  decoration: const InputDecoration(
                    labelText: 'Склад списания',
                    border: OutlineInputBorder(),
                  ),
                  items: snapshot.data!
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: selectWarehouse,
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _moneyField(price, 'Стоимость')),
                const SizedBox(width: 8),
                Expanded(child: _moneyField(office, 'Офис')),
                const SizedBox(width: 8),
                Expanded(child: _moneyField(installer, 'Монтажник')),
              ],
            ),
            if (connectionType != 'WITHOUT_MATERIALS') ...[
              const SizedBox(height: 18),
              const Text(
                'Использованные материалы',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (loadingMaterials) const LinearProgressIndicator(),
              ...balances.map(
                (material) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: quantities[material.materialId],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: material.name,
                      helperText:
                          'На складе: ${material.quantity} ${material.unitName}',
                      suffixText: material.unitName,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ],
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving || warehouseId == null ? null : save,
              icon: const Icon(Icons.check),
              label: Text(saving ? 'Сохранение…' : 'Оформить подключение'),
            ),
          ],
        ),
      ),
    );
  }

  TextField _moneyField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '₽',
        border: const OutlineInputBorder(),
      ),
    );
  }

  double number(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final usedMaterials = connectionType == 'WITHOUT_MATERIALS'
          ? <ConnectionMaterialInput>[]
          : balances
                .map(
                  (material) => ConnectionMaterialInput(
                    materialId: material.materialId,
                    quantity: number(quantities[material.materialId]!.text),
                  ),
                )
                .where((item) => item.quantity > 0)
                .toList();
      await widget.repository.addConnection(
        clientId: widget.client.id,
        warehouseId: warehouseId!,
        connectionType: connectionType,
        connectionDate: DateTime.now(),
        price: number(price.text),
        officeAmount: number(office.text),
        installerAmount: number(installer.text),
        materials: usedMaterials,
        comment: comment.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      setState(() {
        saving = false;
        error = exception
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', '');
      });
    }
  }
}
