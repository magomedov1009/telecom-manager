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
          (values) => (
            values[0] as List<LookupItem>,
            values[1] as List<UserItem>,
            values[2] as String,
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
        final users = snapshot.data!.$2;
        final names = {for (final user in users) user.id: user.fullName};
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
                  tooltip: 'Добавить организацию',
                  icon: const Icon(Icons.add_business),
                  onPressed: addOrganization,
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: snapshot.data!.$3,
              items: snapshot.data!.$1
                  .map(
                    (organization) => DropdownMenuItem(
                      value: organization.id,
                      child: Text(organization.name),
                    ),
                  )
                  .toList(),
              onChanged: (id) async {
                if (id == null) return;
                await _run(() => widget.repository.switchOrganization(id));
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
                  tooltip: 'Добавить пользователя',
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: () => userDialog(users: users),
                ),
              ],
            ),
            ...users.map(
              (user) => Card(
                child: ListTile(
                  isThreeLine: true,
                  leading: CircleAvatar(
                    child: Icon(
                      user.isActive ? Icons.person_outline : Icons.person_off,
                    ),
                  ),
                  title: Text(user.fullName),
                  subtitle: Text(
                    [
                      '${user.username} · ${roleLabel(user.role)} · '
                          '${user.isActive ? 'активен' : 'отключён'}',
                      if (user.managerId != null)
                        'Менеджер: ${names[user.managerId] ?? 'не найден'}',
                      if (user.comment?.isNotEmpty == true) user.comment!,
                      'Создан: ${formatDate(user.createdAt)}'
                          '${user.lastLoginAt == null ? '' : ' · вход: ${formatDate(user.lastLoginAt!)}'}',
                    ].join('\n'),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await userDialog(user: user, users: users);
                      } else if (action == 'password') {
                        await changePassword(user);
                      } else {
                        await _run(() => widget.repository.toggleUser(user.id));
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Изменить'),
                      ),
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

  String formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String errorText(Object error) {
    if (error is ArgumentError) return error.message.toString();
    return error.toString();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorText(error))));
    }
  }

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
      await _run(() => widget.repository.addOrganization(value));
    }
  }

  Future<void> userDialog({
    UserItem? user,
    required List<UserItem> users,
  }) async {
    final username = TextEditingController(text: user?.username);
    final fullName = TextEditingController(text: user?.fullName);
    final password = TextEditingController();
    final comment = TextEditingController(text: user?.comment);
    var role = user?.role ?? 'installer';
    var managerId = user?.managerId;
    var isActive = user?.isActive ?? true;
    final managers = users
        .where((item) => item.role == 'manager' && item.isActive)
        .toList();
    if (!managers.any((item) => item.id == managerId)) managerId = null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(user == null ? 'Новый пользователь' : 'Пользователь'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fullName,
                  decoration: const InputDecoration(labelText: 'ФИО'),
                ),
                if (user == null)
                  TextField(
                    controller: username,
                    decoration: const InputDecoration(labelText: 'Логин'),
                  )
                else
                  TextFormField(
                    initialValue: user.username,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Логин'),
                  ),
                if (user == null)
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Пароль'),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Роль'),
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
                  onChanged: (value) => setDialogState(() {
                    role = value!;
                    if (role != 'installer') managerId = null;
                  }),
                ),
                if (role == 'installer')
                  DropdownButtonFormField<String?>(
                    initialValue: managerId,
                    decoration: const InputDecoration(
                      labelText: 'Менеджер (необязательно)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Не назначен'),
                      ),
                      ...managers.map(
                        (manager) => DropdownMenuItem<String?>(
                          value: manager.id,
                          child: Text(manager.fullName),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => managerId = value),
                  ),
                TextField(
                  controller: comment,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Комментарий'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Активен'),
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(user == null ? 'Создать' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
    final login = username.text;
    final name = fullName.text;
    final secret = password.text;
    final note = comment.text;
    username.dispose();
    fullName.dispose();
    password.dispose();
    comment.dispose();
    if (saved != true) return;
    if (user == null) {
      await _run(
        () => widget.repository.addUser(
          username: login,
          fullName: name,
          role: role,
          password: secret,
          managerId: managerId,
          comment: note,
          isActive: isActive,
        ),
      );
    } else {
      await _run(
        () => widget.repository.updateUser(
          userId: user.id,
          fullName: name,
          role: role,
          managerId: managerId,
          comment: note,
          isActive: isActive,
        ),
      );
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
      await _run(() => widget.repository.changeUserPassword(user.id, password));
    }
  }
}
