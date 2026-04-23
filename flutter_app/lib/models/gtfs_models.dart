class GtfsFileModel {
  final int id;
  final int projectId;
  final String filename;
  final String importPath;
  final DateTime importedAt;

  const GtfsFileModel({
    required this.id,
    required this.projectId,
    required this.filename,
    required this.importPath,
    required this.importedAt,
  });

  factory GtfsFileModel.fromMap(Map<String, dynamic> map) {
    return GtfsFileModel(
      id: map['id'] as int,
      projectId: map['project_id'] as int,
      filename: map['filename'] as String,
      importPath: map['import_path'] as String,
      importedAt: DateTime.parse(map['imported_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'project_id': projectId,
        'filename': filename,
        'import_path': importPath,
        'imported_at': importedAt.toIso8601String(),
      };
}

class AgencyModel {
  final int id;
  final int gtfsFileId;
  final String? agencyId;
  final String agencyName;
  final String? agencyUrl;
  final String? agencyTimezone;

  // UI state (not persisted)
  bool isVisible;
  bool stopsVisible;
  bool simulationVisible;

  AgencyModel({
    required this.id,
    required this.gtfsFileId,
    this.agencyId,
    required this.agencyName,
    this.agencyUrl,
    this.agencyTimezone,
    this.isVisible = true,
    this.stopsVisible = false,
    this.simulationVisible = false,
  });

  factory AgencyModel.fromMap(Map<String, dynamic> map) {
    return AgencyModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      agencyId: map['agency_id'] as String?,
      agencyName: map['agency_name'] as String,
      agencyUrl: map['agency_url'] as String?,
      agencyTimezone: map['agency_timezone'] as String?,
    );
  }
}

class RouteModel {
  final int id;
  final int gtfsFileId;
  final int? agencyDbId;
  final String routeId;
  final String? routeShortName;
  final String? routeLongName;
  final int? routeType;
  final String? routeColor;
  final String? routeTextColor;
  final String? routeDesc;

  // UI state
  bool isVisible;
  bool stopsVisible;
  bool simulationVisible;

  RouteModel({
    required this.id,
    required this.gtfsFileId,
    this.agencyDbId,
    required this.routeId,
    this.routeShortName,
    this.routeLongName,
    this.routeType,
    this.routeColor,
    this.routeTextColor,
    this.routeDesc,
    this.isVisible = true,
    this.stopsVisible = false,
    this.simulationVisible = false,
  });

  String get displayName =>
      routeShortName?.isNotEmpty == true ? routeShortName! : (routeLongName ?? routeId);

  String get hexColor {
    if (routeColor != null && routeColor!.isNotEmpty) {
      return '#$routeColor';
    }
    return '#00AF8C';
  }

  factory RouteModel.fromMap(Map<String, dynamic> map) {
    return RouteModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      agencyDbId: map['agency_db_id'] as int?,
      routeId: map['route_id'] as String,
      routeShortName: map['route_short_name'] as String?,
      routeLongName: map['route_long_name'] as String?,
      routeType: map['route_type'] as int?,
      routeColor: map['route_color'] as String?,
      routeTextColor: map['route_text_color'] as String?,
      routeDesc: map['route_desc'] as String?,
    );
  }
}

class StopModel {
  final int id;
  final int gtfsFileId;
  final String stopId;
  final String? stopName;
  final double stopLat;
  final double stopLon;
  final String? stopCode;
  final String? stopDesc;
  final bool isMerged;
  /// IDs of the original stops that were merged into this one (only set when isMerged == true).
  final List<int> mergedFromStopIds;

  const StopModel({
    required this.id,
    required this.gtfsFileId,
    required this.stopId,
    this.stopName,
    required this.stopLat,
    required this.stopLon,
    this.stopCode,
    this.stopDesc,
    this.isMerged = false,
    this.mergedFromStopIds = const [],
  });

  String get displayName => stopName?.isNotEmpty == true ? stopName! : stopId;

  factory StopModel.fromMap(Map<String, dynamic> map) {
    return StopModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      stopId: map['stop_id'] as String,
      stopName: map['stop_name'] as String?,
      stopLat: (map['stop_lat'] as num).toDouble(),
      stopLon: (map['stop_lon'] as num).toDouble(),
      stopCode: map['stop_code'] as String?,
      stopDesc: map['stop_desc'] as String?,
      isMerged: (map['is_merged'] as int? ?? 0) == 1,
      mergedFromStopIds: _parseIds(map['merged_from_stop_ids'] as String?),
    );
  }

  static List<int> _parseIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').map(int.parse).toList();
  }
}

