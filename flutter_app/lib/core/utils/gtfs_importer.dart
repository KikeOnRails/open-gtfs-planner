import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/gtfs_repository.dart';
import '../../models/gtfs_models.dart';

// Conditional dart:io import (only available on non-web platforms)
import 'gtfs_importer_io_stub.dart'
    if (dart.library.io) 'gtfs_importer_io.dart';

typedef ImportProgressCallback = void Function(String step, double progress);

/// Content map: filename (without .txt) -> CSV string content
typedef GtfsContent = Map<String, String>;

/// Data class to hold all parsed GTFS data for passing between isolates
class _ParsedGtfsData {
  final List<Map<String, dynamic>> agencies;
  final List<Map<String, dynamic>> stops;
  final List<Map<String, dynamic>> routes;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> stopTimes;
  final List<Map<String, dynamic>> shapes;
  final List<Map<String, dynamic>> calendar;
  final List<Map<String, dynamic>> calendarDates;

  _ParsedGtfsData({
    required this.agencies,
    required this.stops,
    required this.routes,
    required this.trips,
    required this.stopTimes,
    required this.shapes,
    required this.calendar,
    required this.calendarDates,
  });
}

/// Parse all CSV content in an isolate (runs on separate thread)
_ParsedGtfsData _parseAllContentInIsolate(GtfsContent content) {
  return _ParsedGtfsData(
    agencies: _parseContentStatic(content, 'agency'),
    stops: _parseContentStatic(content, 'stops'),
    routes: _parseContentStatic(content, 'routes'),
    trips: _parseContentStatic(content, 'trips'),
    stopTimes: _parseContentStatic(content, 'stop_times'),
    shapes: _parseContentStatic(content, 'shapes'),
    calendar: _parseContentStatic(content, 'calendar'),
    calendarDates: _parseContentStatic(content, 'calendar_dates'),
  );
}

/// Static version of _parseContent for use in isolate
List<Map<String, dynamic>> _parseContentStatic(
    GtfsContent content, String key) {
  var csv = content[key];
  if (csv == null || csv.isEmpty) return [];

  try {
    // Normalize line endings: CRLF -> LF, and remove BOM
    csv = csv
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\uFEFF', '');

    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csv);

    if (rows.isEmpty) return [];

    final headers = rows.first.map((h) => h.toString().trim()).toList();

    return rows.skip(1).where((row) => row.isNotEmpty).map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < headers.length; i++) {
        map[headers[i]] = i < row.length ? row[i].toString().trim() : null;
      }
      return map;
    }).toList();
  } catch (e) {
    debugPrint('Error parsing GTFS $key: $e');
    return [];
  }
}

/// Extract ZIP content (can run in isolate for large files)
GtfsContent _extractZipInIsolate(Uint8List bytes) {
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
        // Skip problematic files
      }
    }
  }

  return content;
}

class GtfsImporter {
  final ImportProgressCallback? onProgress;

  GtfsImporter({this.onProgress});

  void _notify(String step, double progress) {
    onProgress?.call(step, progress);
  }

  /// Import GTFS from a zip file path (desktop) or zip bytes (web).
  /// For desktop directories, use [importFromPath] instead.
  Future<GtfsFileModel> importFromZipBytes(
      int projectId, String filename, Uint8List bytes) async {
    _notify('Extrayendo ZIP...', 0.05);

    // Extract ZIP in isolate to avoid blocking UI
    final content = await compute(_extractZipInIsolate, bytes);

    return _importContent(projectId, filename, filename, content);
  }

  /// Import GTFS from a path (file or directory) on native platforms.
  Future<GtfsFileModel> import(int projectId, String pathOrZip) async {
    final isZip = pathOrZip.toLowerCase().endsWith('.zip');
    final filename = _basename(pathOrZip);

    GtfsContent content;
    if (isZip) {
      _notify('Leyendo ZIP...', 0.05);
      content = await readZipContent(pathOrZip);
    } else {
      _notify('Leyendo carpeta GTFS...', 0.05);
      content = await readDirectoryContent(pathOrZip);
    }

    return _importContent(projectId, filename, pathOrZip, content);
  }

