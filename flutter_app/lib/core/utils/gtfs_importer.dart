import 'dart:async';
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
    final content = _extractZipToContent(bytes);
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

  GtfsContent _extractZipToContent(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = <String, String>{};

    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase().endsWith('.txt')) {
        // Handle paths like "gtfs/stops.txt" -> "stops"
        final baseName = file.name.split('/').last.replaceAll('.txt', '').toLowerCase();
        try {
          final fileBytes = file.content as Uint8List;
          content[baseName] = String.fromCharCodes(fileBytes);
        } catch (e) {
          debugPrint('Error reading ${file.name} from zip: $e');
        }
      }
    }

    return content;
  }

  Future<GtfsFileModel> _importContent(
    int projectId,
    String filename,
    String sourcePath,
    GtfsContent content,
  ) async {
    final gtfsFile =
        await GtfsRepository.createGtfsFile(projectId, filename, sourcePath);

    _notify('Leyendo archivos GTFS...', 0.10);

    final agencyData = _parseContent(content, 'agency');
    final stopsData = _parseContent(content, 'stops');
    final routesData = _parseContent(content, 'routes');
    final tripsData = _parseContent(content, 'trips');
    final stopTimesData = _parseContent(content, 'stop_times');
    final shapesData = _parseContent(content, 'shapes');
    final calendarData = _parseContent(content, 'calendar');
    final calendarDatesData = _parseContent(content, 'calendar_dates');

    final db = await AppDatabase.instance;

    _notify('Importando agencias...', 0.15);
    final agencyMap = <String, int>{};
    for (final agency in agencyData) {
      final dbId = await db.insert('gtfs_agencies', {
        'gtfs_file_id': gtfsFile.id,
        'agency_id': agency['agency_id'],
        'agency_name': agency['agency_name'] ?? agency['agency_id'] ?? 'Unknown',
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
    await _importInChunks(db, stopsData, 500, (chunk) async {
      final batch = db.batch();
      for (final row in chunk) {
        batch.insert('gtfs_stops', {
          'gtfs_file_id': gtfsFile.id,
          'stop_id': row['stop_id'] ?? '',
          'stop_name': row['stop_name'],
          'stop_lat': double.tryParse(row['stop_lat']?.toString() ?? '0') ?? 0.0,
          'stop_lon': double.tryParse(row['stop_lon']?.toString() ?? '0') ?? 0.0,
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
    await _importInChunks(db, routesData, 500, (chunk) async {
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
    await GtfsRepository.bulkInsertCalendar(db, gtfsFile.id, calendarData);
    await GtfsRepository.bulkInsertCalendarDates(db, gtfsFile.id, calendarDatesData);

    _notify('Importando viajes (trips)...', 0.50);
    final tripMap = <String, int>{};
    await _importInChunks(db, tripsData, 1000, (chunk) async {
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
    await GtfsRepository.bulkInsertShapes(db, gtfsFile.id, shapesData);

    _notify('Importando horarios (stop_times)...', 0.75);
    await _importInChunks(db, stopTimesData, 1000, (chunk) async {
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

  Future<void> _importInChunks(
    Database db,
    List<Map<String, dynamic>> rows,
    int chunkSize,
    Future<void> Function(List<Map<String, dynamic>>) handler,
  ) async {
    for (var i = 0; i < rows.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, rows.length);
      await handler(rows.sublist(i, end));
    }
  }

  List<Map<String, dynamic>> _parseContent(GtfsContent content, String key) {
    final csv = content[key];
    if (csv == null || csv.isEmpty) return [];

    try {
      final rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(csv);

      if (rows.isEmpty) return [];

      final headers = rows.first
          .map((h) => h.toString().trim().replaceAll('\uFEFF', '').replaceAll('\r', ''))
          .toList();

      return rows.skip(1).where((row) => row.isNotEmpty).map((row) {
        final map = <String, dynamic>{};
        for (var i = 0; i < headers.length; i++) {
          map[headers[i]] =
              i < row.length ? row[i].toString().trim() : null;
        }
        return map;
      }).toList();
    } catch (e) {
      debugPrint('Error parsing GTFS $key: $e');
      return [];
    }
  }
}
