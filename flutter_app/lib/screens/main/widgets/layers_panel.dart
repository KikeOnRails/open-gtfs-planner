import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/shape_editor_provider.dart';
import '../../../providers/simulation_providers.dart';
import '../../../core/database/gtfs_repository.dart';
import 'create_gtfs_dialog.dart';
import 'create_route_dialog.dart';
import '../../../providers/route_editor_providers.dart';

class LayersPanel extends ConsumerStatefulWidget {
  const LayersPanel({super.key});

  @override
  ConsumerState<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends ConsumerState<LayersPanel> {
  @override
  Widget build(BuildContext context) {
    final gtfsFilesAsync = ref.watch(gtfsFilesProvider);
    final importTasks = ref.watch(importTasksProvider);
    final activeImports = importTasks.values
        .where((t) => !t.isComplete || t.error != null)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          right: BorderSide(color: Color(0xFF2E3340), width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildPanelHeader(context),
          // Show all active imports
          ...activeImports.map((task) => _buildImportProgress(task)),
          Expanded(
            child: gtfsFilesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (files) => files.isEmpty && activeImports.isEmpty
                  ? _buildEmptyLayers()
                  : _buildLayersList(files),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context) {
    final importTasks = ref.watch(importTasksProvider);
    final hasActiveImports = importTasks.values.any((t) => !t.isComplete);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E3340), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_outlined, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            'Capas GTFS',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          if (hasActiveImports)
            Container(
              margin: const EdgeInsets.only(right: 8),
              width: 14,
              height: 14,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
          Tooltip(
            message: 'Crear GTFS',
            child: InkWell(
              onTap: () => showCreateGtfsDialog(context, ref),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, color: AppTheme.primary, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportProgress(ImportTask task) {
    final isError = task.error != null;
    final color = isError ? Colors.red : AppTheme.primary;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!task.isComplete)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else if (isError)
                Icon(Icons.error_outline, color: color, size: 14)
              else
                Icon(Icons.check_circle_outline, color: color, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.filename,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isError)
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ref
                        .read(importTasksProvider.notifier)
                        .removeImport(task.id);
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isError ? 'Error: ${task.error}' : task.step,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 11),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          if (!isError) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyLayers() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.upload_file_outlined,
              color: AppTheme.onSurfaceVariant, size: 40),
          const SizedBox(height: 12),
          Text(
            'Sin archivos GTFS',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Importa, crea o descarga\nun archivo GTFS para empezar',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showCreateGtfsDialog(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Crear GTFS'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayersList(List<GtfsFileModel> files) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: files.length,
      itemBuilder: (_, i) => _GtfsFileLayer(gtfsFile: files[i]),
    );
  }

}

// ---------------------------------------------------------------------------
// Individual GTFS file layer widget
// ---------------------------------------------------------------------------

class _GtfsFileLayer extends ConsumerStatefulWidget {
  final GtfsFileModel gtfsFile;
  const _GtfsFileLayer({required this.gtfsFile});

  @override
  ConsumerState<_GtfsFileLayer> createState() => _GtfsFileLayerState();
}

class _GtfsFileLayerState extends ConsumerState<_GtfsFileLayer> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final fileVis = ref.watch(gtfsFileVisibilityProvider);
    final stopsVis = ref.watch(gtfsStopsVisibilityProvider);
    final agenciesAsync = ref.watch(agenciesProvider(widget.gtfsFile.id));

    final isVisible = fileVis[widget.gtfsFile.id] ?? true;
    final showStops = stopsVis[widget.gtfsFile.id] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File header
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppTheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                const Icon(Icons.folder_outlined,
                    size: 15, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.gtfsFile.filename,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Visibility toggle
                _SmallIconButton(
                  icon: isVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  active: isVisible,
                  tooltip: isVisible ? 'Ocultar GTFS' : 'Mostrar GTFS',
                  onTap: () {
                    ref
                        .read(gtfsFileVisibilityProvider.notifier)
                        .set(widget.gtfsFile.id, !isVisible);
                    // Si ocultamos el GTFS, también ocultar sus paradas
                    if (isVisible) {
                      ref
                          .read(gtfsStopsVisibilityProvider.notifier)
                          .set(widget.gtfsFile.id, false);
                    }
                  },
                ),
                const SizedBox(width: 4),
                // Stops toggle
                _SmallIconButton(
                  icon: Icons.place_outlined,
                  active: showStops,
                  tooltip: showStops ? 'Ocultar paradas' : 'Mostrar paradas',
                  onTap: () => ref
                      .read(gtfsStopsVisibilityProvider.notifier)
                      .set(widget.gtfsFile.id, !showStops),
                ),
                const SizedBox(width: 4),
                // Nueva ruta
                _SmallIconButton(
                  icon: Icons.add_road,
                  active: false,
                  tooltip: 'Nueva ruta',
                  onTap: () => showCreateRouteDialog(context, ref, widget.gtfsFile),
                  activeColor: AppTheme.primary,
                ),
                const SizedBox(width: 4),
                // Delete
                _SmallIconButton(
                  icon: Icons.delete_outline,
                  active: false,
                  tooltip: 'Eliminar',
                  onTap: () => _confirmDelete(context),
                  activeColor: Colors.red,
                ),
              ],
            ),
          ),
        ),

        if (_expanded) ...[
          agenciesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(left: 32, top: 4, bottom: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppTheme.primary,
              ),
            ),
            error: (e, _) => const SizedBox.shrink(),
            data: (agencies) => Column(
              children: agencies
                  .map((a) => _AgencyLayer(
                        agency: a,
                        gtfsFile: widget.gtfsFile,
                      ))
                  .toList(),
            ),
          ),
        ],

        const Divider(height: 1),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        title: const Text('Eliminar capa'),
        content: Text(
            '¿Eliminar "${widget.gtfsFile.filename}"? Se borrarán todos sus datos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref
          .read(gtfsFilesProvider.notifier)
          .deleteGtfsFile(widget.gtfsFile.id);
      ref.invalidate(activeServicesProvider);
      ref.invalidate(activeTripsProvider);
    }
  }
}

