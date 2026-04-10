/// Stub for web platform - reading files from filesystem is not supported on web.
/// Use [importFromZipBytes] instead.

Future<Map<String, String>> readZipContent(String zipPath) async {
  throw UnsupportedError(
      'File system access is not available on web. Use importFromZipBytes() instead.');
}

Future<Map<String, String>> readDirectoryContent(String dirPath) async {
  throw UnsupportedError(
      'File system access is not available on web. Use importFromZipBytes() instead.');
}
