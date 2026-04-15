import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// Reads a GTFS zip file and returns a map of filename -> CSV content.
Future<Map<String, String>> readZipContent(String zipPath) async {
  final bytes = File(zipPath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  final content = <String, String>{};

  for (final file in archive) {
    if (file.isFile && file.name.toLowerCase().endsWith('.txt')) {
      final baseName =
          file.name.split('/').last.replaceAll('.txt', '').toLowerCase();
      try {
        final fileBytes = file.content as Uint8List;
        // Use UTF-8 decoding to properly handle BOM and special characters
        content[baseName] = utf8.decode(fileBytes, allowMalformed: true);
      } catch (e) {
        debugPrint('Error reading ${file.name} from zip: $e');
      }
    }
  }

  return content;
}

/// Reads a directory of GTFS txt files and returns a map of filename -> CSV content.
Future<Map<String, String>> readDirectoryContent(String dirPath) async {
  final content = <String, String>{};
  final dir = Directory(dirPath);

  if (!dir.existsSync()) {
    throw ArgumentError('Directory does not exist: $dirPath');
  }

  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
      final baseName = entity.path
          .split('/')
          .last
          .split('\\')
          .last
          .replaceAll('.txt', '')
          .toLowerCase();
      try {
        // Read as bytes and decode as UTF-8 to properly handle BOM
        final bytes = entity.readAsBytesSync();
        content[baseName] = utf8.decode(bytes, allowMalformed: true);
      } catch (e) {
        debugPrint('Error reading ${entity.path}: $e');
      }
    }
  }

  return content;
}
