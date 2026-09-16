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
      appBar: AppBar(
        title: const Text('Долги по материалам'),
        actions: [
          IconButton(
            tooltip: 'Журнал списаний',
            icon: const Icon(Icons.history),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      _SettlementJournalScreen(repository: widget.repository),
                ),
              );
              if (mounted) {
                setState(
                  () => settlements = widget.repository.materialSettlements(),
                );
              }
            },
          ),
        ],
      ),
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
      if (mounted) {
        setState(() => settlements = widget.repository.materialSettlements());
      }
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
      quantityController.dispose();
      commentController.dispose();
    }
  }
}

class _SettlementJournalScreen extends StatefulWidget {
  const _SettlementJournalScreen({required this.repository});
  final LocalRepository repository;
  @override
  State<_SettlementJournalScreen> createState() =>
      _SettlementJournalScreenState();
}

class _SettlementJournalScreenState extends State<_SettlementJournalScreen> {
  late Future<List<MaterialSettlementJournalItem>> items;
  @override
  void initState() {
    super.initState();
    items = widget.repository.materialSettlementJournal();
  }

  String amount(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Журнал списаний долгов')),
    body: FutureBuilder<List<MaterialSettlementJournalItem>>(
      future: items,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('Списаний ещё не было'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final item = snapshot.data![index];
            return Card(
              child: ListTile(
                title: Text('${item.debtorName} → ${item.creditorName}'),
                subtitle: Text(
                  '${item.materialName} · ${item.date.day.toString().padLeft(2, '0')}.${item.date.month.toString().padLeft(2, '0')}.${item.date.year}${item.comment?.isNotEmpty == true ? '\n${item.comment}' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${amount(item.quantity)} ${item.unitName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Удалить',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Удалить списание?'),
                            content: const Text(
                              'Списание будет отменено, а долг по материалу восстановлен.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Отмена'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Удалить'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) {
                          return;
                        }
                        await widget.repository.deleteMaterialSettlement(
                          item.id,
                        );
                        if (mounted) {
                          setState(
                            () => items = widget.repository
                                .materialSettlementJournal(),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