class TripModel {
  final int id;
  final int gtfsFileId;
  final int routeDbId;
  final String serviceId;
  final String tripId;
  final String? tripHeadsign;
  final int? directionId;
  final String? blockId;
  final String? shapeId;

  // Loaded relationships
  RouteModel? route;
  List<StopTimeModel>? stopTimes;

  // Computed datetimes
  DateTime? startDatetime;
  DateTime? endDatetime;
  
  // Precomputed arc-length positions (metres from shape start) for each stop.
  // Computed with a monotonic forward projection, so they are always increasing.
  // Works correctly for circular routes where two vertices share the same location.
  List<double>? shapeArcLengthsForStops;
  // Keep old field name for backward compat — now unused, kept to avoid cascade changes
  List<int>? shapeIndicesForStops;

  TripModel({
    required this.id,
    required this.gtfsFileId,
    required this.routeDbId,
    required this.serviceId,
    required this.tripId,
    this.tripHeadsign,
    this.directionId,
    this.blockId,
    this.shapeId,
    this.route,
    this.stopTimes,
    this.shapeIndicesForStops,
    this.shapeArcLengthsForStops,
  });

  factory TripModel.fromMap(Map<String, dynamic> map) {
    return TripModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      routeDbId: map['route_db_id'] as int,
      serviceId: map['service_id'] as String,
      tripId: map['trip_id'] as String,
      tripHeadsign: map['trip_headsign'] as String?,
      directionId: map['direction_id'] as int?,
      blockId: map['block_id'] as String?,
      shapeId: map['shape_id'] as String?,
    );
  }

  void generateDatetimes(DateTime date) {
    if (stopTimes == null || stopTimes!.isEmpty) return;

    final first = stopTimes!.first;
    final last = stopTimes!.last;

    startDatetime = first.getArrivalTimeInDate(date);
    endDatetime = last.getArrivalTimeInDate(date);
  }

  bool isActiveAt(DateTime d) {
    if (startDatetime == null || endDatetime == null) return false;
    return (d.isAfter(startDatetime!) || d.isAtSameMomentAs(startDatetime!)) &&
           (d.isBefore(endDatetime!) || d.isAtSameMomentAs(endDatetime!));
  }

  double getTripPercent(DateTime d) {
    if (startDatetime == null || endDatetime == null) return 0;
    if (!d.isAfter(startDatetime!)) return 0;
    if (!d.isBefore(endDatetime!)) return 100;
    final max = endDatetime!.millisecondsSinceEpoch - startDatetime!.millisecondsSinceEpoch;
    final current = d.millisecondsSinceEpoch - startDatetime!.millisecondsSinceEpoch;
    return (current / max) * 100;
  }

  String getStartHour() {
    if (startDatetime == null) return '--:--';
    final h = startDatetime!.hour.toString().padLeft(2, '0');
    final m = startDatetime!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String getEndHour() {
    if (endDatetime == null) return '--:--';
    final h = endDatetime!.hour.toString().padLeft(2, '0');
    final m = endDatetime!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class StopTimeModel {
  final int id;
  final int gtfsFileId;
  final int tripDbId;
  final int stopDbId;
  final String arrivalTime;
  final String departureTime;
  final int stopSequence;
  final String? stopHeadsign;
  final int? pickupType;
  final int? dropOffType;

  // Loaded relationship
  StopModel? stop;
  TripModel? trip;

  StopTimeModel({
    required this.id,
    required this.gtfsFileId,
    required this.tripDbId,
    required this.stopDbId,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopSequence,
    this.stopHeadsign,
    this.pickupType,
    this.dropOffType,
    this.stop,
    this.trip,
  });

  factory StopTimeModel.fromMap(Map<String, dynamic> map) {
    return StopTimeModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      tripDbId: map['trip_db_id'] as int,
      stopDbId: map['stop_db_id'] as int,
      arrivalTime: map['arrival_time'] as String,
      departureTime: map['departure_time'] as String,
      stopSequence: map['stop_sequence'] as int,
      stopHeadsign: map['stop_headsign'] as String?,
      pickupType: map['pickup_type'] as int?,
      dropOffType: map['drop_off_type'] as int?,
    );
  }

  DateTime getArrivalTimeInDate(DateTime d) {
    final parts = arrivalTime.split(':').map(int.parse).toList();
    final hours = parts[0];
    final minutes = parts.length > 1 ? parts[1] : 0;
    final seconds = parts.length > 2 ? parts[2] : 0;
    // Handle times past midnight (e.g., 25:00:00)
    return DateTime(d.year, d.month, d.day)
        .add(Duration(hours: hours, minutes: minutes, seconds: seconds));
  }

  DateTime getDepartureTimeInDate(DateTime d) {
    final parts = departureTime.split(':').map(int.parse).toList();
    final hours = parts[0];
    final minutes = parts.length > 1 ? parts[1] : 0;
    final seconds = parts.length > 2 ? parts[2] : 0;
    // Handle times past midnight (e.g., 25:00:00)
    return DateTime(d.year, d.month, d.day)
        .add(Duration(hours: hours, minutes: minutes, seconds: seconds));
  }

  String get arrivalHourMin {
    final parts = arrivalTime.split(':');
    final h = int.parse(parts[0]) % 24;
    final m = parts.length > 1 ? parts[1] : '00';
    return '${h.toString().padLeft(2, '0')}:$m';
  }

  String getHeadsign() {
    if (stopHeadsign?.isNotEmpty == true) return stopHeadsign!;
    if (trip?.tripHeadsign?.isNotEmpty == true) return trip!.tripHeadsign!;
    return '-';
  }
}

class ShapeModel {
  final int id;
  final int gtfsFileId;
  final String shapeId;
  final double shapePtLat;
  final double shapePtLon;
  final int shapePtSequence;

  const ShapeModel({
    required this.id,
    required this.gtfsFileId,
    required this.shapeId,
    required this.shapePtLat,
    required this.shapePtLon,
    required this.shapePtSequence,
  });

  factory ShapeModel.fromMap(Map<String, dynamic> map) {
    return ShapeModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      shapeId: map['shape_id'] as String,
      shapePtLat: (map['shape_pt_lat'] as num).toDouble(),
      shapePtLon: (map['shape_pt_lon'] as num).toDouble(),
      shapePtSequence: map['shape_pt_sequence'] as int,
    );
  }
}

