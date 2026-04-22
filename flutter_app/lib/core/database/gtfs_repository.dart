import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../services/osrm_service.dart';
import '../../models/gtfs_models.dart';
import '../../models/project_model.dart';

class GtfsRepository {
  static Future<Database> get _db => AppDatabase.instance;

  // -------------------------------------------------------------------------
  // Projects
  // -------------------------------------------------------------------------

  static Future<List<ProjectModel>> getProjects() async {
    final db = await _db;
    final rows = await db.query('projects', orderBy: 'created_at DESC');
    return rows.map(ProjectModel.fromMap).toList();
  }

  static Future<ProjectModel> createProject(String name) async {
    final db = await _db;
    final id = await db.insert('projects', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    return ProjectModel.fromMap(rows.first);
  }

  static Future<void> deleteProject(int id) async {
    final db = await _db;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------------
  // GTFS Files
  // -------------------------------------------------------------------------

  static Future<List<GtfsFileModel>> getGtfsFiles(int projectId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_files',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
    return rows.map(GtfsFileModel.fromMap).toList();
  }

  static Future<GtfsFileModel> createGtfsFile(
      int projectId, String filename, String importPath) async {
    final db = await _db;
    final id = await db.insert('gtfs_files', {
      'project_id': projectId,
      'filename': filename,
      'import_path': importPath,
      'imported_at': DateTime.now().toIso8601String(),
    });
    final rows = await db.query('gtfs_files', where: 'id = ?', whereArgs: [id]);
    return GtfsFileModel.fromMap(rows.first);
  }

  static Future<void> deleteGtfsFile(int id) async {
    final db = await _db;
    await db.delete('gtfs_files', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------------
  // Agencies
  // -------------------------------------------------------------------------

  static Future<List<AgencyModel>> getAgencies(int gtfsFileId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_agencies',
      where: 'gtfs_file_id = ?',
      whereArgs: [gtfsFileId],
    );
    return rows.map(AgencyModel.fromMap).toList();
  }

  static Future<int> insertAgency(
      int gtfsFileId, Map<String, dynamic> data) async {
    final db = await _db;
    return db.insert('gtfs_agencies', {
      'gtfs_file_id': gtfsFileId,
      'agency_id': data['agency_id'],
      'agency_name': data['agency_name'] ?? data['agency_id'] ?? 'Unknown',
      'agency_url': data['agency_url'],
      'agency_timezone': data['agency_timezone'],
    });
  }

  // -------------------------------------------------------------------------
  // Routes
  // -------------------------------------------------------------------------

  static Future<List<RouteModel>> getRoutes(int gtfsFileId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_routes',
      where: 'gtfs_file_id = ?',
      whereArgs: [gtfsFileId],
    );
    return rows.map(RouteModel.fromMap).toList();
  }

  static Future<List<RouteModel>> getRoutesByAgency(int agencyDbId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_routes',
      where: 'agency_db_id = ?',
      whereArgs: [agencyDbId],
    );
    return rows.map(RouteModel.fromMap).toList();
  }

  static Future<int> insertRoute(
      int gtfsFileId, int? agencyDbId, Map<String, dynamic> data) async {
    final db = await _db;
    return db.insert('gtfs_routes', {
      'gtfs_file_id': gtfsFileId,
      'agency_db_id': agencyDbId,
      'route_id': data['route_id'] ?? '',
      'route_short_name': data['route_short_name'],
      'route_long_name': data['route_long_name'],
      'route_type': data['route_type'] != null
          ? int.tryParse(data['route_type'].toString())
          : null,
      'route_color': data['route_color'],
      'route_text_color': data['route_text_color'],
      'route_desc': data['route_desc'],
    });
  }

  static Future<RouteModel?> getRouteById(int id) async {
    final db = await _db;
    final rows =
        await db.query('gtfs_routes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return RouteModel.fromMap(rows.first);
  }

  static Future<void> updateRouteColor(int routeId, String? color) async {
    final db = await _db;
    await db.update(
      'gtfs_routes',
      {'route_color': color},
      where: 'id = ?',
      whereArgs: [routeId],
    );
  }

  // -------------------------------------------------------------------------
  // Stops
  // -------------------------------------------------------------------------

  static Future<List<StopModel>> getStops(int gtfsFileId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_stops',
      where: 'gtfs_file_id = ?',
      whereArgs: [gtfsFileId],
    );
    return rows.map(StopModel.fromMap).toList();
  }

  static Future<int> insertStop(
      int gtfsFileId, Map<String, dynamic> data) async {
    final db = await _db;
    return db.insert('gtfs_stops', {
      'gtfs_file_id': gtfsFileId,
      'stop_id': data['stop_id'] ?? '',
      'stop_name': data['stop_name'],
      'stop_lat': double.tryParse(data['stop_lat']?.toString() ?? '0') ?? 0.0,
      'stop_lon': double.tryParse(data['stop_lon']?.toString() ?? '0') ?? 0.0,
      'stop_code': data['stop_code'],
      'stop_desc': data['stop_desc'],
    });
  }

  static Future<StopModel?> getStopById(int id) async {
    final db = await _db;
    final rows = await db.query('gtfs_stops', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return StopModel.fromMap(rows.first);
  }

  // Get unique stops for a specific route
  static Future<List<StopModel>> getStopsByRoute(int routeDbId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT s.*
      FROM gtfs_stops s
      INNER JOIN gtfs_stop_times st ON s.id = st.stop_db_id
      INNER JOIN gtfs_trips t ON st.trip_db_id = t.id
      WHERE t.route_db_id = ?
      ORDER BY s.stop_name
    ''', [routeDbId]);
    return rows.map(StopModel.fromMap).toList();
  }

  // -------------------------------------------------------------------------
  // Trips
  // -------------------------------------------------------------------------

  static Future<List<TripModel>> getTripsByServices(
      List<int> gtfsFileIds, List<String> serviceIds) async {
    if (serviceIds.isEmpty) return [];
    final db = await _db;

    final placeholders = serviceIds.map((_) => '?').join(',');
    final fileIdPlaceholders = gtfsFileIds.map((_) => '?').join(',');

    final rows = await db.rawQuery('''
      SELECT t.*, r.route_short_name, r.route_long_name, r.route_color, r.route_text_color,
             r.route_id, r.route_type
      FROM gtfs_trips t
      INNER JOIN gtfs_routes r ON t.route_db_id = r.id
      WHERE t.gtfs_file_id IN ($fileIdPlaceholders)
        AND t.service_id IN ($placeholders)
    ''', [...gtfsFileIds, ...serviceIds]);

    return rows.map((row) {
      final trip = TripModel.fromMap(row);
      trip.route = RouteModel(
        id: row['route_db_id'] as int,
        gtfsFileId: row['gtfs_file_id'] as int,
        routeId: row['route_id'] as String,
        routeShortName: row['route_short_name'] as String?,
        routeLongName: row['route_long_name'] as String?,
        routeColor: row['route_color'] as String?,
        routeTextColor: row['route_text_color'] as String?,
        routeType: row['route_type'] as int?,
      );
      return trip;
    }).toList();
  }

  static Future<void> loadStopTimesForTrips(List<TripModel> trips) async {
    if (trips.isEmpty) return;
    final db = await _db;

    final tripIds = trips.map((t) => t.id).toList();
    final placeholders = tripIds.map((_) => '?').join(',');

    final rows = await db.rawQuery('''
      SELECT st.*, s.stop_lat, s.stop_lon, s.stop_name, s.stop_id as gtfs_stop_id
      FROM gtfs_stop_times st
      INNER JOIN gtfs_stops s ON st.stop_db_id = s.id
      WHERE st.trip_db_id IN ($placeholders)
      ORDER BY st.trip_db_id, st.stop_sequence ASC
    ''', tripIds);

    final Map<int, List<StopTimeModel>> stopTimesByTrip = {};
    for (final row in rows) {
      final st = StopTimeModel.fromMap(row);
      st.stop = StopModel(
        id: st.stopDbId,
        gtfsFileId: st.gtfsFileId,
        stopId: row['gtfs_stop_id'] as String,
        stopName: row['stop_name'] as String?,
        stopLat: (row['stop_lat'] as num).toDouble(),
        stopLon: (row['stop_lon'] as num).toDouble(),
      );
      stopTimesByTrip.putIfAbsent(st.tripDbId, () => []).add(st);
    }

    for (final trip in trips) {
      trip.stopTimes = (stopTimesByTrip[trip.id] ?? [])
        ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }
  }

  // -------------------------------------------------------------------------
  // Routes serving a specific stop (for transfer review)
  // -------------------------------------------------------------------------

  static Future<List<RouteModel>> getRoutesForStop(
      int stopDbId, List<String> serviceIds) async {
    if (serviceIds.isEmpty) return [];
    final db = await _db;
    final placeholders = serviceIds.map((_) => '?').join(',');
    final rows = await db.rawQuery('''
      SELECT DISTINCT r.id, r.gtfs_file_id, r.agency_db_id, r.route_id,
             r.route_short_name, r.route_long_name, r.route_type,
             r.route_color, r.route_text_color, r.route_desc
      FROM gtfs_routes r
      INNER JOIN gtfs_trips t ON t.route_db_id = r.id
      INNER JOIN gtfs_stop_times st ON st.trip_db_id = t.id
      WHERE st.stop_db_id = ?
        AND t.service_id IN ($placeholders)
      ORDER BY r.route_short_name ASC
    ''', [stopDbId, ...serviceIds]);
    return rows.map(RouteModel.fromMap).toList();
  }

  // -------------------------------------------------------------------------
  // Stop Times for a specific stop
  // -------------------------------------------------------------------------

  static Future<List<StopTimeModel>> getStopTimesByStop(
      int stopDbId, List<String> serviceIds, DateTime date) async {
    if (serviceIds.isEmpty) return [];
    final db = await _db;

    final placeholders = serviceIds.map((_) => '?').join(',');

    final rows = await db.rawQuery('''
      SELECT st.*, t.trip_headsign, t.route_db_id,
             r.id as route_id_pk, r.route_short_name, r.route_long_name,
             r.route_color, r.route_id, t.id as trip_db_id_alias
      FROM gtfs_stop_times st
      INNER JOIN gtfs_trips t ON st.trip_db_id = t.id
      INNER JOIN gtfs_routes r ON t.route_db_id = r.id
      WHERE st.stop_db_id = ?
        AND t.service_id IN ($placeholders)
      ORDER BY st.arrival_time ASC
    ''', [stopDbId, ...serviceIds]);

    return rows.map((row) {
      final st = StopTimeModel.fromMap(row);
      final trip = TripModel(
        id: row['trip_db_id'] as int,
        gtfsFileId: st.gtfsFileId,
        routeDbId: row['route_db_id'] as int? ?? 0,
        serviceId: '',
        tripId: '',
        tripHeadsign: row['trip_headsign'] as String?,
      );
      trip.route = RouteModel(
        id: row['route_id_pk'] as int? ?? row['route_db_id'] as int? ?? 0,
        gtfsFileId: st.gtfsFileId,
        routeId: row['route_id'] as String,
        routeShortName: row['route_short_name'] as String?,
        routeLongName: row['route_long_name'] as String?,
        routeColor: row['route_color'] as String?,
      );
      st.trip = trip;
      return st;
    }).toList();
  }

  // -------------------------------------------------------------------------
  // Shapes
  // -------------------------------------------------------------------------

  static Future<List<ShapeModel>> getShapesByRouteShapeId(
      int gtfsFileId, String shapeId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_shapes',
      where: 'gtfs_file_id = ? AND shape_id = ?',
      whereArgs: [gtfsFileId, shapeId],
      orderBy: 'shape_pt_sequence ASC',
    );
    return rows.map(ShapeModel.fromMap).toList();
  }

  static Future<List<ShapeModel>> getAllShapesByGtfsFile(int gtfsFileId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_shapes',
      where: 'gtfs_file_id = ?',
      whereArgs: [gtfsFileId],
      orderBy: 'shape_id, shape_pt_sequence ASC',
    );
    return rows.map(ShapeModel.fromMap).toList();
  }

  // Group shapes by shape_id and ensure they are sorted by sequence
  static Map<String, List<ShapeModel>> groupShapes(List<ShapeModel> shapes) {
    final Map<String, List<ShapeModel>> grouped = {};
    for (final s in shapes) {
      grouped.putIfAbsent(s.shapeId, () => []).add(s);
    }
    // Ensure each group is sorted by shape_pt_sequence
    for (final list in grouped.values) {
      list.sort((a, b) => a.shapePtSequence.compareTo(b.shapePtSequence));
    }
    return grouped;
  }

  // Get all shape_ids used by a specific route
  static Future<List<String>> getShapeIdsByRoute(int routeDbId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT shape_id 
      FROM gtfs_trips 
      WHERE route_db_id = ? AND shape_id IS NOT NULL AND shape_id != ''
    ''', [routeDbId]);
    return rows
        .map((row) => row['shape_id'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toList();
  }

  // Get all shapes for a specific route
  static Future<List<ShapeModel>> getShapesByRoute(
      int gtfsFileId, int routeDbId) async {
    final shapeIds = await getShapeIdsByRoute(routeDbId);
    if (shapeIds.isEmpty) return [];

    final db = await _db;
    final placeholders = shapeIds.map((_) => '?').join(',');
    final rows = await db.rawQuery('''
      SELECT * FROM gtfs_shapes 
      WHERE gtfs_file_id = ? AND shape_id IN ($placeholders)
      ORDER BY shape_id, shape_pt_sequence ASC
    ''', [gtfsFileId, ...shapeIds]);

    return rows.map(ShapeModel.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Calendar
  // ---------------------------------------------------------------------------

  static Future<List<CalendarModel>> getCalendar(int gtfsFileId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_calendar',
      where: 'gtfs_file_id = ?',
      whereArgs: [gtfsFileId],
    );
    return rows.map(CalendarModel.fromMap).toList();
  }

  static Future<List<CalendarDateModel>> getCalendarDates(
      int gtfsFileId) async {
    final db = await _db;
    final rows = await db.query(
      'gtfs_calendar_dates',
      where: 'gtfs_file_id = ?',
      whereArgs: [gtfsFileId],
    );
    return rows.map(CalendarDateModel.fromMap).toList();
  }

  // -------------------------------------------------------------------------
  // Active services calculation
  // -------------------------------------------------------------------------

  static Future<List<ServiceInfo>> getActiveServices(
      List<GtfsFileModel> gtfsFiles, DateTime date) async {
    final services = <ServiceInfo>[];
    final dateOnly = DateTime(date.year, date.month, date.day);

    for (final gtfsFile in gtfsFiles) {
      // From calendar_dates (exception_type == 1 = added)
      final calDates = await getCalendarDates(gtfsFile.id);
      for (final cd in calDates) {
        final cdDate = DateTime(cd.date.year, cd.date.month, cd.date.day);
        if (cdDate.isAtSameMomentAs(dateOnly) && cd.exceptionType == 1) {
          services.add(ServiceInfo(
            serviceId: cd.serviceId,
            gtfsFileId: gtfsFile.id,
            gtfsFilename: gtfsFile.filename,
          ));
        }
      }

      // From calendar (weekly schedule)
      final calendar = await getCalendar(gtfsFile.id);
      for (final cal in calendar) {
        if (cal.isActiveOnDate(date)) {
          // Make sure not removed by calendar_dates exception_type == 2
          final isRemoved = calDates.any(
            (cd) =>
                cd.serviceId == cal.serviceId &&
                cd.exceptionType == 2 &&
                DateTime(cd.date.year, cd.date.month, cd.date.day)
                    .isAtSameMomentAs(dateOnly),
          );
          if (!isRemoved) {
            services.add(ServiceInfo(
              serviceId: cal.serviceId,
              gtfsFileId: gtfsFile.id,
              gtfsFilename: gtfsFile.filename,
            ));
          }
        }
      }
    }

    // Deduplicate
    final seen = <String>{};
    return services.where((s) {
      final key = '${s.gtfsFileId}_${s.serviceId}';
      return seen.add(key);
    }).toList();
  }

  // -------------------------------------------------------------------------
  // Bulk insert helpers (for importer)
  // -------------------------------------------------------------------------

  static Future<void> bulkInsertStops(
      Database db, int gtfsFileId, List<Map<String, dynamic>> rows) async {
    const chunkSize = 500;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      final batch = db.batch();
      for (final row in chunk) {
        batch.insert('gtfs_stops', {
          'gtfs_file_id': gtfsFileId,
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
      await batch.commit(noResult: true);
    }
  }

  static Future<void> bulkInsertRoutes(Database db, int gtfsFileId,
      Map<String, int> agencyMap, List<Map<String, dynamic>> rows) async {
    const chunkSize = 500;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      final batch = db.batch();
      for (final row in chunk) {
        final agencyId = row['agency_id'] as String?;
        final agencyDbId = agencyId != null ? agencyMap[agencyId] : null;
        batch.insert('gtfs_routes', {
          'gtfs_file_id': gtfsFileId,
          'agency_db_id': agencyDbId ?? agencyMap.values.firstOrNull,
          'route_id': row['route_id'] ?? '',
          'route_short_name': row['route_short_name'],
          'route_long_name': row['route_long_name'],
          'route_type': int.tryParse(row['route_type']?.toString() ?? ''),
          'route_color': row['route_color'],
          'route_text_color': row['route_text_color'],
          'route_desc': row['route_desc'],
        });
      }
      await batch.commit(noResult: true);
    }
  }

  static Future<void> bulkInsertTrips(Database db, int gtfsFileId,
      Map<String, int> routeMap, List<Map<String, dynamic>> rows) async {
    const chunkSize = 1000;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      final batch = db.batch();
      for (final row in chunk) {
        final routeDbId = routeMap[row['route_id']?.toString()];
        if (routeDbId == null) continue;
        batch.insert('gtfs_trips', {
          'gtfs_file_id': gtfsFileId,
          'route_db_id': routeDbId,
          'service_id': row['service_id'] ?? '',
          'trip_id': row['trip_id'] ?? '',
          'trip_headsign': row['trip_headsign'],
          'direction_id': int.tryParse(row['direction_id']?.toString() ?? ''),
          'block_id': row['block_id'],
          'shape_id': (row['shape_id']?.toString().isEmpty ?? true)
              ? null
              : row['shape_id'],
        });
      }
      await batch.commit(noResult: true);
    }
  }

  static Future<void> bulkInsertStopTimes(
      Database db,
      int gtfsFileId,
      Map<String, int> tripMap,
      Map<String, int> stopMap,
      List<Map<String, dynamic>> rows) async {
    const chunkSize = 1000;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      final batch = db.batch();
      for (final row in chunk) {
        final tripDbId = tripMap[row['trip_id']?.toString()];
        final stopDbId = stopMap[row['stop_id']?.toString()];
        if (tripDbId == null || stopDbId == null) continue;
        batch.insert('gtfs_stop_times', {
          'gtfs_file_id': gtfsFileId,
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
    }
  }

  static Future<void> bulkInsertShapes(
      Database db, int gtfsFileId, List<Map<String, dynamic>> rows) async {
    const chunkSize = 1000;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
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
    }
  }

  static Future<void> bulkInsertCalendar(
      Database db, int gtfsFileId, List<Map<String, dynamic>> rows) async {
    final batch = db.batch();
    for (final row in rows) {
      final startRaw = row['start_date']?.toString() ?? '';
      final endRaw = row['end_date']?.toString() ?? '';
      final startDate = _parseGtfsDate(startRaw);
      final endDate = _parseGtfsDate(endRaw);
      batch.insert('gtfs_calendar', {
        'gtfs_file_id': gtfsFileId,
        'service_id': row['service_id'] ?? '',
        'monday': _boolInt(row['monday']),
        'tuesday': _boolInt(row['tuesday']),
        'wednesday': _boolInt(row['wednesday']),
        'thursday': _boolInt(row['thursday']),
        'friday': _boolInt(row['friday']),
        'saturday': _boolInt(row['saturday']),
        'sunday': _boolInt(row['sunday']),
        'start_date': startDate,
        'end_date': endDate,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<void> bulkInsertCalendarDates(
      Database db, int gtfsFileId, List<Map<String, dynamic>> rows) async {
    const chunkSize = 1000;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      final batch = db.batch();
      for (final row in chunk) {
        final dateRaw = row['date']?.toString() ?? '';
        final date = _parseGtfsDate(dateRaw);
        batch.insert('gtfs_calendar_dates', {
          'gtfs_file_id': gtfsFileId,
          'service_id': row['service_id'] ?? '',
          'date': date,
          'exception_type': int.tryParse((row['exception_type'] ?? '1')
                  .toString()
                  .replaceAll(RegExp(r'\s'), '')) ??
              1,
        });
      }
      await batch.commit(noResult: true);
    }
  }

  // -------------------------------------------------------------------------
  // Shape generation from stops
  // -------------------------------------------------------------------------

  /// Checks whether a route already has at least one shape point.
  static Future<bool> routeHasShapes(int routeDbId) async {
    final shapeIds = await getShapeIdsByRoute(routeDbId);
    return shapeIds.isNotEmpty;
  }

  /// Generates shapes for a route from its stop sequences, routing each
  /// segment through the road network via OSRM.
  ///
  /// For each unique ordered stop sequence found in the route's trips,
  /// creates a new shape whose points follow the road geometry.
  /// Updates all matching trips to reference the generated shape_id.
  ///
  /// Returns the number of distinct shapes inserted.
  static Future<int> generateShapesFromStops(
      int gtfsFileId, int routeDbId) async {
    final db = await _db;

    // 1. Fetch all trips for this route
    final tripRows = await db.query(
      'gtfs_trips',
      where: 'gtfs_file_id = ? AND route_db_id = ?',
      whereArgs: [gtfsFileId, routeDbId],
    );
    if (tripRows.isEmpty) return 0;

    // 2. For each trip, build the ordered list of stop coordinates
    final Map<String, List<int>> patternToTripIds = {};
    final Map<String, List<Map<String, dynamic>>> patternToStopRows = {};

    for (final tripRow in tripRows) {
      final tripDbId = tripRow['id'] as int;

      final stRows = await db.rawQuery('''
        SELECT st.stop_sequence, s.stop_lat, s.stop_lon
        FROM gtfs_stop_times st
        INNER JOIN gtfs_stops s ON st.stop_db_id = s.id
        WHERE st.trip_db_id = ?
        ORDER BY st.stop_sequence ASC
      ''', [tripDbId]);

      if (stRows.isEmpty) continue;

      // Use stop lat/lon sequence as pattern key (rounded to 5 dp)
      final key = stRows
          .map((r) =>
              '${(r['stop_lat'] as num).toStringAsFixed(5)},${(r['stop_lon'] as num).toStringAsFixed(5)}')
          .join('|');

      patternToTripIds.putIfAbsent(key, () => []).add(tripDbId);
      patternToStopRows.putIfAbsent(key, () => stRows.cast());
    }

    if (patternToStopRows.isEmpty) return 0;

    int shapesInserted = 0;

    // 3. For each unique pattern, get road geometry via OSRM, then insert
    for (final entry in patternToStopRows.entries) {
      final pattern = entry.key;
      final stops = entry.value;
      final shapeId = 'generated_${routeDbId}_${shapesInserted + 1}';

      // Build waypoints list
      final waypoints = stops
          .map((s) => (
                (s['stop_lat'] as num).toDouble(),
                (s['stop_lon'] as num).toDouble(),
              ))
          .toList();

      // Request road-following geometry from OSRM
      final roadPoints = await OsrmService.getRouteGeometry(waypoints);

      // Insert shape points from the road geometry
      final batch = db.batch();
      for (var seq = 0; seq < roadPoints.length; seq++) {
        final pt = roadPoints[seq];
        batch.insert('gtfs_shapes', {
          'gtfs_file_id': gtfsFileId,
          'shape_id': shapeId,
          'shape_pt_lat': pt.$1,
          'shape_pt_lon': pt.$2,
          'shape_pt_sequence': seq + 1,
        });
      }

      // Update all trips with this pattern to use the generated shape_id
      for (final tripDbId in patternToTripIds[pattern]!) {
        batch.update(
          'gtfs_trips',
          {'shape_id': shapeId},
          where: 'id = ?',
          whereArgs: [tripDbId],
        );
      }

      await batch.commit(noResult: true);
      shapesInserted++;
    }
    return shapesInserted;
  }

  static String _parseGtfsDate(String raw) {
    // GTFS dates are YYYYMMDD
    if (raw.length == 8) {
      return '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}';
    }
    return raw;
  }

  static int _boolInt(dynamic v) {
    if (v == null) return 0;
    final s = v.toString().trim();
    if (s == '1' || s.toLowerCase() == 'true') return 1;
    return 0;
  }

  // -------------------------------------------------------------------------
  // Shape editing
  // -------------------------------------------------------------------------

  /// Replace all shape points for [shapeId] with the new [points] list.
  static Future<void> updateShapePoints(
      int gtfsFileId, String shapeId, List<LatLng> points) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'gtfs_shapes',
        where: 'gtfs_file_id = ? AND shape_id = ?',
        whereArgs: [gtfsFileId, shapeId],
      );
      final batch = txn.batch();
      for (int i = 0; i < points.length; i++) {
        batch.insert('gtfs_shapes', {
          'gtfs_file_id': gtfsFileId,
          'shape_id': shapeId,
          'shape_pt_lat': points[i].latitude,
          'shape_pt_lon': points[i].longitude,
          'shape_pt_sequence': i + 1,
        });
      }
      await batch.commit(noResult: true);
    });
  }
}
