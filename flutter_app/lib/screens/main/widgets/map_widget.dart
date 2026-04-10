import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/interpolation_helper.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/simulation_providers.dart';

class MapWidget extends ConsumerStatefulWidget {
  const MapWidget({super.key});

  @override
  ConsumerState<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends ConsumerState<MapWidget> {
  final MapController _mapController = MapController();
  bool _initialized = false;
  // Cache for shapes: gtfsFileId -> shape_id -> List<LatLng>
  final Map<int, Map<String, List<LatLng>>> _shapesCache = {};
  // Cache for stops per file
  final Map<int, List<StopModel>> _stopsCache = {};

  @override
  Widget build(BuildContext context) {
    final simTime = ref.watch(simulationTimeProvider);
    final activeTripsAsync = ref.watch(activeTripsProvider);
    final gtfsFilesAsync = ref.watch(gtfsFilesProvider);
    final fileVis = ref.watch(gtfsFileVisibilityProvider);
    final shapeVis = ref.watch(routeShapeVisibilityProvider);
    final stopsVis = ref.watch(gtfsStopsVisibilityProvider);
    final simVis = ref.watch(routeSimulationVisibilityProvider);
    final selectedStop = ref.watch(selectedStopProvider);
    final selectedTrip = ref.watch(selectedTripProvider);

    final gtfsFiles = gtfsFilesAsync.valueOrNull ?? [];

    // Load shapes and stops reactively
    _preloadLayerData(gtfsFiles, shapeVis, stopsVis);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(40.4168, -3.7038), // Madrid
        initialZoom: 13,
        onTap: (_, pos) => _handleMapTap(pos, simTime.dateTime),
      ),
      children: [
        // OSM Tile Layer (free)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.opengtfsplanner.app',
          maxZoom: 19,
          tileBuilder: _darkTileBuilder,
        ),

        // Route shapes (polylines)
        PolylineLayer(
          polylines: _buildPolylines(gtfsFiles, fileVis, shapeVis),
        ),

        // Stop markers
        MarkerLayer(
          markers: _buildStopMarkers(gtfsFiles, stopsVis, selectedStop),
        ),

        // Vehicle simulation markers
        MarkerLayer(
          markers: activeTripsAsync.when(
            data: (trips) => _buildVehicleMarkers(trips, simTime.dateTime,
                simVis, selectedTrip),
            loading: () => [],
            error: (_, __) => [],
          ),
        ),

        // Attribution
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }

  void _preloadLayerData(
    List<GtfsFileModel> files,
    Map<int, bool> shapeVis,
    Map<int, bool> stopsVis,
  ) {
    for (final file in files) {
      // Load shapes if any route from this file has shape visibility
      if (!_shapesCache.containsKey(file.id)) {
        _loadShapesForFile(file.id);
      }
      // Load stops if stops visibility is enabled
      if (stopsVis[file.id] == true && !_stopsCache.containsKey(file.id)) {
        _loadStopsForFile(file.id);
      }
    }
  }

  Future<void> _loadShapesForFile(int gtfsFileId) async {
    // Avoid duplicate loads
    _shapesCache[gtfsFileId] = {};

    final shapes =
        await GtfsRepository.getAllShapesByGtfsFile(gtfsFileId);
    final grouped = GtfsRepository.groupShapes(shapes);

    final latLngMap = <String, List<LatLng>>{};
    for (final entry in grouped.entries) {
      final pts = entry.value
          .map((s) => LatLng(s.shapePtLat, s.shapePtLon))
          .toList();
      latLngMap[entry.key] = pts;
    }

    if (mounted) {
      setState(() {
        _shapesCache[gtfsFileId] = latLngMap;
      });
    }
  }

  Future<void> _loadStopsForFile(int gtfsFileId) async {
    _stopsCache[gtfsFileId] = [];

    final stops = await GtfsRepository.getStops(gtfsFileId);

    if (mounted) {
      setState(() {
        _stopsCache[gtfsFileId] = stops;
      });
    }
  }

  List<Polyline> _buildPolylines(
    List<GtfsFileModel> files,
    Map<int, bool> fileVis,
    Map<int, bool> shapeVis,
  ) {
    final polylines = <Polyline>[];

    for (final file in files) {
      if (fileVis[file.id] == false) continue;
      final shapes = _shapesCache[file.id];
      if (shapes == null) continue;

      for (final entry in shapes.entries) {
        if (entry.value.isEmpty) continue;
        // Only show if the route for this shape is visible
        // (if no specific routes enabled, show all shapes in visible files)
        polylines.add(
          Polyline(
            points: entry.value,
            color: AppTheme.primary.withOpacity(0.7),
            strokeWidth: 3,
          ),
        );
      }
    }

    return polylines;
  }

