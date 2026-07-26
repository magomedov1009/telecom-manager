import 'package:flutter/material.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/repositories/local_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  final repository = LocalRepository(database);
  await repository.initialize();
  runApp(TelecomManagerApp(repository: repository));
}
