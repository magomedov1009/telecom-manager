import 'package:flutter/material.dart';

import 'core/repositories/local_repository.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/finance/finance_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/clients/clients_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/works/works_screen.dart';
import 'features/auth/login_screen.dart';

class TelecomManagerApp extends StatelessWidget {
  const TelecomManagerApp({super.key, required this.repository});

  final LocalRepository repository;

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF155EEF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Телеком Менеджер',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            side: BorderSide(color: Color(0xFFE4E7EC)),
          ),
        ),
        useMaterial3: true,
      ),
      home: _AuthGate(repository: repository),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.repository});
  final LocalRepository repository;
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  UserItem? user;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    widget.repository.currentUser().then((value) {
      if (mounted) {
        setState(() {
          user = value;
          loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user == null) {
      return LoginScreen(
        repository: widget.repository,
        onLogin: (value) => setState(() => user = value),
      );
    }
    return AppShell(
      repository: widget.repository,
      user: user!,
      onLogout: () async {
        await widget.repository.logout();
        if (mounted) setState(() => user = null);
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.user,
    required this.onLogout,
  });

  final LocalRepository repository;
  final UserItem user;
  final VoidCallback onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  int refreshKey = 0;

  void refresh() => setState(() => refreshKey++);

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        key: ValueKey('dashboard-$refreshKey'),
        repository: widget.repository,
      ),
      InventoryScreen(
        key: ValueKey('inventory-$refreshKey'),
        repository: widget.repository,
        onChanged: refresh,
      ),
      ClientsScreen(
        key: ValueKey('clients-$refreshKey'),
        repository: widget.repository,
        onChanged: refresh,
      ),
      FinanceScreen(
        key: ValueKey('finance-$refreshKey'),
        repository: widget.repository,
        role: widget.user.role,
        onChanged: refresh,
      ),
      WorksScreen(
        key: ValueKey('works-$refreshKey'),
        repository: widget.repository,
        onChanged: refresh,
      ),
      SyncScreen(
        key: ValueKey('sync-$refreshKey'),
        repository: widget.repository,
        role: widget.user.role,
        onLogout: widget.onLogout,
        onChanged: refresh,
      ),
    ];
    return Scaffold(
      body: SafeArea(child: screens[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Склад',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Клиенты',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Финансы',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Работы',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync),
            label: 'Синхронизация',
          ),
        ],
      ),
    );
  }
}
