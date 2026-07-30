import 'dart:io';
import 'dart:ffi';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

/// Platform-specific database initialization for dart:io platforms.
Future<void> platformInitDatabase() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    if (Platform.isLinux) {
      // Most Linux systems ship libsqlite3.so.0 without the unversioned dev symlink.
      sqlite3_open.open.overrideFor(
        sqlite3_open.OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
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