class CalendarModel {
  final int id;
  final int gtfsFileId;
  final String serviceId;
  final bool monday;
  final bool tuesday;
  final bool wednesday;
  final bool thursday;
  final bool friday;
  final bool saturday;
  final bool sunday;
  final DateTime startDate;
  final DateTime endDate;

  const CalendarModel({
    required this.id,
    required this.gtfsFileId,
    required this.serviceId,
    required this.monday,
    required this.tuesday,
    required this.wednesday,
    required this.thursday,
    required this.friday,
    required this.saturday,
    required this.sunday,
    required this.startDate,
    required this.endDate,
  });

  bool isActiveOnDay(int isoWeekday) {
    switch (isoWeekday) {
      case 1:
        return monday;
      case 2:
        return tuesday;
      case 3:
        return wednesday;
      case 4:
        return thursday;
      case 5:
        return friday;
      case 6:
        return saturday;
      case 7:
        return sunday;
      default:
        return false;
    }
  }

  bool isActiveOnDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (d.isBefore(start) || d.isAfter(end)) return false;
    return isActiveOnDay(date.weekday);
  }

  factory CalendarModel.fromMap(Map<String, dynamic> map) {
    return CalendarModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      serviceId: map['service_id'] as String,
      monday: (map['monday'] as int) == 1,
      tuesday: (map['tuesday'] as int) == 1,
      wednesday: (map['wednesday'] as int) == 1,
      thursday: (map['thursday'] as int) == 1,
      friday: (map['friday'] as int) == 1,
      saturday: (map['saturday'] as int) == 1,
      sunday: (map['sunday'] as int) == 1,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
    );
  }
}

