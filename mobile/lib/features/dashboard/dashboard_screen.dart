import 'package:flutter/material.dart';

import '../../core/repositories/local_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repository});

  final LocalRepository repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final Future<DashboardSummary> summary;

  @override
  void initState() {
    super.initState();
    summary = widget.repository.dashboardSummary();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardSummary>(
      future: summary,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Телеком Менеджер',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              data.organizationName,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFFEFF4FF),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.smartphone)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Локальный режим',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Работает без интернета · ${data.pendingChanges} изменений ожидают синхронизации',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _MetricCard(
                  label: 'Провайдеры',
                  value: data.providers,
                  icon: Icons.business_outlined,
                ),
                _MetricCard(
                  label: 'Склады',
                  value: data.warehouses,
                  icon: Icons.warehouse_outlined,
                ),
                _MetricCard(
                  label: 'Клиенты',
                  value: data.clients,
                  icon: Icons.people_outline,
                ),
                _MetricCard(
                  label: 'Подключения',
                  value: data.connections,
                  icon: Icons.add_link,
                ),
                _MetricCard(
                  label: 'В очереди',
                  value: data.pendingChanges,
                  icon: Icons.cloud_upload_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Автономная работа'),
                subtitle: Text(
                  'Склад, клиенты и подключения сохраняются на телефоне. Интернет для работы не требуется.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            Text(
              '$value',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
