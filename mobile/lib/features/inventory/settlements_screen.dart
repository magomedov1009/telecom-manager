import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class SettlementsScreen extends StatelessWidget {
  const SettlementsScreen({super.key, required this.repository});

  final LocalRepository repository;

  String quantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Долги по материалам')),
      body: FutureBuilder<List<MaterialSettlement>>(
        future: repository.materialSettlements(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Взаимных долгов нет.\nВозвраты и встречные перемещения зачтены.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = snapshot.data![index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const CircleAvatar(
                    child: Icon(Icons.balance_outlined),
                  ),
                  title: Text(
                    '${item.debtorName} должен ${item.creditorName}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(item.materialName),
                  trailing: Text(
                    '${quantity(item.quantity)} ${item.unitName}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
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
}
