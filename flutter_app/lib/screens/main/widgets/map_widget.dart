import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/interpolation_helper.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/shape_editor_provider.dart';
import '../../../providers/simulation_providers.dart';
import 'merge_stops_dialog.dart';
import 'create_stop_dialog.dart';
import 'shape_editor_layer.dart';
import '../../../providers/route_editor_providers.dart';

class MapWidget extends ConsumerStatefulWidget {
  const MapWidget({super.key});

  @override
  ConsumerState<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends ConsumerState<MapWidget> {
  late MapController _mapController;
  // Cache for shapes: gtfsFileId -> shape_id -> List<LatLng>
  final Map<int, Map<String, List<LatLng>>> _shapesCache = {};
  // Cache of cumulative arc-length distances per shape (for polyline projection)
  final Map<int, Map<String, List<double>>> _shapeCumDistCache = {};
  int _lastShapeCacheVersion = 0;
  int _lastStopsCacheVersion = 0;
  // Cache for stops per file
  final Map<int, List<StopModel>> _stopsCache = {};
  // Cache para mapear shape_id -> route (para obtener colores)
  final Map<String, RouteModel> _shapeToRouteCache = {};
  // Cache de rutas por archivo
  final Map<int, List<RouteModel>> _routesCache = {};
  // Cache de paradas por ruta: routeId -> List<StopModel>
  final Map<int, List<StopModel>> _routeStopsCache = {};

  // Cache de cadencias calculadas por corredor: key -> label (ej. "12 min")
  final Map<String, String> _corridorHeadwayLabels = {};
  // Cache numérico de cadencia en minutos: key -> minutos (null = sin datos)
  final Map<String, double?> _corridorHeadwayMinutes = {};
  // Corredores cuya análisis ya está en curso para no duplicar peticiones
  final Set<String> _corridorAnalysisPending = {};

  @override
  void initState() {
    super.initState();
    _mapController = ref.read(mapControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Observar solo lo necesario
    final gtfsFilesAsync = ref.watch(gtfsFilesProvider);
    final gtfsFiles = gtfsFilesAsync.valueOrNull ?? [];
    final fileVis = ref.watch(gtfsFileVisibilityProvider);
    final shapeVis = ref.watch(routeShapeVisibilityProvider);
    final stopsVis = ref.watch(gtfsStopsVisibilityProvider);
    final selectedStop = ref.watch(selectedStopProvider);
    final secondSelectedStop = ref.watch(secondSelectedStopProvider);
    final agencyVis = ref.watch(agencyVisibilityProvider);

    // Solo observar el dateTime para vehículos
    final simDateTime =
        ref.watch(simulationTimeProvider.select((state) => state.dateTime));
    final activeTripsAsync = ref.watch(activeTripsProvider);
    final simVis = ref.watch(routeSimulationVisibilityProvider);
    final selectedTrip = ref.watch(selectedTripProvider);

    // Watch stops cache version — when it changes, clear the local stops cache.
    final stopsCacheVersion = ref.watch(stopsCacheVersionProvider);
    if (_lastStopsCacheVersion != stopsCacheVersion) {
      _lastStopsCacheVersion = stopsCacheVersion;
      _stopsCache.clear();
      _routeStopsCache.clear();
    }

    // Watch shape cache version — when it changes, clear the local cache so
    // newly generated shapes are reloaded from the database.
    final shapeCacheVersion = ref.watch(shapeCacheVersionProvider);
    if (_lastShapeCacheVersion != shapeCacheVersion) {
      _lastShapeCacheVersion = shapeCacheVersion;
      _shapesCache.clear();
      _shapeCumDistCache.clear();
      _shapeToRouteCache.clear();
      _routesCache.clear();
      _routeStopsCache.clear();
      // Synchronously reset shapeIndicesForStops on ALL known trips so they
      // are unconditionally recomputed against the new shape geometry.
      // This runs in the same frame as the cache clear, before any
      // async reload can complete — eliminating all race conditions.
      final knownTrips = ref.read(activeTripsProvider).valueOrNull;
      if (knownTrips != null) {
        for (final trip in knownTrips) {
          trip.shapeIndicesForStops = null;
          trip.shapeArcLengthsForStops = null;
        }
      }
    }

    final editState = ref.watch(shapeEditorProvider);

    // Load shapes and stops reactively
    _preloadLayerData(gtfsFiles, shapeVis, stopsVis);

    // Pattern editor state (for live shape preview and stop-click interception)
    final patternState = ref.watch(patternEditorProvider);

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(40.4168, -3.7038), // Madrid
        initialZoom: 13,
        onTap: (_, pos) => _handleMapTap(pos, simDateTime),
        // Disable map pan/zoom while the user is dragging a shape point
        // so the map doesn't compete for the pointer event.
        interactionOptions: InteractionOptions(
          flags: (editState?.isDraggingPoint == true)
              ? InteractiveFlag.none
              : InteractiveFlag.all,
        ),
      ),
      children: [
        // OSM Tile Layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.opengtfsplanner.app',
          maxZoom: 19,
          tileBuilder: _darkTileBuilder,
          tileProvider: CancellableNetworkTileProvider(),
        ),

        // Route shapes (polylines) — skip the shape being edited
        PolylineLayer(
          polylines: _buildPolylines(
            gtfsFiles, fileVis, shapeVis, selectedTrip, agencyVis,
            excludeShapeId: editState?.shapeId,
          ),
        ),

        // Corridor overlay (detected corridors)
        ..._buildCorridorLayers(ref),

        // Pattern editor: live shape preview
        if (patternState != null && patternState.shapePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: patternState.shapePoints
                    .map((p) => LatLng(p.$1, p.$2))
                    .toList(),
                strokeWidth: 3.5,
                color: Colors.orangeAccent.withOpacity(0.9),
                borderColor: Colors.orange.shade900.withOpacity(0.6),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),

        // Stop markers
        MarkerLayer(
          markers: _buildStopMarkers(gtfsFiles, stopsVis, selectedStop,
              ref.watch(routeStopsVisibilityProvider), agencyVis,
              secondSelectedStop: secondSelectedStop),
        ),

        // Vehicle simulation markers
        activeTripsAsync.when(
          data: (trips) {
            final activeNow =
                trips.where((t) => t.isActiveAt(simDateTime)).toList();
            // Precompute shape indices for trips that don't have them yet
            _precomputeShapeIndices(activeNow);
            return MarkerLayer(
              markers: _buildVehicleMarkers(
                  activeNow, simDateTime, simVis, selectedTrip, agencyVis),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),

        // Shape editor layer (handles + edit polyline)
        const ShapeEditorLayer(),

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

    final twoStopsSelected =
        selectedStop != null && secondSelectedStop != null;

    // Always wrap in Stack for overlay toolbars and hints
    return Stack(children: [
      map,

      // Edit toolbar (shape editor)
      if (editState != null)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(child: _buildEditToolbar(context, editState)),
        ),

      // Two-stop action toolbar
      if (twoStopsSelected && editState == null)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: _buildTwoStopToolbar(
                context, selectedStop, secondSelectedStop),
          ),
        ),

      // Pick-stop-location mode banner
      if (ref.watch(pickStopLocationProvider) != null)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF01E2129),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.withOpacity(0.7), width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.my_location, size: 14, color: Colors.teal),
                  const SizedBox(width: 8),
                  const Text('Toca el mapa para colocar la parada',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => ref.read(pickStopLocationProvider.notifier).state = null,
                    child: const Icon(Icons.close, size: 14, color: Colors.white54),
                  ),
                ]),
              ),
            ),
          ),
        ),

      // Create stop FAB (bottom-left)
      if (editState == null && ref.watch(pickStopLocationProvider) == null)
        Positioned(
          bottom: 56,
          left: 12,
          child: Tooltip(
            message: 'Crear parada: pincha en el mapa para colocarla',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => activatePickStopMode(context, ref),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xF01E2129),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal.withOpacity(0.5), width: 1),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_location_alt, size: 14, color: Colors.teal),
                    SizedBox(width: 6),
                    Text('Nueva parada',
                        style: TextStyle(
                            color: Colors.teal,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
        ),

      // Help hint (bottom-right)
      if (editState == null)
        const Positioned(
          bottom: 12,
          right: 12,
          child: _MapHint(),
        ),
    ]);
  }

  Widget _buildTwoStopToolbar(
      BuildContext context, StopModel stopA, StopModel stopB) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xF01E2129),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.place, color: Colors.orange, size: 14),
          const SizedBox(width: 4),
          Text(
            stopA.displayName,
            style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.add, color: Colors.white38, size: 14),
          const SizedBox(width: 8),
          const Icon(Icons.place, color: Colors.cyan, size: 14),
          const SizedBox(width: 4),
          Text(
            stopB.displayName,
            style: const TextStyle(color: Colors.cyan, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: Colors.white12),
          const SizedBox(width: 12),
          // Merge button
          _ToolbarBtn(
            icon: Icons.merge_type,
            label: 'Unificar parada',
            enabled: true,
            color: Colors.teal,
            onTap: () async {
              final merged = await showMergeStopsDialog(
                  context, ref, stopA, stopB);
              if (!mounted) return;
              if (merged != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    backgroundColor: const Color(0xFF0D5C47),
                    content: Row(children: [
                      const Icon(Icons.check_circle,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Paradas unificadas como "${merged.displayName}"',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
                );
                if (mounted) setState(() {});
              }
            },
          ),
          const SizedBox(width: 8),
          // Deselect button
          _ToolbarBtn(
            icon: Icons.close,
            label: 'Deseleccionar',
            enabled: true,
            color: Colors.white54,
            onTap: () {
              ref.read(selectedStopProvider.notifier).state = null;
              ref.read(secondSelectedStopProvider.notifier).state = null;
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildEditToolbar(BuildContext context, ShapeEditState editState) {
    final mode = editState.mode;
    final notifier = ref.read(shapeEditorProvider.notifier);
    final isBusy = editState.isSaving;

    // Border colour reflects active mode
    final borderColor = switch (mode) {
      ShapeEditMode.delete => Colors.red.withOpacity(0.7),
      ShapeEditMode.append => Colors.green.withOpacity(0.7),
      ShapeEditMode.prepend => Colors.blue.withOpacity(0.7),
      _ => Colors.orange.withOpacity(0.6),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xF01E2129),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // --- Title ---
          const Icon(Icons.edit_road, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                editState.routeName.isNotEmpty
                    ? editState.routeName
                    : 'Editando shape',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '${editState.points.length} puntos',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 12),
          _ToolbarDivider(),
          const SizedBox(width: 8),

          // --- Mode buttons ---
          Tooltip(
            message: 'Modo normal: arrastra puntos, toca el punto medio para insertar',
            child: _ModeBtn(
              icon: Icons.open_with,
              label: 'Mover',
              active: mode == ShapeEditMode.normal,
              color: Colors.orange,
              onTap: isBusy ? null : () => notifier.setMode(ShapeEditMode.normal),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Modo borrar: toca un punto para eliminarlo',
            child: _ModeBtn(
              icon: Icons.remove_circle_outline,
              label: 'Borrar',
              active: mode == ShapeEditMode.delete,
              color: Colors.red[300]!,
              onTap: isBusy ? null : () => notifier.setMode(ShapeEditMode.delete),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Modo añadir al final: toca el mapa para añadir un punto al final',
            child: _ModeBtn(
              icon: Icons.south_east,
              label: 'Añadir final',
              active: mode == ShapeEditMode.append,
              color: Colors.green[400]!,
              onTap: isBusy ? null : () => notifier.setMode(ShapeEditMode.append),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Modo añadir al inicio: toca el mapa para añadir un punto al principio',
            child: _ModeBtn(
              icon: Icons.north_west,
              label: 'Añadir inicio',
              active: mode == ShapeEditMode.prepend,
              color: Colors.blue[300]!,
              onTap: isBusy ? null : () => notifier.setMode(ShapeEditMode.prepend),
            ),
          ),
          const SizedBox(width: 8),
          _ToolbarDivider(),
          const SizedBox(width: 8),

          // --- History ---
          _ToolbarBtn(
            icon: Icons.undo,
            label: 'Deshacer',
            enabled: editState.canUndo && !isBusy,
            color: Colors.white70,
            onTap: () => notifier.undo(),
          ),
          const SizedBox(width: 4),
          _ToolbarBtn(
            icon: Icons.redo,
            label: 'Rehacer',
            enabled: editState.canRedo && !isBusy,
            color: Colors.white70,
            onTap: () => notifier.redo(),
          ),
          const SizedBox(width: 8),
          _ToolbarDivider(),
          const SizedBox(width: 8),

          // --- Simplify ---
          Tooltip(
            message: 'Simplificar: reduce puntos redundantes (tolerancia ~5 m)',
            child: _ToolbarBtn(
              icon: Icons.auto_fix_high,
              label: 'Simplificar',
              enabled: editState.points.length > 10 && !isBusy,
              color: Colors.purple[200]!,
              onTap: () => _showSimplifyDialog(context, editState),
            ),
          ),
          const SizedBox(width: 8),
          _ToolbarDivider(),
          const SizedBox(width: 8),

          // --- Cancel / Save ---
          _ToolbarBtn(
            icon: Icons.close,
            label: 'Cancelar',
            enabled: !isBusy,
            color: Colors.red[300]!,
            onTap: () => notifier.cancel(),
          ),
          const SizedBox(width: 4),
          _ToolbarBtn(
            icon: isBusy ? null : Icons.check,
            label: isBusy ? 'Guardando…' : 'Guardar',
            enabled: !isBusy,
            color: Colors.green[400]!,
            loading: isBusy,
            onTap: () async {
              final ok = await notifier.save();
              if (!mounted) return;
              // Bust shape tile cache so new geometry reloads from DB.
              ref.read(shapeCacheVersionProvider.notifier).state++;
              // Force trips to reload so shapeIndicesForStops is recomputed
              // against the updated shape geometry.
              ref.invalidate(activeTripsProvider);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                backgroundColor: ok ? const Color(0xFF1B6B3A) : Colors.red[800],
                content: Text(
                  ok ? 'Shape guardado correctamente' : 'Error al guardar',
                  style: const TextStyle(color: Colors.white),
                ),
              ));
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _showSimplifyDialog(
      BuildContext context, ShapeEditState editState) async {
    double tolerance = 5.0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1E2129),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Simplificar shape',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Puntos actuales: ${editState.points.length}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text(
                'Tolerancia: ${tolerance.toStringAsFixed(0)} m',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Slider(
                value: tolerance,
                min: 1,
                max: 50,
                divisions: 49,
                activeColor: Colors.purple[300],
                onChanged: (v) => setS(() => tolerance = v),
              ),
              Text(
                'Cuanto mayor la tolerancia, más puntos se eliminarán.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Simplificar',
                  style: TextStyle(color: Colors.purple[300])),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(shapeEditorProvider.notifier).simplify(tolerance);
    }
  }

  List<Marker> _buildVehicleMarkers(
    List<TripModel> trips,
    DateTime simDateTime,
    Map<int, bool> simVis,
    TripModel? selectedTrip,
    Map<int, bool> agencyVis,
  ) {
    final markers = <Marker>[];
    final fileVisibility = ref.read(gtfsFileVisibilityProvider);

    for (final trip in trips) {
      // Verificar si el archivo GTFS del trip está visible
      final isFileVisible = fileVisibility[trip.gtfsFileId] ?? true;
      if (!isFileVisible) continue;

      // Verificar visibilidad de la agencia
      final agencyDbId = trip.route?.agencyDbId;
      if (agencyDbId != null && agencyVis.containsKey(agencyDbId)) {
        if (agencyVis[agencyDbId] == false) continue;
      }
      
      if (simVis.isNotEmpty && simVis[trip.routeDbId] != true) continue;

      final pos = _getTripPosition(trip, simDateTime);
      if (pos == null) continue;

      final route = trip.route;
      final routeColor =
          route != null ? hexToColor(route.routeColor) : AppTheme.primary;
      final textColor =
          route?.routeTextColor != null && route!.routeTextColor!.isNotEmpty
              ? hexToColor(route.routeTextColor)
              : Colors.white;

      final isSelected = selectedTrip?.id == trip.id;
      final size = isSelected ? 44.0 : 36.0;

      markers.add(
        Marker(
          key: ValueKey('vehicle_${trip.id}'),
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

    StopTimeModel? prev;
    StopTimeModel? next;
    int prevIndex = 0;

    for (var i = 0; i < stopTimes.length; i++) {
      final arrivalDt = stopTimes[i].getArrivalTimeInDate(simDateTime);
      if (arrivalDt.isAfter(simDateTime)) {
        next = stopTimes[i];
        if (i > 0) {
          prev = stopTimes[i - 1];
          prevIndex = i - 1;
        }
        break;
      }
    }

    if (next == null) {
      final last = stopTimes.last;
      final s = last.stop;
      if (s == null) return null;
      return LatLng(s.stopLat, s.stopLon);
    }

    if (prev == null) {
      final s = next.stop;
      if (s == null) return null;
      return LatLng(s.stopLat, s.stopLon);
    }

    final prevStop = prev.stop;
    final nextStop = next.stop;
    if (prevStop == null || nextStop == null) return null;

    // Use departure_time for the previous stop so the vehicle stays at the
    // stop during its dwell time and only starts moving when it departs.
    // This avoids the slow-start / fast-end visual artefact caused by
    // counting dwell time as travel time.
    final timePrev =
        prev.getDepartureTimeInDate(simDateTime).millisecondsSinceEpoch;
    final timeNext =
        next.getArrivalTimeInDate(simDateTime).millisecondsSinceEpoch;
    final timeCurrent = simDateTime.millisecondsSinceEpoch;

    double fraction;
    if (timeCurrent <= timePrev) {
      fraction = 0;
    } else if (timeCurrent >= timeNext) {
      fraction = 1;
    } else {
      fraction = (timeCurrent - timePrev) / (timeNext - timePrev);
    }

    // Try to use shape if available — uses arc-length polyline projection
    // so it works correctly even for heavily simplified shapes where many
    // stops may lie between the same two simplified vertices.
    final useShapeInterpolation = ref.read(useShapeInterpolationProvider);

    if (useShapeInterpolation &&
        trip.shapeId != null &&
        trip.shapeId!.isNotEmpty) {
      final shapePath = _shapesCache[trip.gtfsFileId]?[trip.shapeId!];
      final arcLengths = trip.shapeArcLengthsForStops;

      if (shapePath != null &&
          shapePath.length >= 2 &&
          arcLengths != null &&
          arcLengths.length > prevIndex + 1) {
        // Get or compute cumulative arc-length distances (cached per shape)
        _shapeCumDistCache.putIfAbsent(trip.gtfsFileId, () => {});
        final cumDist = _shapeCumDistCache[trip.gtfsFileId]!.putIfAbsent(
          trip.shapeId!,
          () => InterpolationHelper.buildCumulativeDistances(shapePath),
        );

        // Precomputed arc lengths are monotonically increasing (computed with
        // forward-only projection), so they are unambiguous even for circular
        // routes where two vertices share the same physical location.
        final prevArcLen = arcLengths[prevIndex];
        final nextArcLen = arcLengths[prevIndex + 1];

        if (nextArcLen >= prevArcLen) {
          final targetArcLen = prevArcLen + (nextArcLen - prevArcLen) * fraction;
          return InterpolationHelper.pointAtArcLength(shapePath, cumDist, targetArcLen);
        }
      }
    }

    // Fallback to direct interpolation between stops
    final result = InterpolationHelper.interpolateGeodetic(
      prevStop.stopLat,
      prevStop.stopLon,
      nextStop.stopLat,
      nextStop.stopLon,
      fraction,
    );

    return LatLng(result.$1, result.$2);
  }

  /// Precompute monotonic arc-length positions for all stops in each trip.
  /// Runs once per trip+shape combination and stores the result in
  /// [TripModel.shapeArcLengthsForStops].
  ///
  /// Strategy: two-pass vertex search with no upper window limit.
  ///
  ///   Pass 1 – scan the entire remaining shape (from searchFrom to end) and
  ///            find the global minimum haversine distance to the stop.
  ///   Pass 2 – return the arc-length of the FIRST vertex whose distance is
  ///            ≤ [_kEarliestFactor] × that minimum.
  ///
  /// "No upper limit" ensures distant terminus stops (e.g. C5: only 2 stops,
  /// shape 30 km) are never missed.
  /// "First sufficiently-close vertex" ensures circular routes (e.g. C1) snap
  /// to the correct earlier pass instead of a geometrically closer return leg.
  static const double _kEarliestFactor = 3.0;

  void _precomputeShapeIndices(List<TripModel> trips) {
    for (final trip in trips) {
      if (trip.shapeArcLengthsForStops != null) continue;
      if (trip.shapeId == null || trip.shapeId!.isEmpty) continue;
      if (trip.stopTimes == null || trip.stopTimes!.isEmpty) continue;

      final shapePath = _shapesCache[trip.gtfsFileId]?[trip.shapeId!];
      if (shapePath == null || shapePath.isEmpty) continue;

      _shapeCumDistCache.putIfAbsent(trip.gtfsFileId, () => {});
      final cumDist = _shapeCumDistCache[trip.gtfsFileId]!.putIfAbsent(
        trip.shapeId!,
        () => InterpolationHelper.buildCumulativeDistances(shapePath),
      );

      final arcLengths = <double>[];
      int searchFromIdx = 0;

      for (final st in trip.stopTimes!) {
        final stop = st.stop;
        if (stop == null) {
          arcLengths.add(cumDist[searchFromIdx]);
          continue;
        }

        // Pass 1: find global minimum distance from searchFromIdx to end
        double minDist = double.infinity;
        for (int i = searchFromIdx; i < shapePath.length; i++) {
          final d = InterpolationHelper.haversineMeters(
            stop.stopLat, stop.stopLon,
            shapePath[i].latitude, shapePath[i].longitude,
          );
          if (d < minDist) minDist = d;
        }

        // Pass 2: take the FIRST vertex within kEarliestFactor × minDist.
        // This prefers an earlier match over a marginally closer later one,
        // which prevents circular routes from snapping to the return leg.
        final threshold = minDist * _kEarliestFactor;
        int bestIdx = searchFromIdx;
        for (int i = searchFromIdx; i < shapePath.length; i++) {
          final d = InterpolationHelper.haversineMeters(
            stop.stopLat, stop.stopLon,
            shapePath[i].latitude, shapePath[i].longitude,
          );
          if (d <= threshold) {
            bestIdx = i;
            break;
          }
        }

        arcLengths.add(cumDist[bestIdx]);
        searchFromIdx = bestIdx; // monotonically forward for next stop
      }

      trip.shapeArcLengthsForStops = arcLengths;
    }
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
      // Load routes for shape-to-route mapping
      if (!_routesCache.containsKey(file.id)) {
        _loadRoutesForFile(file.id);
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

    final shapes = await GtfsRepository.getAllShapesByGtfsFile(gtfsFileId);
    final grouped = GtfsRepository.groupShapes(shapes);

    final latLngMap = <String, List<LatLng>>{};
    for (final entry in grouped.entries) {
      final pts =
          entry.value.map((s) => LatLng(s.shapePtLat, s.shapePtLon)).toList();
      latLngMap[entry.key] = pts;
    }

    if (mounted) {
      setState(() {
        _shapesCache[gtfsFileId] = latLngMap;
      });
    }
  }

  Future<void> _loadRoutesForFile(int gtfsFileId) async {
    _routesCache[gtfsFileId] = [];

    final routes = await GtfsRepository.getRoutes(gtfsFileId);

    if (mounted) {
      setState(() {
        _routesCache[gtfsFileId] = routes;
      });
      
      // Cargar los shape_ids para cada ruta y actualizar el caché
      _loadShapeToRouteMappings(gtfsFileId, routes);
    }
  }

  Future<void> _loadShapeToRouteMappings(int gtfsFileId, List<RouteModel> routes) async {
    for (final route in routes) {
      final shapeIds = await GtfsRepository.getShapeIdsByRoute(route.id);
      for (final shapeId in shapeIds) {
        _shapeToRouteCache[shapeId] = route;
      }
    }
    // Forzar actualización del mapa después de cargar los mapeos
    if (mounted) {
      setState(() {});
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

  // ---------------------------------------------------------------------------
  // Corridor map helpers
  // ---------------------------------------------------------------------------

  /// Returns a color reflecting the headway: green (frequent) → red (infrequent).
  Color _headwayColor(double? minutes) {
    if (minutes == null) return const Color(0xFF607D8B); // grey – loading/unknown
    if (minutes < 5) return const Color(0xFF00E676);    // bright green
    if (minutes < 10) return const Color(0xFFB2FF59);   // lime
    if (minutes < 20) return const Color(0xFFFFD740);   // amber
    if (minutes < 40) return const Color(0xFFFF6D00);   // orange
    return const Color(0xFFFF1744);                     // red – very infrequent
  }

  /// Unique cache key for a corridor.
  String _corKey(CorredorDetectado cor) => cor.stopIds.join(',');

  /// Fires an async headway analysis for [cor] if not already running/cached.
  void _ensureCorridorHeadway(CorredorDetectado cor) {
    final key = _corKey(cor);
    if (_corridorHeadwayLabels.containsKey(key) ||
        _corridorAnalysisPending.contains(key)) return;

    _corridorAnalysisPending.add(key);

    () async {
      try {
        final services = await ref.read(activeServicesProvider.future);
        final fileIds = ref
            .read(gtfsFilesProvider)
            .valueOrNull
            ?.map((f) => f.id)
            .toList() ?? [];
        final serviceIds = services.map((s) => s.serviceId).toList();

        final analysis = await GtfsRepository.analyzeCorredore(
          stopIds: cor.stopIds,
          displayName: cor.displayName,
          serviceIds: serviceIds,
          gtfsFileIds: fileIds,
        );

        final h = analysis.globalAvgHeadwayMinutes;
        final label = h == null
            ? '—'
            : h < 1
                ? '<1 min'
                : '${h.round()} min';

        if (mounted) {
          setState(() {
            _corridorHeadwayLabels[key] = label;
            _corridorHeadwayMinutes[key] = h;
            _corridorAnalysisPending.remove(key);
          });
        }
      } catch (_) {
        _corridorAnalysisPending.remove(key);
      }
    }();
  }

  /// Extracts a slice of [shapePoints] between the closest points to
  /// [first] and [last] stops. Returns null if the shape doesn't fit.
  List<LatLng>? _sliceShapeForStops(
    List<LatLng> shapePoints,
    LatLng first,
    LatLng last,
  ) {
    if (shapePoints.length < 2) return null;

    // Find index of shape point closest to first stop.
    int iStart = 0;
    double bestStart = double.infinity;
    for (int i = 0; i < shapePoints.length; i++) {
      final d = _dist2(shapePoints[i], first);
      if (d < bestStart) {
        bestStart = d;
        iStart = i;
      }
    }

    // Find index of shape point closest to last stop, searching FORWARD
    // from iStart to keep directionality.
    int iEnd = iStart;
    double bestEnd = double.infinity;
    for (int i = iStart; i < shapePoints.length; i++) {
      final d = _dist2(shapePoints[i], last);
      if (d < bestEnd) {
        bestEnd = d;
        iEnd = i;
      }
    }

    if (iEnd <= iStart) return null;
    return shapePoints.sublist(iStart, iEnd + 1);
  }

  /// Squared lat/lon distance (no need for real geodesics at this scale).
  double _dist2(LatLng a, LatLng b) {
    final dlat = a.latitude - b.latitude;
    final dlon = a.longitude - b.longitude;
    return dlat * dlat + dlon * dlon;
  }

  /// Returns shape points for [cor] following the actual route geometry,
  /// or falls back to straight stop-to-stop line.
  List<LatLng> _corridorShapePoints(CorredorDetectado cor) {
    final fallback =
        cor.stops.map((s) => LatLng(s.stopLat, s.stopLon)).toList();
    if (cor.routes.isEmpty || cor.stops.length < 2) return fallback;

    final route = cor.routes.first;
    final fileShapes = _shapesCache[route.gtfsFileId];
    if (fileShapes == null || fileShapes.isEmpty) return fallback;

    final firstPt = LatLng(cor.stops.first.stopLat, cor.stops.first.stopLon);
    final lastPt = LatLng(cor.stops.last.stopLat, cor.stops.last.stopLon);

    // Find shape IDs that belong to this route.
    final candidateShapeIds = _shapeToRouteCache.entries
        .where((e) => e.value.id == route.id)
        .map((e) => e.key)
        .toList();

    List<LatLng>? best;
    double bestLen = double.infinity;

    for (final shapeId in candidateShapeIds) {
      final pts = fileShapes[shapeId];
      if (pts == null || pts.length < 2) continue;
      final sliced = _sliceShapeForStops(pts, firstPt, lastPt);
      if (sliced != null && sliced.length < bestLen) {
        bestLen = sliced.length.toDouble();
        best = sliced;
      }
    }

    return best ?? fallback;
  }

  /// Builds the corridor overlay layers (polylines + headway labels).
  List<Widget> _buildCorridorLayers(WidgetRef ref) {
    final visible = ref.watch(corredorMapVisibleProvider);
    if (!visible) return const [];

    final corridors =
        ref.watch(detectedCorridorsProvider).valueOrNull ?? [];
    if (corridors.isEmpty) return const [];

    final polylines = <Polyline>[];
    final markers = <Marker>[];

    for (var i = 0; i < corridors.length; i++) {
      final cor = corridors[i];

      // Kick off headway analysis if not yet available
      _ensureCorridorHeadway(cor);

      final color = _headwayColor(_corridorHeadwayMinutes[_corKey(cor)]);

      final points = _corridorShapePoints(cor);
      if (points.length < 2) continue;

      // Main corridor polyline
      polylines.add(Polyline(
        points: points,
        strokeWidth: 5,
        color: color.withOpacity(0.75),
        borderColor: Colors.black.withOpacity(0.35),
        borderStrokeWidth: 1.5,
      ));

      // Headway label at the middle point of the shape
      final midIdx = points.length ~/ 2;
      final midPoint = points[midIdx];
      final headway = _corridorHeadwayLabels[_corKey(cor)];
      final label = headway ?? '…';

      markers.add(Marker(
        point: midPoint,
        width: 80,
        height: 26,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.90),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ));
    }

    return [
      PolylineLayer(polylines: polylines),
      MarkerLayer(markers: markers),
    ];
  }

  List<Polyline> _buildPolylines(
    List<GtfsFileModel> files,
    Map<int, bool> fileVis,
    Map<int, bool> shapeVis,
    TripModel? selectedTrip,
    Map<int, bool> agencyVis, {
    String? excludeShapeId,
  }) {
    final polylines = <Polyline>[];

    // Si hay un vehículo seleccionado, solo mostrar su shape
    if (selectedTrip != null && selectedTrip.shapeId != null && selectedTrip.shapeId!.isNotEmpty) {
      final shapes = _shapesCache[selectedTrip.gtfsFileId];
      if (shapes != null) {
        final shapePoints = shapes[selectedTrip.shapeId!];
        if (shapePoints != null && shapePoints.isNotEmpty) {
          final route = selectedTrip.route;
          final routeColor = route != null ? hexToColor(route.routeColor) : AppTheme.primary;
          
          // Add a dark border for better contrast
          polylines.add(
            Polyline(
              points: shapePoints,
              color: Colors.black.withOpacity(0.6),
              strokeWidth: 6.5,
            ),
          );
          
          // Main line with route color
          polylines.add(
            Polyline(
              points: shapePoints,
              color: routeColor,
              strokeWidth: 4.5,
            ),
          );
        }
      }
      return polylines;
    }

    // Contar cuántas rutas están visibles
    final visibleRoutesCount = shapeVis.isEmpty 
        ? -1  // -1 indica "todas por defecto"
        : shapeVis.values.where((v) => v).length;
    
    // Si hay más de una ruta visible, usar color genérico
    final useGenericColor = visibleRoutesCount != 1;

    // Si no hay vehículo seleccionado, mostrar shapes según visibilidad
    for (final file in files) {
      // Verificar si el archivo GTFS está visible (por defecto true)
      final isFileVisible = fileVis[file.id] ?? true;
      if (!isFileVisible) continue;
      
      final shapes = _shapesCache[file.id];
      if (shapes == null) continue;

      // Obtener rutas del archivo
      final routes = _routesCache[file.id];
      final routesLoaded = routes != null && routes.isNotEmpty;

      for (final entry in shapes.entries) {
        if (entry.value.isEmpty) continue;
        
        final shapeId = entry.key;

        // Skip the shape currently being edited (ShapeEditorLayer renders it)
        if (excludeShapeId != null && shapeId == excludeShapeId) continue;
        
        // Buscar la ruta que usa este shape_id
        final route = routesLoaded ? _findRouteForShapeId(routes, shapeId) : null;
        
        // Determinar si debe mostrarse este shape
        bool shouldShow = false;
        Color routeColor = AppTheme.primary;
        
        if (route != null) {
          // Verificar visibilidad de la agencia
          final agencyDbId = route.agencyDbId;
          if (agencyDbId != null && agencyVis[agencyDbId] == false) continue;

          // Si shapeVis está vacío, mostrar todas las rutas por defecto
          // Si shapeVis tiene valores, solo mostrar las marcadas como true
          shouldShow = shapeVis.isEmpty || (shapeVis[route.id] ?? false);
          
          // Usar color específico solo si hay exactamente una ruta visible
          routeColor = useGenericColor 
              ? AppTheme.primary 
              : hexToColor(route.routeColor);
        } else if (shapeVis.isEmpty) {
          // Si no encontramos la ruta y no hay filtros, mostrar con color por defecto
          // Esto incluye el caso donde las rutas aún no se han cargado
          shouldShow = true;
        }
        
        if (shouldShow) {
          _addPolyline(polylines, entry.value, routeColor);
        }
      }
    }

    return polylines;
  }

  void _addPolyline(List<Polyline> polylines, List<LatLng> points, Color color) {
    // Add a dark border for better contrast
    polylines.add(
      Polyline(
        points: points,
        color: Colors.black.withOpacity(0.6),
        strokeWidth: 6.5,
      ),
    );
    
    // Main line with color
    polylines.add(
      Polyline(
        points: points,
        color: color,
        strokeWidth: 4.5,
      ),
    );
  }

  RouteModel? _findRouteForShapeId(List<RouteModel> routes, String shapeId) {
    // Buscar en el caché primero
    final cacheKey = shapeId;
    if (_shapeToRouteCache.containsKey(cacheKey)) {
      return _shapeToRouteCache[cacheKey];
    }

    // Si no está en caché, necesitamos buscarlo en los trips
    // Por ahora, retornamos null y la lógica de carga lo manejará
    return null;
  }

  List<Marker> _buildStopMarkers(
    List<GtfsFileModel> files,
    Map<int, bool> stopsVis,
    StopModel? selectedStop,
    Map<int, bool> routeStopsVis,
    Map<int, bool> agencyVis, {
    StopModel? secondSelectedStop,
  }) {
    final markers = <Marker>[];

    // Build a flat route lookup map from cache
    final routeById = <int, RouteModel>{};
    for (final routes in _routesCache.values) {
      for (final r in routes) {
        routeById[r.id] = r;
      }
    }

    // Si hay rutas con paradas visibles, cargar solo esas paradas
    // Filtrar las rutas cuya agencia esté oculta
    final visibleRoutes = routeStopsVis.entries
        .where((e) => e.value)
        .where((e) {
          final route = routeById[e.key];
          if (route == null) return true;
          final agencyDbId = route.agencyDbId;
          if (agencyDbId != null && agencyVis.containsKey(agencyDbId)) {
            return agencyVis[agencyDbId] != false;
          }
          return true;
        })
        .map((e) => e.key)
        .toList();
    
    if (visibleRoutes.isNotEmpty) {
      // Mostrar paradas de rutas específicas
      _buildStopMarkersForRoutes(visibleRoutes, selectedStop, markers,
          secondSelectedStop: secondSelectedStop);
    } else {
      // Mostrar paradas por archivo (comportamiento original)
      for (final file in files) {
        // Verificar visibilidad del archivo GTFS
        final fileVisibility = ref.read(gtfsFileVisibilityProvider);
        final isFileVisible = fileVisibility[file.id] ?? true;
        if (!isFileVisible) continue;
        
        if (stopsVis[file.id] != true) continue;
        final stops = _stopsCache[file.id] ?? [];

        for (final stop in stops) {
          _addStopMarker(stop, selectedStop, markers,
              secondSelectedStop: secondSelectedStop);
        }
      }
    }

    return markers;
  }

  void _buildStopMarkersForRoutes(
    List<int> routeIds,
    StopModel? selectedStop,
    List<Marker> markers, {
    StopModel? secondSelectedStop,
  }) {
    final uniqueStops = <int, StopModel>{};
    
    // Cargar paradas de las rutas visibles
    for (final routeId in routeIds) {
      final stops = _routeStopsCache[routeId];
      if (stops != null) {
        for (final stop in stops) {
          if (!uniqueStops.containsKey(stop.id)) {
            uniqueStops[stop.id] = stop;
          }
        }
      } else {
        // Si no está en caché, cargar las paradas de esta ruta
        _loadStopsForRoute(routeId);
      }
    }
    
    // Añadir marcadores para las paradas únicas
    for (final stop in uniqueStops.values) {
      _addStopMarker(stop, selectedStop, markers,
          secondSelectedStop: secondSelectedStop);
    }
  }

  Future<void> _loadStopsForRoute(int routeId) async {
    final stops = await GtfsRepository.getStopsByRoute(routeId);
    if (mounted) {
      setState(() {
        _routeStopsCache[routeId] = stops;
      });
    }
  }

  void _addStopMarker(
    StopModel stop,
    StopModel? selectedStop,
    List<Marker> markers, {
    StopModel? secondSelectedStop,
  }) {
    final isSelected = selectedStop?.id == stop.id;
    final isSecondSelected = secondSelectedStop?.id == stop.id;
    final highlight = isSelected || isSecondSelected;
    final isMerged = stop.isMerged;
    final markerColor = isSecondSelected
        ? Colors.cyan
        : isSelected
            ? Colors.orange
            : isMerged
                ? const Color(0xFFAB47BC) // purple for merged stops
                : Colors.white;
    final borderColor = isSecondSelected
        ? Colors.cyan.shade700
        : isSelected
            ? Colors.orange.shade800
            : isMerged
                ? Colors.purple.shade700
                : AppTheme.primary;
    markers.add(
      Marker(
        point: LatLng(stop.stopLat, stop.stopLon),
        width: highlight ? 24 : 16,
        height: highlight ? 24 : 16,
        child: GestureDetector(
          onTap: () {
            // If pattern editor is active, add stop to trayecto
            final patternEditorState = ref.read(patternEditorProvider);
            if (patternEditorState != null) {
              ref.read(patternEditorProvider.notifier).addStop(stop);
              return;
            }
            final isModifier =
                HardwareKeyboard.instance.isShiftPressed;
            if (isModifier) {
              // Don't allow selecting the same stop twice
              if (selectedStop?.id == stop.id) return;
              ref.read(secondSelectedStopProvider.notifier).state = stop;
            } else {
              ref.read(selectedStopProvider.notifier).state = stop;
              ref.read(selectedTripProvider.notifier).state = null;
              // Clear second selection when clicking without modifier
              ref.read(secondSelectedStopProvider.notifier).state = null;
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor,
                width: highlight ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isSecondSelected
                          ? Colors.cyan
                          : isSelected
                              ? Colors.orange
                              : isMerged
                                  ? Colors.purple
                                  : AppTheme.primary)
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

  void _handleMapTap(LatLng pos, DateTime simDateTime) {
    // Pick-stop-location mode: deliver the location and exit
    final pickCallback = ref.read(pickStopLocationProvider);
    if (pickCallback != null) {
      pickCallback(pos);
      return;
    }

    // In shape editor modes, map tap adds/removes points
    final editState = ref.read(shapeEditorProvider);
    if (editState != null) {
      switch (editState.mode) {
        case ShapeEditMode.append:
          ref.read(shapeEditorProvider.notifier).appendPoint(pos);
          return;
        case ShapeEditMode.prepend:
          ref.read(shapeEditorProvider.notifier).prependPoint(pos);
          return;
        default:
          break;
      }
    }

    const threshold = 50.0; // metres

    // Check if click is on a stop - deselect if clicking far away
    final selectedStop = ref.read(selectedStopProvider);
    if (selectedStop != null) {
      final dist = InterpolationHelper.haversineMeters(pos.latitude,
          pos.longitude, selectedStop.stopLat, selectedStop.stopLon);
      if (dist > threshold) {
        ref.read(selectedStopProvider.notifier).state = null;
        ref.read(secondSelectedStopProvider.notifier).state = null;
        ref.read(selectedTripProvider.notifier).state = null;
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
        -0.8,
        0,
        0,
        0,
        255,
        0,
        -0.8,
        0,
        0,
        255,
        0,
        0,
        -0.8,
        0,
        255,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: tileWidget,
    );
  }
}

// ---------------------------------------------------------------------------
// Map help hint (Shift multi-select tip)
// ---------------------------------------------------------------------------

class _MapHint extends StatelessWidget {
  const _MapHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC1E2129),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.keyboard, color: Colors.white38, size: 13),
          const SizedBox(width: 6),
          RichText(
            text: const TextSpan(
              style: TextStyle(color: Colors.white38, fontSize: 10),
              children: [
                TextSpan(
                  text: 'Shift',
                  style: TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                TextSpan(text: ' + clic para seleccionar una 2ª parada'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit toolbar button
// ---------------------------------------------------------------------------

class _ToolbarBtn extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool enabled;
  final bool loading;
  final Color color;
  final VoidCallback onTap;

  const _ToolbarBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (loading)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: color),
                )
              else if (icon != null)
                Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode toggle button (highlighted when active)
// ---------------------------------------------------------------------------

class _ModeBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback? onTap;

  const _ModeBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.25) : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? color : color.withOpacity(0.35),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: active ? color : color.withOpacity(0.6)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? color : color.withOpacity(0.6),
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vertical divider for toolbar
// ---------------------------------------------------------------------------

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      color: Colors.white.withOpacity(0.15),
    );
  }
}
