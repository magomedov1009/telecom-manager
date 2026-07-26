import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repositories/local_repository.dart';
import '../../core/sync/sync_service.dart';
import '../catalogs/catalogs_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/organization_users_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({
    super.key,
    required this.repository,
    required this.role,
    required this.onLogout,
    required this.onChanged,
  });
  final LocalRepository repository;
  final String role;
  final VoidCallback onLogout;
  final VoidCallback onChanged;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final serverController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  late Future<int> pending;
  bool busy = false;
  String? statusMessage;

  @override
  void initState() {
    super.initState();
    pending = widget.repository.pendingChanges();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    serverController.text = preferences.getString('server_url') ?? '';
  }

  @override
  void dispose() {
    serverController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.role == 'admin')
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Справочники'),
              subtitle: const Text(
                'Провайдеры, склады, материалы и виды работ',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CatalogsScreen(repository: widget.repository),
                ),
              ),
            ),
          ),
        if (widget.role != 'installer')
          Card(
            child: ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Отчёты'),
              subtitle: const Text('Периоды, провайдеры и экспорт CSV'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReportsScreen(repository: widget.repository),
                ),
              ),
            ),
          ),
        if (widget.role == 'admin')
          Card(
            child: ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Организации и пользователи'),
              subtitle: const Text('Роли и отдельные рабочие пространства'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      OrganizationUsersScreen(repository: widget.repository),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Выйти'),
            onTap: widget.onLogout,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Синхронизация',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Локальная база работает независимо от сервера.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        FutureBuilder<int>(
          future: pending,
          builder: (context, snapshot) => Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: const CircleAvatar(
                child: Icon(Icons.cloud_upload_outlined),
              ),
              title: const Text('Ожидают отправки'),
              subtitle: const Text(
                'Изменения безопасно хранятся на устройстве',
              ),
              trailing: Text(
                '${snapshot.data ?? 0}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Сервер организации',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Укажите адрес сервера и данные пользователя сайта.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: serverController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Например, https://telecom.example.ru',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Логин сайта',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль сайта',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : connect,
                  icon: const Icon(Icons.link),
                  label: const Text('Подключить устройство'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : synchronize,
                  icon: const Icon(Icons.sync),
                  label: const Text('Синхронизировать сейчас'),
                ),
                if (statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(statusMessage!),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Автономный режим сохраняется'),
            subtitle: Text(
              'Без интернета записи остаются в очереди и отправляются при следующей синхронизации.',
            ),
          ),
        ),
      ],
    );
  }

  SyncService service() => SyncService(
    repository: widget.repository,
    serverUrl: serverController.text.trim(),
  );

  Future<void> connect() async {
    setState(() {
      busy = true;
      statusMessage = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('server_url', serverController.text.trim());
      await service().connect(
        username: usernameController.text,
        password: passwordController.text,
        deviceName: 'Android Telecom Manager',
      );
      widget.onChanged();
      setState(() {
        statusMessage =
            'Устройство подключено. Создано отдельное серверное '
            'рабочее пространство.';
        pending = widget.repository.pendingChanges();
      });
    } catch (error) {
      setState(
        () => statusMessage = error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> synchronize() async {
    setState(() {
      busy = true;
      statusMessage = null;
    });
    try {
      final result = await service().synchronize();
      widget.onChanged();
      setState(() {
        statusMessage =
            'Отправлено: ${result.sent}, получено: ${result.received}, конфликтов: ${result.conflicts}';
        pending = widget.repository.pendingChanges();
      });
    } catch (error) {
      setState(
        () => statusMessage = error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
