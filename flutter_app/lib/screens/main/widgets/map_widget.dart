import 'package:flutter/material.dart';
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
import 'shape_editor_layer.dart';

class MapWidget extends ConsumerStatefulWidget {
  const MapWidget({super.key});

  @override
  ConsumerState<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends ConsumerState<MapWidget> {
  late MapController _mapController;
  // Cache for shapes: gtfsFileId -> shape_id -> List<LatLng>
  final Map<int, Map<String, List<LatLng>>> _shapesCache = {};
  int _lastShapeCacheVersion = 0;
  // Cache for stops per file
  final Map<int, List<StopModel>> _stopsCache = {};
  // Cache para mapear shape_id -> route (para obtener colores)
  final Map<String, RouteModel> _shapeToRouteCache = {};
  // Cache de rutas por archivo
  final Map<int, List<RouteModel>> _routesCache = {};
  // Cache de paradas por ruta: routeId -> List<StopModel>
  final Map<int, List<StopModel>> _routeStopsCache = {};

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
    final agencyVis = ref.watch(agencyVisibilityProvider);

    // Solo observar el dateTime para vehículos
    final simDateTime =
        ref.watch(simulationTimeProvider.select((state) => state.dateTime));
    final activeTripsAsync = ref.watch(activeTripsProvider);
    final simVis = ref.watch(routeSimulationVisibilityProvider);
    final selectedTrip = ref.watch(selectedTripProvider);

    // Watch shape cache version — when it changes, clear the local cache so
    // newly generated shapes are reloaded from the database.
    final shapeCacheVersion = ref.watch(shapeCacheVersionProvider);
    if (_lastShapeCacheVersion != shapeCacheVersion) {
      _lastShapeCacheVersion = shapeCacheVersion;
      _shapesCache.clear();
      _shapeToRouteCache.clear();
    }

    final editState = ref.watch(shapeEditorProvider);

    // Load shapes and stops reactively
    _preloadLayerData(gtfsFiles, shapeVis, stopsVis);

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(40.4168, -3.7038), // Madrid
        initialZoom: 13,
        onTap: (_, pos) => _handleMapTap(pos, simDateTime),
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

        // Stop markers
        MarkerLayer(
          markers: _buildStopMarkers(gtfsFiles, stopsVis, selectedStop,
              ref.watch(routeStopsVisibilityProvider), agencyVis),
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

    if (editState == null) return map;

    // Wrap map in a Stack to show the edit toolbar
    return Stack(children: [
      map,
      Positioned(
        top: 12,
        left: 0,
        right: 0,
        child: Center(child: _buildEditToolbar(context, editState)),
      ),
    ]);
  }

  Widget _buildEditToolbar(BuildContext context, ShapeEditState editState) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xF01E2129),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.edit_road, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Text(
            'Editando shape${editState.routeName.isNotEmpty ? ': ${editState.routeName}' : ''}',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            '(${editState.points.length} pts)',
            style:
                TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
          ),
          const SizedBox(width: 12),
          // Undo
          _ToolbarBtn(
            icon: Icons.undo,
            label: 'Deshacer',
            enabled: editState.canUndo && !editState.isSaving,
            color: Colors.white70,
            onTap: () => ref.read(shapeEditorProvider.notifier).undo(),
          ),
          const SizedBox(width: 6),
          // Cancel
          _ToolbarBtn(
            icon: Icons.close,
            label: 'Cancelar',
            enabled: !editState.isSaving,
            color: Colors.red[300]!,
            onTap: () => ref.read(shapeEditorProvider.notifier).cancel(),
          ),
          const SizedBox(width: 6),
          // Save
          _ToolbarBtn(
            icon: editState.isSaving ? null : Icons.check,
            label: editState.isSaving ? 'Guardando…' : 'Guardar',
            enabled: !editState.isSaving,
            color: Colors.green[400]!,
            loading: editState.isSaving,
            onTap: () async {
              final ok =
                  await ref.read(shapeEditorProvider.notifier).save();
              if (!mounted) return;
              // Bust map shape cache so the updated shape reloads
              ref.read(shapeCacheVersionProvider.notifier).state++;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                backgroundColor:
                    ok ? const Color(0xFF1B6B3A) : Colors.red[800],
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

    final timePrev =
        prev.getArrivalTimeInDate(simDateTime).millisecondsSinceEpoch;
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

    // Try to use shape if available with precomputed indices
    final useShapeInterpolation = ref.read(useShapeInterpolationProvider);

    if (useShapeInterpolation &&
        trip.shapeId != null &&
        trip.shapeId!.isNotEmpty) {
      final shapePath = _shapesCache[trip.gtfsFileId]?[trip.shapeId!];
      final shapeIndices = trip.shapeIndicesForStops;

      if (shapePath != null &&
          shapePath.isNotEmpty &&
          shapeIndices != null &&
          shapeIndices.length > prevIndex + 1) {
        final result = InterpolationHelper.interpolateAlongShape(
          shapePath,
          prevStop.stopLat,
          prevStop.stopLon,
          nextStop.stopLat,
          nextStop.stopLon,
          fraction,
          prevShapeIndex: shapeIndices[prevIndex],
          nextShapeIndex: shapeIndices[prevIndex + 1],
        );

        if (result != null) {
          return LatLng(result.$1, result.$2);
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

  /// Precompute shape indices for trips that have shapes but no indices yet
  void _precomputeShapeIndices(List<TripModel> trips) {
    for (final trip in trips) {
      // Skip if already computed or no shape available
      if (trip.shapeIndicesForStops != null) continue;
      if (trip.shapeId == null || trip.shapeId!.isEmpty) continue;
      if (trip.stopTimes == null || trip.stopTimes!.isEmpty) continue;

      final shapePath = _shapesCache[trip.gtfsFileId]?[trip.shapeId!];
      if (shapePath == null || shapePath.isEmpty) continue;

      // Extract stop coordinates
      final stopCoords = <(double, double)>[];
      for (final st in trip.stopTimes!) {
        final stop = st.stop;
        if (stop != null) {
          stopCoords.add((stop.stopLat, stop.stopLon));
        }
      }

      if (stopCoords.isEmpty) continue;

      // Compute and store indices
      trip.shapeIndicesForStops =
          InterpolationHelper.computeShapeIndicesForStops(
        shapePath,
        stopCoords,
      );
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
    Map<int, bool> agencyVis,
  ) {
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
      _buildStopMarkersForRoutes(visibleRoutes, selectedStop, markers);
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
          _addStopMarker(stop, selectedStop, markers);
        }
      }
    }

    return markers;
  }

  void _buildStopMarkersForRoutes(
    List<int> routeIds,
    StopModel? selectedStop,
    List<Marker> markers,
  ) {
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
      _addStopMarker(stop, selectedStop, markers);
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
    List<Marker> markers,
  ) {
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
                color:
                    isSelected ? Colors.orange.shade800 : AppTheme.primary,
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

  void _handleMapTap(LatLng pos, DateTime simDateTime) {
    const threshold = 50.0; // metres

    // Check if click is on a stop - deselect if clicking far away
    final selectedStop = ref.read(selectedStopProvider);
    if (selectedStop != null) {
      final dist = InterpolationHelper.haversineMeters(pos.latitude,
          pos.longitude, selectedStop.stopLat, selectedStop.stopLon);
      if (dist > threshold) {
        ref.read(selectedStopProvider.notifier).state = null;
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
