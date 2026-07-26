import 'package:flutter/material.dart';
import '../../core/repositories/local_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.repository,
    required this.onLogin,
  });
  final LocalRepository repository;
  final ValueChanged<UserItem> onLogin;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  String? organizationId, error;
  bool loading = false;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.router,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Телеком Менеджер',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 24),
                FutureBuilder<List<LookupItem>>(
                  future: widget.repository.organizations(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    organizationId ??= snapshot.data!.firstOrNull?.id;
                    return DropdownButtonFormField<String>(
                      initialValue: organizationId,
                      decoration: const InputDecoration(
                        labelText: 'Организация',
                        border: OutlineInputBorder(),
                      ),
                      items: snapshot.data!
                          .map(
                            (o) => DropdownMenuItem(
                              value: o.id,
                              child: Text(o.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => organizationId = v,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Логин',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  onSubmitted: (_) => login(),
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: loading ? null : login,
                  child: Text(loading ? 'Вход…' : 'Войти'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Первый вход: admin / 0000',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> login() async {
    if (organizationId == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    await widget.repository.switchOrganization(organizationId!);
    final user = await widget.repository.authenticate(
      username.text,
      password.text,
    );
    if (!mounted) return;
    if (user == null) {
      setState(() {
        loading = false;
        error = 'Неверный логин или пароль';
      });
    } else {
      widget.onLogin(user);
    }
  }
}