  String _basename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.last.isNotEmpty ? parts.last : parts[parts.length - 2];
  }

  Future<GtfsFileModel> _importContent(
    int projectId,
    String filename,
    String sourcePath,
    GtfsContent content,
  ) async {
    final gtfsFile =
        await GtfsRepository.createGtfsFile(projectId, filename, sourcePath);

    _notify('Parseando archivos CSV...', 0.10);

    // Parse all CSV data in a separate isolate (heavy operation)
    final parsed = await compute(_parseAllContentInIsolate, content);

    final db = await AppDatabase.instance;

    _notify('Importando agencias...', 0.15);
    final agencyMap = <String, int>{};
    for (final agency in parsed.agencies) {
      final dbId = await db.insert('gtfs_agencies', {
        'gtfs_file_id': gtfsFile.id,
        'agency_id': agency['agency_id'],
        'agency_name':
            agency['agency_name'] ?? agency['agency_id'] ?? 'Unknown',
        'agency_url': agency['agency_url'],
        'agency_timezone': agency['agency_timezone'],
      });
      if (agency['agency_id'] != null) {
        agencyMap[agency['agency_id'].toString()] = dbId;
      }
    }
    if (agencyMap.isEmpty) {
      final dbId = await db.insert('gtfs_agencies', {
        'gtfs_file_id': gtfsFile.id,
        'agency_id': 'default',
        'agency_name': filename,
        'agency_url': null,
        'agency_timezone': null,
      });
      agencyMap['default'] = dbId;
    }

    _notify('Importando paradas...', 0.20);
    final stopMap = <String, int>{};
    await _importInChunks(db, parsed.stops, 300, (chunk) async {
      final batch = db.batch();
      for (final row in chunk) {
        batch.insert('gtfs_stops', {
          'gtfs_file_id': gtfsFile.id,
          'stop_id': row['stop_id'] ?? '',
          'stop_name': row['stop_name'],
          'stop_lat':
              double.tryParse(row['stop_lat']?.toString() ?? '0') ?? 0.0,
          'stop_lon':
              double.tryParse(row['stop_lon']?.toString() ?? '0') ?? 0.0,
          'stop_code': row['stop_code'],
          'stop_desc': row['stop_desc'],
        });
      }
      final ids = await batch.commit();
      for (var i = 0; i < chunk.length; i++) {
        final stopId = chunk[i]['stop_id']?.toString();
        if (stopId != null && ids[i] != null) {
          stopMap[stopId] = ids[i] as int;
        }
      }
    });

    _notify('Importando rutas...', 0.35);
    final routeMap = <String, int>{};
    await _importInChunks(db, parsed.routes, 300, (chunk) async {
      final batch = db.batch();
      for (final row in chunk) {
        final agencyId = row['agency_id']?.toString();
        final agencyDbId = agencyId != null
            ? agencyMap[agencyId]
            : agencyMap.values.firstOrNull;
        batch.insert('gtfs_routes', {
          'gtfs_file_id': gtfsFile.id,
          'agency_db_id': agencyDbId,
          'route_id': row['route_id'] ?? '',
          'route_short_name': row['route_short_name'],
          'route_long_name': row['route_long_name'],
          'route_type': int.tryParse(row['route_type']?.toString() ?? ''),
          'route_color': row['route_color'],
          'route_text_color': row['route_text_color'],
          'route_desc': row['route_desc'],
        });
      }
      final ids = await batch.commit();
      for (var i = 0; i < chunk.length; i++) {
        final routeId = chunk[i]['route_id']?.toString();
        if (routeId != null && ids[i] != null) {
          routeMap[routeId] = ids[i] as int;
        }
      }
    });

    _notify('Importando calendario...', 0.45);
    await _importCalendarInChunks(db, gtfsFile.id, parsed.calendar);
    await _importCalendarDatesInChunks(db, gtfsFile.id, parsed.calendarDates);

    _notify('Importando viajes (trips)...', 0.50);
    final tripMap = <String, int>{};
    await _importInChunks(db, parsed.trips, 500, (chunk) async {
      final batch = db.batch();
      final validChunk = <Map<String, dynamic>>[];
      for (final row in chunk) {
        final routeDbId = routeMap[row['route_id']?.toString()];
        if (routeDbId == null) continue;
        validChunk.add(row);
        batch.insert('gtfs_trips', {
          'gtfs_file_id': gtfsFile.id,
          'route_db_id': routeDbId,
          'service_id': row['service_id'] ?? '',
          'trip_id': row['trip_id'] ?? '',
          'trip_headsign': row['trip_headsign'],
          'direction_id': int.tryParse(row['direction_id']?.toString() ?? ''),
          'block_id': row['block_id'],
          'shape_id': row['shape_id'],
        });
      }
      final ids = await batch.commit();
      for (var i = 0; i < validChunk.length; i++) {
        final tripId = validChunk[i]['trip_id']?.toString();
        if (tripId != null && ids[i] != null) {
          tripMap[tripId] = ids[i] as int;
        }
      }
    });

    _notify('Importando shapes...', 0.70);
    await _importShapesInChunks(db, gtfsFile.id, parsed.shapes);

    _notify('Importando horarios (stop_times)...', 0.75);
    await _importInChunks(db, parsed.stopTimes, 500, (chunk) async {
      final batch = db.batch();
      for (final row in chunk) {
        final tripDbId = tripMap[row['trip_id']?.toString()];
        final stopDbId = stopMap[row['stop_id']?.toString()];
        if (tripDbId == null || stopDbId == null) continue;
        batch.insert('gtfs_stop_times', {
          'gtfs_file_id': gtfsFile.id,
          'trip_db_id': tripDbId,
          'stop_db_id': stopDbId,
          'arrival_time': row['arrival_time'] ?? '00:00:00',
          'departure_time': row['departure_time'] ?? '00:00:00',
          'stop_sequence':
              int.tryParse(row['stop_sequence']?.toString() ?? '0') ?? 0,
          'stop_headsign': row['stop_headsign'],
          'pickup_type': int.tryParse(row['pickup_type']?.toString() ?? ''),
          'drop_off_type': int.tryParse(row['drop_off_type']?.toString() ?? ''),
        });
      }
      await batch.commit(noResult: true);
    });

    _notify('Importación completada', 1.0);
    return gtfsFile;
  }

  /// Import data in smaller chunks with UI yield between each
  Future<void> _importInChunks(
    Database db,
    List<Map<String, dynamic>> rows,
    int chunkSize,
    Future<void> Function(List<Map<String, dynamic>>) handler,
  ) async {
    for (var i = 0; i < rows.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, rows.length);
      await handler(rows.sublist(i, end));
      // Critical: yield to UI after each chunk
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Import calendar data in chunks
  Future<void> _importCalendarInChunks(
    Database db,
    int gtfsFileId,
    List<Map<String, dynamic>> data,
  ) async {
    const chunkSize = 300;
    for (var i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, data.length);
      final chunk = data.sublist(i, end);
      final batch = db.batch();
      for (final row in chunk) {
        batch.insert('gtfs_calendar', {
          'gtfs_file_id': gtfsFileId,
          'service_id': row['service_id'] ?? '',
          'monday': int.tryParse(row['monday']?.toString() ?? '0') ?? 0,
          'tuesday': int.tryParse(row['tuesday']?.toString() ?? '0') ?? 0,
          'wednesday': int.tryParse(row['wednesday']?.toString() ?? '0') ?? 0,
          'thursday': int.tryParse(row['thursday']?.toString() ?? '0') ?? 0,
          'friday': int.tryParse(row['friday']?.toString() ?? '0') ?? 0,
          'saturday': int.tryParse(row['saturday']?.toString() ?? '0') ?? 0,
          'sunday': int.tryParse(row['sunday']?.toString() ?? '0') ?? 0,
          'start_date': row['start_date'] ?? '',
          'end_date': row['end_date'] ?? '',
        });
      }
      await batch.commit(noResult: true);
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Import calendar dates in chunks
  Future<void> _importCalendarDatesInChunks(
    Database db,
    int gtfsFileId,
    List<Map<String, dynamic>> data,
  ) async {
    const chunkSize = 300;
    for (var i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, data.length);
      final chunk = data.sublist(i, end);
      final batch = db.batch();
      for (final row in chunk) {
        batch.insert('gtfs_calendar_dates', {
          'gtfs_file_id': gtfsFileId,
          'service_id': row['service_id'] ?? '',
          'date': row['date'] ?? '',
          'exception_type':
              int.tryParse(row['exception_type']?.toString() ?? '1') ?? 1,
        });
      }
      await batch.commit(noResult: true);
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Import shapes in chunks
  Future<void> _importShapesInChunks(
    Database db,
    int gtfsFileId,
    List<Map<String, dynamic>> data,
  ) async {
    const chunkSize = 500;
    for (var i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, data.length);
      final chunk = data.sublist(i, end);
      final batch = db.batch();
      for (final row in chunk) {
        batch.insert('gtfs_shapes', {
          'gtfs_file_id': gtfsFileId,
          'shape_id': row['shape_id'] ?? '',
          'shape_pt_lat':
              double.tryParse(row['shape_pt_lat']?.toString() ?? '0') ?? 0.0,
          'shape_pt_lon':
              double.tryParse(row['shape_pt_lon']?.toString() ?? '0') ?? 0.0,
          'shape_pt_sequence':
              int.tryParse(row['shape_pt_sequence']?.toString() ?? '0') ?? 0,
        });
      }
      await batch.commit(noResult: true);
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }
}
