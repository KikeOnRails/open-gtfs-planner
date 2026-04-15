import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/gtfs_models.dart';
import '../core/database/gtfs_repository.dart';
import 'project_providers.dart';

// ---------------------------------------------------------------------------
// Map Controller (shared across widgets)
// ---------------------------------------------------------------------------

final mapControllerProvider = Provider<MapController>((ref) {
  return MapController();
});

// ---------------------------------------------------------------------------
// Simulation date/time
// ---------------------------------------------------------------------------

class SimulationTime {
  final DateTime dateTime;
  final bool isPlaying;
  final int speedMultiplier; // 1, 2, 3, 5

  const SimulationTime({
    required this.dateTime,
    this.isPlaying = false,
    this.speedMultiplier = 1,
  });

  SimulationTime copyWith({
    DateTime? dateTime,
    bool? isPlaying,
    int? speedMultiplier,
  }) =>
      SimulationTime(
        dateTime: dateTime ?? this.dateTime,
        isPlaying: isPlaying ?? this.isPlaying,
        speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      );

  String get timeString {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get dateString {
    final y = dateTime.year.toString();
    final mo = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$mo-$d';
  }
}

final simulationTimeProvider =
    StateNotifierProvider<SimulationTimeNotifier, SimulationTime>(
  (_) => SimulationTimeNotifier(),
);

class SimulationTimeNotifier extends StateNotifier<SimulationTime> {
  SimulationTimeNotifier() : super(SimulationTime(dateTime: DateTime.now()));

  void setDateTime(DateTime dt) {
    state = state.copyWith(dateTime: dt);
  }

  void setDate(DateTime d) {
    final cur = state.dateTime;
    state = state.copyWith(
      dateTime:
          DateTime(d.year, d.month, d.day, cur.hour, cur.minute, cur.second),
    );
  }

  void setTime(int h, int m, int s) {
    final cur = state.dateTime;
    state = state.copyWith(
      dateTime: DateTime(cur.year, cur.month, cur.day, h, m, s),
    );
  }

  void advance() {
    final dt = state.dateTime.add(Duration(seconds: 5 * state.speedMultiplier));
    state = state.copyWith(dateTime: dt);
  }

  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);

  void nextSpeed() {
    const speeds = [1, 2, 3, 5];
    final idx = speeds.indexOf(state.speedMultiplier);
    final next = speeds[(idx + 1) % speeds.length];
    state = state.copyWith(speedMultiplier: next);
  }
}

// ---------------------------------------------------------------------------
// Active services for the current simulation date
// ---------------------------------------------------------------------------

final activeServicesProvider = FutureProvider<List<ServiceInfo>>((ref) async {
  // Solo observar la FECHA, no la hora completa
  final simDate = ref.watch(simulationTimeProvider.select((state) =>
      DateTime(state.dateTime.year, state.dateTime.month, state.dateTime.day)));
  final gtfsFilesAsync = ref.watch(gtfsFilesProvider);

  final gtfsFiles = gtfsFilesAsync.valueOrNull ?? [];
  if (gtfsFiles.isEmpty) return [];

  return GtfsRepository.getActiveServices(gtfsFiles, simDate);
});

// ---------------------------------------------------------------------------
// Trips in route (active at current simulation time)
// ---------------------------------------------------------------------------

final activeTripsProvider =
    AsyncNotifierProvider<ActiveTripsNotifier, List<TripModel>>(
        ActiveTripsNotifier.new);

class ActiveTripsNotifier extends AsyncNotifier<List<TripModel>> {
  @override
  Future<List<TripModel>> build() async {
    final services = await ref.watch(activeServicesProvider.future);
    // Solo observar la fecha, no la hora completa para evitar rebuilds en cada tick
    ref.watch(simulationTimeProvider.select((state) => DateTime(
        state.dateTime.year, state.dateTime.month, state.dateTime.day)));
    final simVisibility = ref.watch(routeSimulationVisibilityProvider);

    if (services.isEmpty) return [];

    final gtfsFileIds = services.map((s) => s.gtfsFileId).toSet().toList();
    final serviceIds = services.map((s) => s.serviceId).toList();

    final allTrips =
        await GtfsRepository.getTripsByServices(gtfsFileIds, serviceIds);

    await GtfsRepository.loadStopTimesForTrips(allTrips);

    // Generate datetimes relative to simulation date
    // Usar la fecha completa del provider para generar datetimes
    final fullDateTime = ref.read(simulationTimeProvider).dateTime;
    for (final trip in allTrips) {
      trip.generateDatetimes(fullDateTime);
    }

    // Retornar todos los trips del día, el filtrado por hora se hará en el widget
    // para evitar rebuilds constantes
    final visibleRouteIds =
        simVisibility.entries.where((e) => e.value).map((e) => e.key).toSet();

    if (visibleRouteIds.isEmpty) {
      return allTrips;
    }

    return allTrips
        .where((t) => visibleRouteIds.contains(t.routeDbId))
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Selected stop / trip (panel info)
// ---------------------------------------------------------------------------

final selectedStopProvider = StateProvider<StopModel?>((ref) => null);
final selectedTripProvider = StateProvider<TripModel?>((ref) => null);

// ---------------------------------------------------------------------------
// Stop times for selected stop
// ---------------------------------------------------------------------------

final selectedStopTimesProvider =
    FutureProvider<List<StopTimeModel>>((ref) async {
  final stop = ref.watch(selectedStopProvider);
  if (stop == null) return [];

  final services = await ref.watch(activeServicesProvider.future);
  final simTime = ref.watch(simulationTimeProvider);
  final serviceIds = services.map((s) => s.serviceId).toList();

  final stopTimes = await GtfsRepository.getStopTimesByStop(
    stop.id,
    serviceIds,
    simTime.dateTime,
  );

  // Sort by arrival time
  stopTimes.sort((a, b) {
    final at = a.getArrivalTimeInDate(simTime.dateTime);
    final bt = b.getArrivalTimeInDate(simTime.dateTime);
    return at.compareTo(bt);
  });

  return stopTimes;
});

// ---------------------------------------------------------------------------
// Stops visible on map
// ---------------------------------------------------------------------------

final visibleStopsProvider = FutureProvider<List<StopModel>>((ref) async {
  final gtfsFilesAsync = ref.watch(gtfsFilesProvider);
  final fileVisibility = ref.watch(gtfsStopsVisibilityProvider);

  final gtfsFiles = gtfsFilesAsync.valueOrNull ?? [];
  final stops = <StopModel>[];

  for (final file in gtfsFiles) {
    if (fileVisibility[file.id] == true) {
      stops.addAll(await GtfsRepository.getStops(file.id));
    }
  }

  return stops;
});

// ---------------------------------------------------------------------------
// Interpolation mode (shape-based or direct geodetic)
// ---------------------------------------------------------------------------

final useShapeInterpolationProvider = StateProvider<bool>((ref) => true);
