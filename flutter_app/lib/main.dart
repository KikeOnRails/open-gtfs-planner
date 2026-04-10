import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database factory for desktop/web platforms
  await initDatabaseFactory();

  // Ensure database is open and schema is created
  await AppDatabase.instance;

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
