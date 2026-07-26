import 'package:flutter/material.dart';

import 'core/repositories/local_repository.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/finance/finance_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/clients/clients_screen.dart';
import 'features/sync/sync_screen.dart';

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
      home: AppShell(repository: repository),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.repository});

  final LocalRepository repository;

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
        onChanged: refresh,
      ),
      SyncScreen(
        key: ValueKey('sync-$refreshKey'),
        repository: widget.repository,
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
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync),
            label: 'Синхронизация',
          ),
        ],
      ),
    );
  }
}
