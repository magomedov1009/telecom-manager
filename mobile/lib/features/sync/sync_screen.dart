import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repositories/local_repository.dart';
import '../../core/sync/sync_service.dart';
import '../../core/update/app_update_service.dart';
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
  late String effectiveRole;
  bool busy = false;
  String? statusMessage;
  late Future<AppUpdate> update;
  double? updateProgress;

  @override
  void initState() {
    super.initState();
    pending = widget.repository.pendingChanges();
    effectiveRole = widget.role;
    _loadSettings();
    update = AppUpdateService().check();
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
        FutureBuilder<AppUpdate>(
          future: update,
          builder: (context, snapshot) {
            final info = snapshot.data;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.system_update_outlined),
                title: Text(
                  info?.available == true
                      ? 'Доступна версия ${info!.latestVersion}'
                      : 'Обновление приложения',
                ),
                subtitle: updateProgress != null
                    ? LinearProgressIndicator(value: updateProgress)
                    : Text(
                        snapshot.hasError
                            ? 'Не удалось проверить. Нажмите, чтобы повторить'
                            : info == null
                            ? 'Проверка версии…'
                            : info.available
                            ? 'Установлена ${info.currentVersion}. Нажмите, чтобы обновить'
                            : 'Установлена актуальная версия ${info.currentVersion}',
                      ),
                trailing: info?.available == true
                    ? const Icon(Icons.download_outlined)
                    : const Icon(Icons.refresh),
                onTap: updateProgress != null
                    ? null
                    : () => checkOrInstallUpdate(info),
              ),
            );
          },
        ),
        if (effectiveRole == 'admin')
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
        if (effectiveRole == 'admin')
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.add_business_outlined),
                  title: const Text('Создать организацию на сервере'),
                  subtitle: const Text('Отдельное пространство для города'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy ? null : createServerOrganization,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: const Text('Участники серверной организации'),
                  subtitle: const Text('Приглашение, роли и удаление доступа'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy ? null : showMembers,
                ),
              ],
            ),
          ),
        if (effectiveRole != 'installer')
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
        if (effectiveRole == 'admin')
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

  Future<void> checkOrInstallUpdate(AppUpdate? info) async {
    if (info == null || !info.available) {
      setState(() => update = AppUpdateService().check());
      return;
    }
    try {
      setState(() => updateProgress = 0);
      await AppUpdateService().downloadAndInstall(
        info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            updateProgress = total > 0 ? received / total : null;
          });
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => updateProgress = null);
    }
  }

  Future<void> connect() async {
    setState(() {
      busy = true;
      statusMessage = null;
    });
    try {
      final normalizedUrl = SyncService.normalizeServerUrl(
        serverController.text,
      );
      if (normalizedUrl.isEmpty) {
        throw StateError('Укажите адрес сервера');
      }
      serverController.text = normalizedUrl;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('server_url', normalizedUrl);
      var connection = await service().connect(
        username: usernameController.text,
        password: passwordController.text,
        deviceName: 'Android Telecom Manager',
      );
      if (connection.organizations.length > 1 && mounted) {
        final selected = await selectOrganization(
          connection.organizations,
          connection.organizationId,
        );
        if (selected != null && selected != connection.organizationId) {
          connection = await service().connect(
            username: usernameController.text,
            password: passwordController.text,
            deviceName: 'Android Telecom Manager',
            organizationId: selected,
          );
        }
      }
      final syncResult = await service().synchronize();
      widget.onChanged();
      final localUser = await widget.repository.currentUser();
      setState(() {
        effectiveRole = localUser?.role ?? effectiveRole;
        statusMessage =
            'Устройство подключено. Загружено с сервера: '
            '${syncResult.received}.';
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

  Future<int?> selectOrganization(
    List<ServerOrganization> organizations,
    int current,
  ) async {
    var selected = current;
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Выберите организацию'),
          content: DropdownButtonFormField<int>(
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Организация'),
            items: organizations
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text('${item.name} · ${roleLabel(item.role)}'),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setDialogState(() => selected = value ?? selected),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Подключить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> createServerOrganization() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая серверная организация'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Название или город'),
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
    final name = controller.text;
    controller.dispose();
    if (saved != true) return;
    setState(() => busy = true);
    try {
      final created = await service().createOrganization(name);
      await service().connect(
        username: usernameController.text,
        password: passwordController.text,
        deviceName: 'Android Telecom Manager',
        organizationId: created.id,
      );
      widget.onChanged();
      final localUser = await widget.repository.currentUser();
      if (mounted) {
        setState(() {
          effectiveRole = localUser?.role ?? effectiveRole;
          statusMessage = 'Создана и выбрана организация «${created.name}»';
          pending = widget.repository.pendingChanges();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              statusMessage = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showMembers() async {
    try {
      final members = await service().members();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Участники'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final member in members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(member.fullName),
                    subtitle: Text(
                      '${member.username} · ${roleLabel(member.role)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Удалить доступ',
                      onPressed: () async {
                        try {
                          await service().removeMember(member.userId);
                          if (context.mounted) Navigator.pop(context);
                          if (mounted) {
                            setState(
                              () =>
                                  statusMessage = 'Доступ пользователя удалён',
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.person_remove_outlined),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                inviteMember();
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Пригласить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              statusMessage = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> inviteMember() async {
    final username = TextEditingController();
    var role = 'installer';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Пригласить пользователя сайта'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: username,
                decoration: const InputDecoration(labelText: 'Логин'),
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
                onChanged: (value) =>
                    setDialogState(() => role = value ?? role),
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
              child: const Text('Пригласить'),
            ),
          ],
        ),
      ),
    );
    final login = username.text;
    username.dispose();
    if (saved != true) return;
    try {
      final member = await service().addMember(username: login, role: role);
      if (mounted) {
        setState(
          () => statusMessage =
              '${member.fullName} добавлен: ${roleLabel(member.role)}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              statusMessage = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  String roleLabel(String role) =>
      const {
        'admin': 'Администратор',
        'manager': 'Менеджер',
        'installer': 'Монтажник',
      }[role] ??
      role;

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
