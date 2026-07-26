import 'package:flutter/material.dart';
import '../../core/repositories/local_repository.dart';

class InventoryHistoryScreen extends StatelessWidget {
  const InventoryHistoryScreen({super.key, required this.repository});
  final LocalRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('История склада')),
    body: FutureBuilder<List<InventoryHistoryItem>>(
      future: repository.inventoryHistory(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = snapshot.data![index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    item.quantity > 0 ? Icons.south_west : Icons.north_east,
                  ),
                ),
                title: Text(item.materialName),
                subtitle: Text('${item.warehouseName} · ${item.operationType}'),
                trailing: Text(
                  '${item.quantity > 0 ? '+' : ''}${item.quantity}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: item.quantity > 0 ? Colors.green : Colors.red,
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