class _AgencyLayer extends ConsumerStatefulWidget {
  final AgencyModel agency;
  final GtfsFileModel gtfsFile;
  const _AgencyLayer({required this.agency, required this.gtfsFile});

  @override
  ConsumerState<_AgencyLayer> createState() => _AgencyLayerState();
}

class _AgencyLayerState extends ConsumerState<_AgencyLayer> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final routesAsync = ref.watch(routesProvider(widget.gtfsFile.id));
    final agencyVis = ref.watch(agencyVisibilityProvider);
    final isVisible = agencyVis[widget.agency.id] ?? true;

    return routesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (allRoutes) {
        final agencyRoutes =
            allRoutes.where((r) => r.agencyDbId == widget.agency.id).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 28, right: 12, top: 6, bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: AppTheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.business_outlined,
                        size: 13, color: AppTheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.agency.agencyName,
                        style: TextStyle(
                          fontSize: 11,
                          color: isVisible
                              ? AppTheme.onSurfaceVariant
                              : AppTheme.onSurfaceVariant.withOpacity(0.4),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${agencyRoutes.length} rutas',
                      style: TextStyle(
                        fontSize: 10,
                        color: isVisible
                            ? AppTheme.onSurfaceVariant
                            : AppTheme.onSurfaceVariant.withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Agency visibility toggle
                    _SmallIconButton(
                      icon: isVisible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      active: isVisible,
                      tooltip: isVisible
                          ? 'Ocultar agencia'
                          : 'Mostrar agencia',
                      onTap: () {
                        final notifier = ref.read(
                            agencyVisibilityProvider.notifier);
                        notifier.set(widget.agency.id, !isVisible);
                        // Cascade: when hiding, also clear route-level
                        // shape/sim/stops visibility for this agency's routes
                        if (isVisible) {
                          final shapeNotifier = ref.read(
                              routeShapeVisibilityProvider.notifier);
                          final simNotifier = ref.read(
                              routeSimulationVisibilityProvider.notifier);
                          final stopsNotifier = ref.read(
                              routeStopsVisibilityProvider.notifier);
                          for (final r in agencyRoutes) {
                            shapeNotifier.remove(r.id);
                            simNotifier.set(r.id, false);
                            stopsNotifier.set(r.id, false);
                          }
                          // Also invalidate active trips
                          ref.invalidate(activeTripsProvider);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              ...agencyRoutes.map(
                (r) => _RouteLayer(routeId: r.id, gtfsFile: widget.gtfsFile),
              ),
          ],
        );
      },
    );
  }
}

