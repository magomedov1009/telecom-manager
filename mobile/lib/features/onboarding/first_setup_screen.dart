import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class FirstSetupScreen extends StatefulWidget {
  const FirstSetupScreen({
    super.key,
    required this.repository,
    required this.onComplete,
  });

  final LocalRepository repository;
  final VoidCallback onComplete;

  @override
  State<FirstSetupScreen> createState() => _FirstSetupScreenState();
}

class _FirstSetupScreenState extends State<FirstSetupScreen> {
  final providerController = TextEditingController();
  final warehouseController = TextEditingController(text: 'Основной склад');
  bool saving = false;

  @override
  void dispose() {
    providerController.dispose();
    warehouseController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await widget.repository.createFirstProviderAndWarehouse(
        providerName: providerController.text,
        warehouseName: warehouseController.text,
      );
      if (mounted) widget.onComplete();
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
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.rocket_launch_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Начнём работу',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Создайте своего первого провайдера и склад. Демонстрационных данных в приложении нет.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: providerController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Название провайдера',
                      hintText: 'Например, Мой Провайдер',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: warehouseController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Первый склад',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Создать и продолжить'),
                  ),
                  TextButton(
                    onPressed: saving ? null : widget.onComplete,
                    child: const Text('У меня уже есть сервер'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