  List<Marker> _buildStopMarkers(
    List<GtfsFileModel> files,
    Map<int, bool> stopsVis,
    StopModel? selectedStop,
  ) {
    final markers = <Marker>[];

    for (final file in files) {
      if (stopsVis[file.id] != true) continue;
      final stops = _stopsCache[file.id] ?? [];

      for (final stop in stops) {
        final isSelected = selectedStop?.id == stop.id;
        markers.add(
          Marker(
            point: LatLng(stop.stopLat, stop.stopLon),
            width: isSelected ? 24 : 16,
            height: isSelected ? 24 : 16,
            child: GestureDetector(
              onTap: () {
                ref.read(selectedStopProvider.notifier).state = stop;
                ref.read(selectedTripProvider.notifier).state = null;
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.orange : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.orange.shade800 : AppTheme.primary,
                    width: isSelected ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isSelected ? Colors.orange : AppTheme.primary)
                          .withOpacity(0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  List<Marker> _buildVehicleMarkers(
    List<TripModel> trips,
    DateTime simDateTime,
    Map<int, bool> simVis,
    TripModel? selectedTrip,
  ) {
    final markers = <Marker>[];

    for (final trip in trips) {
      // Check simulation visibility
      if (simVis.isNotEmpty && simVis[trip.routeDbId] != true) continue;

      final pos = _getTripPosition(trip, simDateTime);
      if (pos == null) continue;

      final route = trip.route;
      final routeColor = route != null
          ? hexToColor(route.routeColor)
          : AppTheme.primary;
      final textColor =
          route?.routeTextColor != null && route!.routeTextColor!.isNotEmpty
              ? hexToColor(route.routeTextColor)
              : Colors.white;

      final isSelected = selectedTrip?.id == trip.id;
      final size = isSelected ? 44.0 : 36.0;

      markers.add(
        Marker(
          point: pos,
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () {
              ref.read(selectedTripProvider.notifier).state = trip;
              ref.read(selectedStopProvider.notifier).state = null;
            },
            child: Container(
              decoration: BoxDecoration(
                color: routeColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.yellow : Colors.black,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: routeColor.withOpacity(0.5),
                    blurRadius: isSelected ? 10 : 4,
                    spreadRadius: isSelected ? 2 : 0,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  route?.displayName ?? '?',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: isSelected ? 12 : 10,
                  ),
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  LatLng? _getTripPosition(TripModel trip, DateTime simDateTime) {
    final stopTimes = trip.stopTimes;
    if (stopTimes == null || stopTimes.isEmpty) return null;

    // Find prev/next stop
    StopTimeModel? prev;
    StopTimeModel? next;

    for (var i = 0; i < stopTimes.length; i++) {
      final arrivalDt = stopTimes[i].getArrivalTimeInDate(simDateTime);
      if (arrivalDt.isAfter(simDateTime)) {
        next = stopTimes[i];
        if (i > 0) prev = stopTimes[i - 1];
        break;
      }
    }

    if (next == null) {
      // Past the last stop
      final last = stopTimes.last;
      final s = last.stop;
      if (s == null) return null;
      return LatLng(s.stopLat, s.stopLon);
    }

    if (prev == null) {
      // Before first stop
      final s = next.stop;
      if (s == null) return null;
      return LatLng(s.stopLat, s.stopLon);
    }

    final prevStop = prev.stop;
    final nextStop = next.stop;
    if (prevStop == null || nextStop == null) return null;

    final timePrev = prev.getArrivalTimeInDate(simDateTime).millisecondsSinceEpoch;
    final timeNext = next.getArrivalTimeInDate(simDateTime).millisecondsSinceEpoch;
    final timeCurrent = simDateTime.millisecondsSinceEpoch;

    double fraction;
    if (timeCurrent <= timePrev) {
      fraction = 0;
    } else if (timeCurrent >= timeNext) {
      fraction = 1;
    } else {
      fraction = (timeCurrent - timePrev) / (timeNext - timePrev);
    }

    final result = InterpolationHelper.interpolateGeodetic(
      prevStop.stopLat,
      prevStop.stopLon,
      nextStop.stopLat,
      nextStop.stopLon,
      fraction,
    );

    return LatLng(result.$1, result.$2);
  }

  void _handleMapTap(LatLng pos, DateTime simDateTime) {
    const threshold = 50.0; // metres

    // Check if click is on a trip
    final selectedTrip = ref.read(selectedTripProvider);
    if (selectedTrip != null) {
      final tripPos = _getTripPosition(selectedTrip, simDateTime);
      if (tripPos != null) {
        final dist = InterpolationHelper.haversineMeters(
            pos.latitude, pos.longitude, tripPos.latitude, tripPos.longitude);
        if (dist > threshold) {
          ref.read(selectedTripProvider.notifier).state = null;
        }
      }
    }

    // Check if click is on a stop
    final selectedStop = ref.read(selectedStopProvider);
    if (selectedStop != null) {
      final dist = InterpolationHelper.haversineMeters(
          pos.latitude,
          pos.longitude,
          selectedStop.stopLat,
          selectedStop.stopLon);
      if (dist > threshold) {
        ref.read(selectedStopProvider.notifier).state = null;
      }
    }
  }

  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.8, 0, 0, 0, 255,
        0, -0.8, 0, 0, 255,
        0, 0, -0.8, 0, 255,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}
