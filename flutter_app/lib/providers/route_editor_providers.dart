import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/gtfs_repository.dart';
import '../core/services/osrm_service.dart';
import '../models/gtfs_models.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class PatternEditorState {
  final RouteModel route;
  final GtfsFileModel gtfsFile;

  /// Pattern being edited (null = new, unsaved pattern)
  final int? patternId;

  final String patternName;

  /// Ordered stop list
  final List<StopModel> stops;

  /// Time from origin for each stop, in seconds (null = not defined yet).
  /// Same length as [stops].
  final List<int?> timesFromOriginSeconds;

  /// Shape as (lat, lon) pairs computed by OSRM. Empty until calculated.
  final List<(double, double)> shapePoints;

  /// Whether clicking a stop on the map adds it to the sequence.
  final bool isPickingStop;

  final bool isCalculatingShape;
  final bool isSaving;
  final String? error;

  const PatternEditorState({
    required this.route,
    required this.gtfsFile,
    this.patternId,
    this.patternName = '',
    this.stops = const [],
    this.timesFromOriginSeconds = const [],
    this.shapePoints = const [],
    this.isPickingStop = true,
    this.isCalculatingShape = false,
    this.isSaving = false,
    this.error,
  });

  PatternEditorState copyWith({
    int? Function()? patternId,
    String? patternName,
    List<StopModel>? stops,
    List<int?>? timesFromOriginSeconds,
    List<(double, double)>? shapePoints,
    bool? isPickingStop,
    bool? isCalculatingShape,
    bool? isSaving,
    String? Function()? error,
  }) {
    return PatternEditorState(
      route: route,
      gtfsFile: gtfsFile,
      patternId: patternId != null ? patternId() : this.patternId,
      patternName: patternName ?? this.patternName,
      stops: stops ?? this.stops,
      timesFromOriginSeconds:
          timesFromOriginSeconds ?? this.timesFromOriginSeconds,
      shapePoints: shapePoints ?? this.shapePoints,
      isPickingStop: isPickingStop ?? this.isPickingStop,
      isCalculatingShape: isCalculatingShape ?? this.isCalculatingShape,
      isSaving: isSaving ?? this.isSaving,
      error: error != null ? error() : this.error,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PatternEditorNotifier extends StateNotifier<PatternEditorState?> {
  PatternEditorNotifier() : super(null);

  bool get isActive => state != null;

  void start(RouteModel route, GtfsFileModel gtfsFile) {
    state = PatternEditorState(route: route, gtfsFile: gtfsFile);
  }

  /// Load an existing pattern for editing.
  Future<void> editPattern(
      RoutePatternModel pattern, GtfsFileModel gtfsFile, RouteModel route) async {
    // Set a loading state first
    state = PatternEditorState(
      route: route,
      gtfsFile: gtfsFile,
      patternId: pattern.id,
      patternName: pattern.name ?? '',
      isPickingStop: true,
    );
    try {
      final patternStops = await GtfsRepository.getPatternStops(pattern.id);
      final stops = patternStops
          .where((ps) => ps.stop != null)
          .map((ps) => ps.stop!)
          .toList();
      final times = patternStops
          .map((ps) => ps.timeFromOriginSeconds)
          .toList();

      List<(double, double)> shapePoints = [];
      if (pattern.shapeId != null && pattern.shapeId!.isNotEmpty) {
        shapePoints = await GtfsRepository.getShapePointsForId(
            gtfsFile.id, pattern.shapeId!);
      }

      state = PatternEditorState(
        route: route,
        gtfsFile: gtfsFile,
        patternId: pattern.id,
        patternName: pattern.name ?? '',
        stops: stops,
        timesFromOriginSeconds: times,
        shapePoints: shapePoints,
        isPickingStop: true,
      );
    } catch (e) {
      state = state?.copyWith(error: () => 'Error cargando trayecto: $e');
    }
  }

  void cancel() => state = null;

  void setPatternName(String name) {
    state = state?.copyWith(patternName: name);
  }

  void addStop(StopModel stop) {
    if (state == null) return;
    // Avoid adding the same stop twice consecutively
    if (state!.stops.isNotEmpty && state!.stops.last.id == stop.id) return;
    final stops = [...state!.stops, stop];
    final times = [...state!.timesFromOriginSeconds, null];
    // Auto-set first stop to 0
    if (stops.length == 1) times[0] = 0;
    state = state!.copyWith(
      stops: stops,
      timesFromOriginSeconds: times,
      shapePoints: [],
    );
  }

  void removeStop(int index) {
    if (state == null) return;
    final stops = [...state!.stops]..removeAt(index);
    final times = [...state!.timesFromOriginSeconds]..removeAt(index);
    state = state!.copyWith(
      stops: stops,
      timesFromOriginSeconds: times,
      shapePoints: [],
    );
  }

  void reorderStops(int oldIndex, int newIndex) {
    if (state == null) return;
    final stops = [...state!.stops];
    final times = [...state!.timesFromOriginSeconds];
    if (newIndex > oldIndex) newIndex -= 1;
    final stop = stops.removeAt(oldIndex);
    final time = times.removeAt(oldIndex);
    stops.insert(newIndex, stop);
    times.insert(newIndex, time);
    state = state!.copyWith(
      stops: stops,
      timesFromOriginSeconds: times,
      shapePoints: [],
    );
  }

  void setTimeFromOrigin(int index, int? seconds) {
    if (state == null || index >= state!.timesFromOriginSeconds.length) return;
    final times = [...state!.timesFromOriginSeconds];
    times[index] = seconds;
    state = state!.copyWith(timesFromOriginSeconds: times);
  }

  Future<void> calculateShape() async {
    if (state == null || state!.stops.length < 2) return;
    state = state!.copyWith(isCalculatingShape: true, error: () => null);
    try {
      final waypoints =
          state!.stops.map((s) => (s.stopLat, s.stopLon)).toList();
      final points = await OsrmService.getRouteGeometry(waypoints);
      state = state!.copyWith(
        isCalculatingShape: false,
        shapePoints: points,
      );
    } catch (e) {
      state = state!.copyWith(
        isCalculatingShape: false,
        error: () => 'Error calculando shape: $e',
      );
    }
  }

  /// Persists the pattern (creates if new, overwrites stops/shape if existing).
  /// Returns the saved [RoutePatternModel] or null on failure.
  Future<RoutePatternModel?> save() async {
    if (state == null) return null;
    state = state!.copyWith(isSaving: true, error: () => null);
    try {
      final s = state!;
      int patternId = s.patternId ??
          await GtfsRepository.insertRoutePattern(
              s.gtfsFile.id, s.route.id, s.patternName.isEmpty ? null : s.patternName);

      // Update name if already existed
      if (s.patternId != null) {
        await GtfsRepository.updateRoutePatternName(
            patternId, s.patternName.isEmpty ? '' : s.patternName);
      }

      // Save stops
      final stopsData = <Map<String, dynamic>>[];
      for (int i = 0; i < s.stops.length; i++) {
        stopsData.add({
          'stop_db_id': s.stops[i].id,
          'time_from_origin_seconds': s.timesFromOriginSeconds[i],
        });
      }
      await GtfsRepository.savePatternStops(patternId, stopsData);

      // Save shape if computed
      if (s.shapePoints.isNotEmpty) {
        await GtfsRepository.savePatternShape(
            patternId, s.gtfsFile.id, s.shapePoints);
      }

      state = null;
      return await GtfsRepository.getRoutePatternById(patternId);
    } catch (e) {
      state = state!.copyWith(isSaving: false, error: () => e.toString());
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final patternEditorProvider =
    StateNotifierProvider<PatternEditorNotifier, PatternEditorState?>(
  (_) => PatternEditorNotifier(),
);
