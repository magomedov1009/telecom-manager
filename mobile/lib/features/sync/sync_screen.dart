import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repositories/local_repository.dart';
import '../catalogs/catalogs_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/organization_users_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({
    super.key,
    required this.repository,
    required this.role,
    required this.onLogout,
  });
  final LocalRepository repository;
  final String role;
  final VoidCallback onLogout;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final serverController = TextEditingController();
  late Future<int> pending;

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
                  'Адрес сохраняется локально. Авторизацию и передачу данных подключим после добавления защищённого sync API.',
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
                FilledButton.icon(
                  onPressed: () async {
                    final preferences = await SharedPreferences.getInstance();
                    await preferences.setString(
                      'server_url',
                      serverController.text.trim(),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Адрес сервера сохранён')),
                      );
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Сохранить адрес'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Сейчас: только локальный режим'),
            subtitle: Text(
              'Ни одна запись не отправляется в сеть без готовой авторизации, организации и правил разрешения конфликтов.',
            ),
          ),
        ),
      ],
    );
  }
}