class _RouteLayer extends ConsumerStatefulWidget {
  final int routeId;
  final GtfsFileModel gtfsFile;
  const _RouteLayer({required this.routeId, required this.gtfsFile});

  @override
  ConsumerState<_RouteLayer> createState() => _RouteLayerState();
}

class _RouteLayerState extends ConsumerState<_RouteLayer> {
  // null = not yet loaded, true/false = has/no shapes
  bool? _hasShapes;
  bool _generating = false;
  List<RoutePatternModel> _patterns = [];
  int _lastPatternCacheVersion = -1;

  @override
  void initState() {
    super.initState();
    _checkShapes();
    _loadPatterns();
  }

  Future<void> _loadPatterns() async {
    final patterns = await GtfsRepository.getRoutePatterns(widget.routeId);
    if (mounted) setState(() => _patterns = patterns);
  }

  Future<void> _checkShapes() async {
    final has = await GtfsRepository.routeHasShapes(widget.routeId);
    if (mounted) setState(() => _hasShapes = has);
  }

  Future<void> _generateShapes(BuildContext context) async {
    setState(() => _generating = true);

    // Get the current route from the provider
    final routesAsync = ref.read(routesProvider(widget.gtfsFile.id));
    final route = routesAsync.valueOrNull?.firstWhere(
      (r) => r.id == widget.routeId,
      orElse: () => throw Exception('Route not found'),
    );
    
    if (route == null) return;

    // Show a persistent snackbar with progress info
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: const Color(0xFF1E2129),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(minutes: 2),
          content: Row(children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppTheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Generando shapes para ${route.displayName} siguiendo el viario…',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ]),
        ),
      );

