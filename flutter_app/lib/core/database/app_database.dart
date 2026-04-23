import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Conditional import: dart:io is not available on web
import 'db_init_stub.dart'
    if (dart.library.io) 'db_init_io.dart';

/// Initializes the SQLite database factory depending on the platform.
/// Delegates to platform-specific initialization.
Future<void> initDatabaseFactory() => platformInitDatabase();

class AppDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    _db ??= await _openDatabase();
    return _db!;
  }

  static Future<String> getDatabasePath() async {
    if (kIsWeb) {
      return 'open_gtfs_planner.db';
    }
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'open_gtfs_planner', 'open_gtfs_planner.db');
  }

  static Future<Database> _openDatabase() async {
    final dbPath = await getDatabasePath();

    // Create directory on native platforms (not web)
    if (!kIsWeb) {
      await ensureDirectory(p.dirname(dbPath));
    }

    return openDatabase(
      dbPath,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        filename TEXT NOT NULL,
        import_path TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_agencies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        agency_id TEXT,
        agency_name TEXT NOT NULL,
        agency_url TEXT,
        agency_timezone TEXT,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_stops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        stop_id TEXT NOT NULL,
        stop_name TEXT,
        stop_lat REAL NOT NULL,
        stop_lon REAL NOT NULL,
        stop_code TEXT,
        stop_desc TEXT,
        is_merged INTEGER NOT NULL DEFAULT 0,
        merged_from_stop_ids TEXT,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        agency_db_id INTEGER,
        route_id TEXT NOT NULL,
        route_short_name TEXT,
        route_long_name TEXT,
        route_type INTEGER,
        route_color TEXT,
        route_text_color TEXT,
        route_desc TEXT,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE,
        FOREIGN KEY (agency_db_id) REFERENCES gtfs_agencies(id) ON DELETE SET NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        route_db_id INTEGER NOT NULL,
        service_id TEXT NOT NULL,
        trip_id TEXT NOT NULL,
        trip_headsign TEXT,
        direction_id INTEGER,
        block_id TEXT,
        shape_id TEXT,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE,
        FOREIGN KEY (route_db_id) REFERENCES gtfs_routes(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_stop_times (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        trip_db_id INTEGER NOT NULL,
        stop_db_id INTEGER NOT NULL,
        arrival_time TEXT NOT NULL,
        departure_time TEXT NOT NULL,
        stop_sequence INTEGER NOT NULL,
        stop_headsign TEXT,
        pickup_type INTEGER,
        drop_off_type INTEGER,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE,
        FOREIGN KEY (trip_db_id) REFERENCES gtfs_trips(id) ON DELETE CASCADE,
        FOREIGN KEY (stop_db_id) REFERENCES gtfs_stops(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_shapes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        shape_id TEXT NOT NULL,
        shape_pt_lat REAL NOT NULL,
        shape_pt_lon REAL NOT NULL,
        shape_pt_sequence INTEGER NOT NULL,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_calendar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        service_id TEXT NOT NULL,
        monday INTEGER NOT NULL DEFAULT 0,
        tuesday INTEGER NOT NULL DEFAULT 0,
        wednesday INTEGER NOT NULL DEFAULT 0,
        thursday INTEGER NOT NULL DEFAULT 0,
        friday INTEGER NOT NULL DEFAULT 0,
        saturday INTEGER NOT NULL DEFAULT 0,
        sunday INTEGER NOT NULL DEFAULT 0,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gtfs_calendar_dates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        service_id TEXT NOT NULL,
        date TEXT NOT NULL,
        exception_type INTEGER NOT NULL,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS route_patterns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gtfs_file_id INTEGER NOT NULL,
        route_db_id INTEGER NOT NULL,
        name TEXT,
        direction_id INTEGER NOT NULL DEFAULT 0,
        shape_id TEXT,
        FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE,
        FOREIGN KEY (route_db_id) REFERENCES gtfs_routes(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS route_pattern_stops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pattern_id INTEGER NOT NULL,
        stop_db_id INTEGER NOT NULL,
        stop_sequence INTEGER NOT NULL,
        time_from_origin_seconds INTEGER,
        FOREIGN KEY (pattern_id) REFERENCES route_patterns(id) ON DELETE CASCADE,
        FOREIGN KEY (stop_db_id) REFERENCES gtfs_stops(id) ON DELETE CASCADE
      )
    ''');

    // Indexes for performance
    batch.execute('CREATE INDEX IF NOT EXISTS idx_stops_gtfs ON gtfs_stops(gtfs_file_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_routes_gtfs ON gtfs_routes(gtfs_file_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_trips_gtfs ON gtfs_trips(gtfs_file_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_trips_service ON gtfs_trips(service_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_stop_times_trip ON gtfs_stop_times(trip_db_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_stop_times_stop ON gtfs_stop_times(stop_db_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_shapes_id ON gtfs_shapes(gtfs_file_id, shape_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_calendar_service ON gtfs_calendar(gtfs_file_id, service_id)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_cal_dates_service ON gtfs_calendar_dates(gtfs_file_id, service_id)');

    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE gtfs_stops ADD COLUMN is_merged INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE gtfs_stops ADD COLUMN merged_from_stop_ids TEXT',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS route_patterns (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          gtfs_file_id INTEGER NOT NULL,
          route_db_id INTEGER NOT NULL,
          name TEXT,
          direction_id INTEGER NOT NULL DEFAULT 0,
          shape_id TEXT,
          FOREIGN KEY (gtfs_file_id) REFERENCES gtfs_files(id) ON DELETE CASCADE,
          FOREIGN KEY (route_db_id) REFERENCES gtfs_routes(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS route_pattern_stops (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pattern_id INTEGER NOT NULL,
          stop_db_id INTEGER NOT NULL,
          stop_sequence INTEGER NOT NULL,
          time_from_origin_seconds INTEGER,
          FOREIGN KEY (pattern_id) REFERENCES route_patterns(id) ON DELETE CASCADE,
          FOREIGN KEY (stop_db_id) REFERENCES gtfs_stops(id) ON DELETE CASCADE
        )
      ''');
    }
  }

  /// Reset / re-open (useful after migrations or tests)
  static Future<void> reset() async {
    await _db?.close();
    _db = null;
  }
}
