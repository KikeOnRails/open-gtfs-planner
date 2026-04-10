/// Stub for web platform - no-op database initialization.
Future<void> platformInitDatabase() async {
  // On web, sqflite uses IndexedDB via sqflite_common_ffi_web.
  // No explicit initialization is needed; the package registers itself.
}

/// No-op on web - directories don't exist on web.
Future<void> ensureDirectory(String path) async {}
