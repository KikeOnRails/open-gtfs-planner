import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Stub for web platform - no-op database initialization.
Future<void> platformInitDatabase() async {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}

/// No-op on web - directories don't exist on web.
Future<void> ensureDirectory(String path) async {}
