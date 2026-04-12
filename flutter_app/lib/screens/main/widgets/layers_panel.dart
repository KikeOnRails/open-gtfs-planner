import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/gtfs_importer.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/simulation_providers.dart';
import '../../../core/database/gtfs_repository.dart';

class LayersPanel extends ConsumerStatefulWidget {
  const LayersPanel({super.key});

  @override
  ConsumerState<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends ConsumerState<LayersPanel> {
  bool _importing = false;
  double _importProgress = 0.0;
  String _importStep = '';

  @override
  Widget build(BuildContext context) {
    final gtfsFilesAsync = ref.watch(gtfsFilesProvider);

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
          if (_importing) _buildImportProgress(),
          Expanded(
            child: gtfsFilesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (files) => files.isEmpty
                  ? _buildEmptyLayers()
                  : _buildLayersList(files),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context) {
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
          Tooltip(
            message: 'Importar GTFS',
            child: InkWell(
              onTap: _importing ? null : _importGtfs,
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

  Widget _buildImportProgress() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _importStep,
                  style: const TextStyle(
                      color: AppTheme.primary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _importProgress,
              backgroundColor: AppTheme.primary.withOpacity(0.2),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              minHeight: 4,
            ),
          ),
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
            'Importa un archivo GTFS (.zip)\no una carpeta GTFS descomprimida',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _importing ? null : _importGtfs,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Importar GTFS'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

  Future<void> _importGtfs() async {
    final project = ref.read(currentProjectProvider);
    if (project == null) return;

    // Pick a zip file or folder
    if (kIsWeb) {
      // Web: pick zip file only (bytes mode)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
        dialogTitle: 'Selecciona archivo GTFS (.zip)',
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      await _runImportFromBytes(
          project.id, result.files.first.name, bytes);
    } else {
      // Desktop: pick zip or folder
      final zipResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: 'Selecciona archivo GTFS (.zip) o cancela para elegir carpeta',
      );

      String? path;
      if (zipResult != null && zipResult.files.isNotEmpty) {
        path = zipResult.files.first.path;
      } else {
        // Fall back to folder picker
        path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Selecciona carpeta GTFS',
        );
      }

      if (path == null) return;
      await _runImport(project.id, path);
    }
  }

  Future<void> _runImport(int projectId, String path) async {
    setState(() {
      _importing = true;
      _importProgress = 0;
      _importStep = 'Iniciando importación...';
    });

    try {
      final importer = GtfsImporter(
        onProgress: (step, progress) {
          setState(() {
            _importStep = step;
            _importProgress = progress;
          });
        },
      );
      await importer.import(projectId, path);
      _afterImport();
    } catch (e) {
      _showImportError(e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _runImportFromBytes(
      int projectId, String filename, Uint8List bytes) async {
    setState(() {
      _importing = true;
      _importProgress = 0;
      _importStep = 'Iniciando importación...';
    });

    try {
      final importer = GtfsImporter(
        onProgress: (step, progress) {
          setState(() {
            _importStep = step;
            _importProgress = progress;
          });
        },
      );
      await importer.importFromZipBytes(projectId, filename, bytes);
      _afterImport();
    } catch (e) {
      _showImportError(e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _afterImport() {
    ref.invalidate(gtfsFilesProvider);
    ref.invalidate(activeServicesProvider);
    ref.invalidate(activeTripsProvider);
  }

  void _showImportError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al importar GTFS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  tooltip: isVisible ? 'Ocultar shapes' : 'Mostrar shapes',
                  onTap: () => ref
                      .read(gtfsFileVisibilityProvider.notifier)
                      .set(widget.gtfsFile.id, !isVisible),
                ),
                const SizedBox(width: 4),
                // Stops toggle
                _SmallIconButton(
                  icon: Icons.place_outlined,
                  active: showStops,
                  tooltip: showStops
                      ? 'Ocultar paradas'
                      : 'Mostrar paradas',
                  onTap: () => ref
                      .read(gtfsStopsVisibilityProvider.notifier)
                      .set(widget.gtfsFile.id, !showStops),
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

    return routesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (allRoutes) {
        final agencyRoutes = allRoutes
            .where((r) => r.agencyDbId == widget.agency.id)
            .toList();

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
                      _expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${agencyRoutes.length} rutas',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              ...agencyRoutes.map(
                (r) => _RouteLayer(route: r, gtfsFile: widget.gtfsFile),
              ),
          ],
        );
      },
    );
  }
}

class _RouteLayer extends ConsumerWidget {
  final RouteModel route;
  final GtfsFileModel gtfsFile;
  const _RouteLayer({required this.route, required this.gtfsFile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shapeVis = ref.watch(routeShapeVisibilityProvider);
    final simVis = ref.watch(routeSimulationVisibilityProvider);

    final showShape = shapeVis[route.id] ?? false;
    final showSim = simVis[route.id] ?? false;

    final routeColor = hexToColor(route.routeColor);

    return Padding(
      padding: const EdgeInsets.only(left: 44, right: 12, top: 3, bottom: 3),
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
              onTap: () => _centerMapOnRoute(ref),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Text(
                  route.displayName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          // Shape visibility
          _SmallIconButton(
            icon: Icons.route_outlined,
            active: showShape,
            tooltip: showShape ? 'Ocultar recorrido' : 'Mostrar recorrido',
            onTap: () {
              ref
                  .read(routeShapeVisibilityProvider.notifier)
                  .set(route.id, !showShape);
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
              // Reload active trips
              ref.invalidate(activeTripsProvider);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _centerMapOnRoute(WidgetRef ref) async {
    final mapController = ref.read(mapControllerProvider);
    
    // Get shapes for this route
    final shapes = await GtfsRepository.getShapesByRoute(
      gtfsFile.id,
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
    
    // Fit bounds with padding
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
            color: active ? activeColor : AppTheme.onSurfaceVariant.withOpacity(0.4),
          ),
        ),
      ),
    );
  }
}
