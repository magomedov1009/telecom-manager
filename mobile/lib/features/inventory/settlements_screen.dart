import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class SettlementsScreen extends StatefulWidget {
  const SettlementsScreen({super.key, required this.repository});

  final LocalRepository repository;

  @override
  State<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends State<SettlementsScreen> {
  late Future<List<MaterialSettlement>> settlements;

  @override
  void initState() {
    super.initState();
    settlements = widget.repository.materialSettlements();
  }

  String quantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Долги по материалам')),
      body: FutureBuilder<List<MaterialSettlement>>(
        future: settlements,
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
                  onTap: () => settle(item),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> settle(MaterialSettlement debt) async {
    final quantityController = TextEditingController();
    final commentController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Закрыть долг материалом'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${debt.debtorName} → ${debt.creditorName}\n${debt.materialName}: ${quantity(debt.quantity)} ${debt.unitName}',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Списать количество',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(
                labelText: 'Причина или комментарий',
              ),
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
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final value =
        double.tryParse(quantityController.text.replaceAll(',', '.')) ?? 0;
    try {
      await widget.repository.settleMaterialDebt(
        debt: debt,
        quantity: value,
        comment: commentController.text,
      );
      if (mounted)
        setState(() => settlements = widget.repository.materialSettlements());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Invalid argument(s): ', ''),
            ),
          ),
        );
    } finally {
      quantityController.dispose();
      commentController.dispose();
    }
  }
}