    try {
      final count = await GtfsRepository.generateShapesFromStops(
          widget.gtfsFile.id, route.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // Invalidate the map shape cache so it reloads from DB
      ref.read(routeShapeVisibilityProvider.notifier).remove(route.id);
      ref.invalidate(activeTripsProvider);
      // Signal MapWidget to clear its local shapes cache
      ref.read(shapeCacheVersionProvider.notifier).state++;
      setState(() {
        _hasShapes = count > 0;
        _generating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: count > 0 ? AppTheme.primaryDark : Colors.orange[800],
          content: Row(children: [
            Icon(count > 0 ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count > 0
                    ? '$count trayecto${count != 1 ? 's' : ''} generado${count != 1 ? 's' : ''} siguiendo el viario'
                    : 'No se encontraron paradas para generar shapes',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ]),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: Colors.red[800],
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Error al generar shapes: $e',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ]),
        ),
      );
    }
  }

  Future<void> _startEditingShape() async {
    // Get the current route from the provider
    final routesAsync = ref.read(routesProvider(widget.gtfsFile.id));
    final route = routesAsync.valueOrNull?.firstWhere(
      (r) => r.id == widget.routeId,
      orElse: () => throw Exception('Route not found'),
    );
    
    if (route == null) return;

    final shapeIds =
        await GtfsRepository.getShapeIdsByRoute(route.id);
    if (shapeIds.isEmpty) return;

    final shapeId = shapeIds.first;
    final shapes = await GtfsRepository.getShapesByRouteShapeId(
        widget.gtfsFile.id, shapeId);
    if (shapes.isEmpty) return;

    final points =
        shapes.map((s) => LatLng(s.shapePtLat, s.shapePtLon)).toList();

    if (!mounted) return;
    ref.read(shapeEditorProvider.notifier).startEditing(
          gtfsFileId: widget.gtfsFile.id,
          shapeId: shapeId,
          points: points,
          routeColor: hexToColor(route.routeColor),
          routeName: route.displayName,
        );

    // Center map on the shape
    final mapController = ref.read(mapControllerProvider);
    final avgLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final avgLon =
        points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    mapController.move(LatLng(avgLat, avgLon), mapController.camera.zoom);
  }

  void _showContextMenu(BuildContext context, Offset globalPosition) async {
    final hasShapes = _hasShapes ?? true;
    final items = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'center',
        child: const Row(children: [
          Icon(Icons.center_focus_strong_outlined, size: 14),
          SizedBox(width: 8),
          Text('Centrar mapa', style: TextStyle(fontSize: 12)),
        ]),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'change_color',
        child: const Row(children: [
          Icon(Icons.color_lens, size: 14, color: Colors.blue),
          SizedBox(width: 8),
          Text('Cambiar color', style: TextStyle(fontSize: 12)),
        ]),
      ),
      if (!hasShapes) ...[        
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'generate_shapes',
          child: Row(children: [
            _generating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary))
                : const Icon(Icons.route_outlined,
                    size: 14, color: AppTheme.primary),
            const SizedBox(width: 8),
            const Text('Generar shapes desde paradas',
                style: TextStyle(fontSize: 12, color: AppTheme.primary)),
          ]),
        ),
      ],
      if (hasShapes) ...[        
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'edit_shape',
          child: const Row(children: [
            Icon(Icons.edit_road, size: 14, color: Colors.orange),
            SizedBox(width: 8),
            Text('Editar shape',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ]),
        ),
      ],
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'delete_route',
        child: const Row(children: [
          Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
          SizedBox(width: 8),
          Text('Eliminar ruta', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
        ]),
      ),
    ];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      color: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: items,
    );

    if (!mounted) return;
    if (result == 'center') {
      await _centerMapOnRoute();
    } else if (result == 'change_color') {
      await _changeRouteColor(context);
    } else if (result == 'generate_shapes') {
      await _generateShapes(context);
    } else if (result == 'edit_shape') {
      await _startEditingShape();
    } else if (result == 'delete_route') {
      await _confirmDeleteRoute(context);
    }
  }

  Future<void> _confirmDeleteRoute(BuildContext context) async {
    final routesAsync = ref.read(routesProvider(widget.gtfsFile.id));
    final route = routesAsync.valueOrNull?.firstWhere(
      (r) => r.id == widget.routeId,
      orElse: () => throw Exception('Route not found'),
    );
    if (route == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2129),
        title: const Text('Eliminar ruta', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          '¿Eliminar la ruta "${route.displayName}" y todos sus trayectos, expediciones y shapes?\n\nEsta acción no se puede deshacer.',
          style: const TextStyle(color: Color(0xFF8B9299), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await GtfsRepository.deleteRoute(route.id);
    ref.invalidate(routesProvider(widget.gtfsFile.id));
    ref.read(shapeCacheVersionProvider.notifier).state++;
    ref.invalidate(activeTripsProvider);
  }

  Future<void> _changeRouteColor(BuildContext context) async {
    // Get the current route from the provider
    final routesAsync = ref.read(routesProvider(widget.gtfsFile.id));
    final route = routesAsync.valueOrNull?.firstWhere(
      (r) => r.id == widget.routeId,
      orElse: () => throw Exception('Route not found'),
    );
    
    if (route == null) return;

    Color currentColor = hexToColor(route.routeColor);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Cambiar color de ${route.displayName}'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: currentColor,
              onColorChanged: (color) {
                currentColor = color;
              },
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Guardar'),
              onPressed: () async {
                // Convert color to hex string without #
                final hexString = currentColor.toARGB32().toRadixString(16).substring(2).toUpperCase();
                await GtfsRepository.updateRouteColor(route.id, hexString);
                
                // Refresh the routes provider to update the UI
                ref.invalidate(routesProvider(widget.gtfsFile.id));
                
                // Force reload of active trips to get updated route colors
                ref.invalidate(activeTripsProvider);
                
                // Force map widget to reload shape caches to get updated colors
                ref.read(shapeCacheVersionProvider.notifier).state++;
                
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get the route from the provider
    final routesAsync = ref.watch(routesProvider(widget.gtfsFile.id));
    final route = routesAsync.valueOrNull?.firstWhere(
      (r) => r.id == widget.routeId,
      orElse: () => throw Exception('Route not found'),
    );

    if (route == null) {
      return const SizedBox.shrink(); // Route not found, don't render
    }

    final shapeVis = ref.watch(routeShapeVisibilityProvider);
    final simVis = ref.watch(routeSimulationVisibilityProvider);
    final stopsVis = ref.watch(routeStopsVisibilityProvider);

    final showShape = shapeVis[route.id] ?? false;
    final showSim = simVis[route.id] ?? false;
    final showStops = stopsVis[route.id] ?? false;
    final hasShapes = _hasShapes ?? true;

    final routeColor = hexToColor(route.routeColor);

    // Reload patterns when cache version changes
    final patternCacheVersion = ref.watch(patternCacheVersionProvider);
    if (patternCacheVersion != _lastPatternCacheVersion) {
      _lastPatternCacheVersion = patternCacheVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPatterns());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Route row
        GestureDetector(
          onSecondaryTapUp: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: Padding(
            padding:
                const EdgeInsets.only(left: 44, right: 12, top: 3, bottom: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: routeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => _centerMapOnRoute(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              route.displayName,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Indicator when route has no shapes
                          if (!hasShapes)
                            Tooltip(
                              message:
                                  'Sin shapes — click derecho para generar',
                              child: Icon(
                                Icons.warning_amber_rounded,
                                size: 11,
                                color: Colors.orange.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Shape visibility (disabled if no shapes)
                _SmallIconButton(
                  icon: Icons.route_outlined,
                  active: showShape,
                  tooltip: !hasShapes
                      ? 'Sin shapes (click derecho para generar)'
                      : showShape
                          ? 'Ocultar recorrido'
                          : 'Mostrar recorrido',
                  onTap: () async {
                    if (!hasShapes) return;
                    if (showShape) {
                      ref
                          .read(routeShapeVisibilityProvider.notifier)
                          .remove(route.id);
                    } else {
                      ref
                          .read(routeShapeVisibilityProvider.notifier)
                          .set(route.id, true);
                      await _centerMapOnRoute();
                    }
                  },
                ),
                const SizedBox(width: 2),
                // Stops visibility
                _SmallIconButton(
                  icon: Icons.location_on_outlined,
                  active: showStops,
                  tooltip: showStops ? 'Ocultar paradas' : 'Mostrar paradas',
                  onTap: () {
                    ref
                        .read(routeStopsVisibilityProvider.notifier)
                        .set(route.id, !showStops);
                  },
                ),
                const SizedBox(width: 2),
                // Simulation visibility
                _SmallIconButton(
                  icon: Icons.directions_bus_outlined,
                  active: showSim,
                  tooltip: showSim
                      ? 'Ocultar simulación'
                      : 'Activar simulación',
                  onTap: () {
                    ref
                        .read(routeSimulationVisibilityProvider.notifier)
                        .set(route.id, !showSim);
                    ref.invalidate(activeTripsProvider);
                  },
                ),
              ],
            ),
          ),
        ),

        // Trayectos sub-list
        ..._patterns.map((pattern) => _PatternRow(
              key: ValueKey(pattern.id),
              pattern: pattern,
              route: route,
              gtfsFile: widget.gtfsFile,
              onDeleted: _loadPatterns,
            )),

        // "Nuevo trayecto" button
        Padding(
          padding: const EdgeInsets.only(left: 60, right: 12, bottom: 2),
          child: InkWell(
            onTap: () {
              ref
                  .read(patternEditorProvider.notifier)
                  .start(route, widget.gtfsFile);
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.add, size: 11,
                      color: AppTheme.onSurfaceVariant.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Text(
                    'Nuevo trayecto',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _centerMapOnRoute() async {
    final mapController = ref.read(mapControllerProvider);

    // Get the route from the provider
    final routesAsync = ref.read(routesProvider(widget.gtfsFile.id));
    final route = routesAsync.valueOrNull?.firstWhere(
      (r) => r.id == widget.routeId,
      orElse: () => throw Exception('Route not found'),
    );
    
    if (route == null) return;

    // Get shapes for this route
    final shapes = await GtfsRepository.getShapesByRoute(
      widget.gtfsFile.id,
      route.id,
    );

    if (shapes.isEmpty) return;

    // Calculate bounds
    double minLat = shapes.first.shapePtLat;
    double maxLat = shapes.first.shapePtLat;
    double minLon = shapes.first.shapePtLon;
    double maxLon = shapes.first.shapePtLon;

    for (final shape in shapes) {
      if (shape.shapePtLat < minLat) minLat = shape.shapePtLat;
      if (shape.shapePtLat > maxLat) maxLat = shape.shapePtLat;
      if (shape.shapePtLon < minLon) minLon = shape.shapePtLon;
      if (shape.shapePtLon > maxLon) maxLon = shape.shapePtLon;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );

    mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }
}

class _PatternRow extends ConsumerWidget {
  final RoutePatternModel pattern;
  final RouteModel route;
  final GtfsFileModel gtfsFile;
  final VoidCallback onDeleted;

  const _PatternRow({
    super.key,
    required this.pattern,
    required this.route,
    required this.gtfsFile,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding:
          const EdgeInsets.only(left: 60, right: 12, top: 1, bottom: 1),
      child: Row(
        children: [
          const Icon(Icons.subdirectory_arrow_right,
              size: 10, color: Color(0xFF4A5568)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              pattern.displayName,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Edit button
          Tooltip(
            message: 'Editar trayecto',
            child: InkWell(
              onTap: () async {
                await ref
                    .read(patternEditorProvider.notifier)
                    .editPattern(pattern, gtfsFile, route);
              },
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.edit_outlined,
                    size: 12, color: Color(0xFF6B9FD4)),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Delete button
          Tooltip(
            message: 'Eliminar trayecto',
            child: InkWell(
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1E2129),
                    title: const Text('Eliminar trayecto',
                        style: TextStyle(
                            color: Colors.white, fontSize: 15)),
                    content: Text(
                      '¿Eliminar el trayecto "${pattern.displayName}"?\n\nEsta acción no se puede deshacer.',
                      style: const TextStyle(
                          color: Color(0xFF8B9299), fontSize: 13),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await GtfsRepository.deleteRoutePattern(pattern.id);
                ref.read(shapeCacheVersionProvider.notifier).state++;
                ref.read(patternCacheVersionProvider.notifier).state++;
                onDeleted();
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close,
                    size: 12,
                    color: Colors.redAccent.withOpacity(0.7)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final Color activeColor;

  const _SmallIconButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.activeColor = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            icon,
            size: 14,
            color: active
                ? activeColor
                : AppTheme.onSurfaceVariant.withOpacity(0.4),
          ),
        ),
      ),
    );
  }
}