class CalendarDateModel {
  final int id;
  final int gtfsFileId;
  final String serviceId;
  final DateTime date;
  final int exceptionType; // 1 = added, 2 = removed

  const CalendarDateModel({
    required this.id,
    required this.gtfsFileId,
    required this.serviceId,
    required this.date,
    required this.exceptionType,
  });

  factory CalendarDateModel.fromMap(Map<String, dynamic> map) {
    return CalendarDateModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      serviceId: map['service_id'] as String,
      date: DateTime.parse(map['date'] as String),
      exceptionType: map['exception_type'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// Route patterns (trayectos)
// ---------------------------------------------------------------------------

class RoutePatternModel {
  final int id;
  final int gtfsFileId;
  final int routeDbId;
  final String? name;
  final int directionId;
  final String? shapeId;

  // Loaded
  List<RoutePatternStopModel> stops;

  RoutePatternModel({
    required this.id,
    required this.gtfsFileId,
    required this.routeDbId,
    this.name,
    required this.directionId,
    this.shapeId,
    this.stops = const [],
  });

  String get displayName => name?.isNotEmpty == true ? name! : 'Trayecto $id';

  factory RoutePatternModel.fromMap(Map<String, dynamic> map) {
    return RoutePatternModel(
      id: map['id'] as int,
      gtfsFileId: map['gtfs_file_id'] as int,
      routeDbId: map['route_db_id'] as int,
      name: map['name'] as String?,
      directionId: map['direction_id'] as int? ?? 0,
      shapeId: map['shape_id'] as String?,
    );
  }
}

class RoutePatternStopModel {
  final int id;
  final int patternId;
  final int stopDbId;
  final int stopSequence;
  final int? timeFromOriginSeconds;

  // Loaded
  StopModel? stop;

  RoutePatternStopModel({
    required this.id,
    required this.patternId,
    required this.stopDbId,
    required this.stopSequence,
    this.timeFromOriginSeconds,
    this.stop,
  });

  /// Format time as "mm:ss"
  String get formattedTime {
    if (timeFromOriginSeconds == null) return '--:--';
    final m = timeFromOriginSeconds! ~/ 60;
    final s = timeFromOriginSeconds! % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  factory RoutePatternStopModel.fromMap(Map<String, dynamic> map) {
    return RoutePatternStopModel(
      id: map['id'] as int,
      patternId: map['pattern_id'] as int,
      stopDbId: map['stop_db_id'] as int,
      stopSequence: map['stop_sequence'] as int,
      timeFromOriginSeconds: map['time_from_origin_seconds'] as int?,
    );
  }
}

class ServiceInfo {
  final String serviceId;
  final int gtfsFileId;
  final String gtfsFilename;

  const ServiceInfo({
    required this.serviceId,
    required this.gtfsFileId,
    required this.gtfsFilename,
  });
}

/// Lightweight summary of a single trip (expedición) for display in the editor.
class ExpedicionSummary {
  final int tripDbId;
  final String serviceId;
  final String? headsign;
  final int? directionId;
  final String? departureTime; // "HH:MM:SS"
  final String? arrivalTime;   // "HH:MM:SS"
  final int stopCount;

  const ExpedicionSummary({
    required this.tripDbId,
    required this.serviceId,
    this.headsign,
    this.directionId,
    this.departureTime,
    this.arrivalTime,
    this.stopCount = 0,
  });

  /// Returns "HH:MM" from "HH:MM:SS" (or the raw value if unexpected format).
  static String _hhmm(String? t) {
    if (t == null) return '--:--';
    final parts = t.split(':');
    if (parts.length < 2) return t;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  String get depHHMM => _hhmm(departureTime);
  String get arrHHMM => _hhmm(arrivalTime);

  String get displayLabel {
    if (headsign != null && headsign!.isNotEmpty) return headsign!;
    if (directionId != null) return directionId == 0 ? 'Ida' : 'Vuelta';
    return '';
  }
}
