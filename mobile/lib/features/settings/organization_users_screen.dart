import 'package:flutter/material.dart';
import '../../core/repositories/local_repository.dart';

class OrganizationUsersScreen extends StatefulWidget {
  const OrganizationUsersScreen({super.key, required this.repository});
  final LocalRepository repository;
  @override
  State<OrganizationUsersScreen> createState() =>
      _OrganizationUsersScreenState();
}

class _OrganizationUsersScreenState extends State<OrganizationUsersScreen> {
  late Future<(List<LookupItem>, List<UserItem>, String)> data;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
    data =
        Future.wait([
          widget.repository.organizations(),
          widget.repository.users(),
          widget.repository.organizationId,
        ]).then(
          (v) => (
            v[0] as List<LookupItem>,
            v[1] as List<UserItem>,
            v[2] as String,
          ),
        );
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Организации и пользователи')),
    body: FutureBuilder<(List<LookupItem>, List<UserItem>, String)>(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Организация',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_business),
                  onPressed: addOrganization,
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: snapshot.data!.$3,
              items: snapshot.data!.$1
                  .map(
                    (o) => DropdownMenuItem(value: o.id, child: Text(o.name)),
                  )
                  .toList(),
              onChanged: (id) async {
                if (id != null) {
                  await widget.repository.switchOrganization(id);
                  reload();
                }
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Пользователи',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: addUser,
                ),
              ],
            ),
            ...snapshot.data!.$2.map(
              (user) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(user.fullName),
                  subtitle: Text(
                    '${user.username} · ${roleLabel(user.role)} · '
                    '${user.isActive ? 'активен' : 'отключён'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'password') {
                        await changePassword(user);
                      } else {
                        await widget.repository.toggleUser(user.id);
                        reload();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'password',
                        child: Text('Сменить пароль'),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(user.isActive ? 'Отключить' : 'Включить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  String roleLabel(String role) =>
      const {
        'admin': 'Администратор',
        'manager': 'Менеджер',
        'installer': 'Монтажник',
      }[role] ??
      role;

  Future<void> addOrganization() async {
    final name = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая организация'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    final value = name.text;
    name.dispose();
    if (saved == true) {
      await widget.repository.addOrganization(value);
      reload();
    }
  }

  Future<void> addUser() async {
    final username = TextEditingController(),
        fullName = TextEditingController(),
        password = TextEditingController();
    String role = 'installer';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новый пользователь'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fullName,
                decoration: const InputDecoration(labelText: 'ФИО'),
              ),
              TextField(
                controller: username,
                decoration: const InputDecoration(labelText: 'Логин'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль'),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                items: const [
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Администратор'),
                  ),
                  DropdownMenuItem(value: 'manager', child: Text('Менеджер')),
                  DropdownMenuItem(
                    value: 'installer',
                    child: Text('Монтажник'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => role = v!),
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
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    final login = username.text, name = fullName.text, secret = password.text;
    username.dispose();
    fullName.dispose();
    password.dispose();
    if (saved == true) {
      await widget.repository.addUser(
        username: login,
        fullName: name,
        role: role,
        password: secret,
      );
      reload();
    }
  }

  Future<void> changePassword(UserItem user) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Пароль: ${user.fullName}'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Новый пароль'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    final password = controller.text;
    controller.dispose();
    if (saved == true) {
      await widget.repository.changeUserPassword(user.id, password);
      reload();
    }
  }
}
