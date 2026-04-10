import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Platform-specific database initialization for dart:io platforms.
Future<void> platformInitDatabase() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Android/iOS: default sqflite works without modification
}

/// Creates the directory at [path] if it doesn't exist.
Future<void> ensureDirectory(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
}
