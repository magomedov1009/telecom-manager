import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repositories/local_repository.dart';
import '../../core/sync/sync_service.dart';

class CloudAccessScreen extends StatefulWidget {
  const CloudAccessScreen({
    super.key,
    required this.repository,
    required this.onConnected,
  });

  final LocalRepository repository;
  final ValueChanged<UserItem> onConnected;

  @override
  State<CloudAccessScreen> createState() => _CloudAccessScreenState();
}

class _CloudAccessScreenState extends State<CloudAccessScreen> {
  final server = TextEditingController();
  final organization = TextEditingController();
  final fullName = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  bool registration = false;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    server.dispose();
    organization.dispose();
    fullName.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final serverUrl = SyncService.normalizeServerUrl(server.text);
    if (serverUrl.isEmpty) {
      setState(() => error = 'Укажите адрес облачного сервера');
      return;
    }
    setState(() {
      error = null;
      loading = true;
    });
    try {
      final service = SyncService(
        repository: widget.repository,
        serverUrl: serverUrl,
      );
      if (registration) {
        await service.register(
          organizationName: organization.text,
          fullName: fullName.text,
          username: username.text,
          password: password.text,
          deviceName: 'Android Telecom Manager',
        );
      } else {
        await service.connect(
          username: username.text,
          password: password.text,
          deviceName: 'Android Telecom Manager',
        );
      }
      await service.synchronize();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('server_url', serverUrl);
      final user = await widget.repository.currentUser();
      if (!mounted) return;
      if (user == null) throw StateError('Не удалось открыть организацию');
      widget.onConnected(user);
      Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(registration ? 'Облачная организация' : 'Вход в облако'),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cloud_outlined, size: 56),
                const SizedBox(height: 14),
                Text(
                  registration
                      ? 'Создайте организацию'
                      : 'Подключитесь к облаку',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: server,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Адрес облачного сервера',
                    hintText: 'https://cloud.example.ru',
                  ),
                ),
                if (registration) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: organization,
                    decoration: const InputDecoration(
                      labelText: 'Название компании',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fullName,
                    decoration: const InputDecoration(labelText: 'Ваше имя'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Логин'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: registration
                        ? 'Пароль (минимум 6 символов)'
                        : 'Пароль',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: loading ? null : submit,
                  child: Text(
                    loading
                        ? 'Подключение…'
                        : registration
                        ? 'Создать и подключиться'
                        : 'Войти',
                  ),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => setState(() => registration = !registration),
                  child: Text(
                    registration
                        ? 'У меня уже есть аккаунт'
                        : 'Создать новую организацию',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
