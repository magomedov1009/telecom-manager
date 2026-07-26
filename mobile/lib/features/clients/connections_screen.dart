import 'package:flutter/material.dart';
import '../../core/repositories/local_repository.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });
  final LocalRepository repository;
  final VoidCallback onChanged;
  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late Future<List<ConnectionListItem>> data;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() => data = widget.repository.connections());
  static const labels = {
    'NEW': 'Новое подключение',
    'RECONNECT': 'Переподключение',
    'ONU_REPLACE': 'Замена ONU',
    'CABLE_REPLACE': 'Замена кабеля',
    'WITHOUT_MATERIALS': 'Без материалов',
    'CUSTOM': 'Другое',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подключения')),
    body: FutureBuilder<List<ConnectionListItem>>(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('Подключений пока нет'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = snapshot.data![index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.router_outlined)),
                title: Text(item.clientLogin),
                subtitle: Text(
                  '${item.providerName} · ${labels[item.connectionType] ?? item.connectionType}\n${item.address}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (_) => remove(item),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> remove(ConnectionListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подключение?'),
        content: const Text(
          'Материалы вернутся на склад, финансовые начисления будут отменены.',
        ),
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
    if (confirmed == true) {
      await widget.repository.deleteConnection(item.id);
      widget.onChanged();
      reload();
    }
  }
}
