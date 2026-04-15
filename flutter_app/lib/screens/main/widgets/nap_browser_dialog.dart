import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/nap_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/simulation_providers.dart';

/// Shows a dialog to browse and import GTFS from the NAP (Mitma) repository.
Future<void> showNapBrowserDialog(
    BuildContext context, WidgetRef ref, int projectId) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _NapBrowserDialog(projectId: projectId, ref: ref),
  );
}

class _NapBrowserDialog extends StatefulWidget {
  final int projectId;
  final WidgetRef ref;

  const _NapBrowserDialog({required this.projectId, required this.ref});

  @override
  State<_NapBrowserDialog> createState() => _NapBrowserDialogState();
}

class _NapBrowserDialogState extends State<_NapBrowserDialog> {
  final _searchController = TextEditingController();
  List<NapGtfsDataset>? _datasets;
  List<NapGtfsDataset>? _filteredDatasets;
  bool _isLoading = true;
  String? _error;
  bool _isDownloading = false;
  String? _downloadingName;

  @override
  void initState() {
    super.initState();
    _loadDatasets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDatasets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final datasets = await NapRepositoryService.getDatasets();
      if (mounted) {
        setState(() {
          _datasets = datasets;
          _filteredDatasets = datasets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_datasets == null) return;
    setState(() {
      if (query.isEmpty) {
        _filteredDatasets = _datasets;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredDatasets = _datasets!.where((d) {
          return d.nombre.toLowerCase().contains(lowerQuery) ||
              (d.descripcion?.toLowerCase().contains(lowerQuery) ?? false) ||
              (d.organizacionNombre?.toLowerCase().contains(lowerQuery) ??
                  false) ||
              d.regiones
                  .any((r) => r.nombre.toLowerCase().contains(lowerQuery)) ||
              d.operadores
                  .any((o) => o.nombre.toLowerCase().contains(lowerQuery)) ||
              d.tiposTransporte
                  .any((t) => t.nombre.toLowerCase().contains(lowerQuery));
        }).toList();
      }
    });
  }

  Future<void> _importDataset(NapGtfsDataset dataset) async {
    final ficheroId = dataset.primaryFicheroId;
    if (ficheroId == null) return;

    setState(() {
      _isDownloading = true;
      _downloadingName = dataset.nombre;
    });

    try {
      // Download the GTFS ZIP
      final bytes = await NapRepositoryService.downloadFile(ficheroId);

      // Import it using the existing import flow
      final filename = '${dataset.nombre.trim()}.zip';

      await widget.ref
          .read(gtfsImportProvider)
          .importFromBytes(widget.projectId, filename, Uint8List.fromList(bytes));

      widget.ref.invalidate(activeServicesProvider);
      widget.ref.invalidate(activeTripsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GTFS "${dataset.nombre}" importado correctamente'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadingName = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al importar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              _buildSearchBar(),
              const SizedBox(height: 16),
              Expanded(child: _buildContent()),
              if (_isDownloading) _buildDownloadingBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.cloud_download_outlined,
              color: AppTheme.accent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Repositorio NAP - Mitma',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Punto de Acceso Nacional de Transporte',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed:
              _isDownloading ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, región, operador...',
        prefixIcon:
            const Icon(Icons.search, color: AppTheme.onSurfaceVariant, size: 20),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2E3340)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2E3340)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Cargando datos del NAP...',
                style: TextStyle(color: AppTheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(
              'Error al cargar datos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadDatasets,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final datasets = _filteredDatasets ?? [];
    if (datasets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off,
                color: AppTheme.onSurfaceVariant, size: 40),
            const SizedBox(height: 12),
            Text(
              'No se encontraron resultados',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${datasets.length} datasets encontrados',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: datasets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) =>
                _DatasetCard(
                  dataset: datasets[index],
                  onImport: _isDownloading ? null : () => _importDataset(datasets[index]),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingBar() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Descargando e importando "$_downloadingName"...',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dataset card widget
// ---------------------------------------------------------------------------

class _DatasetCard extends StatelessWidget {
  final NapGtfsDataset dataset;
  final VoidCallback? onImport;

  const _DatasetCard({required this.dataset, this.onImport});

  @override
  Widget build(BuildContext context) {
    final fichero = dataset.primaryFichero;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onImport,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2E3340), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Transport icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _transportIcon(dataset.transportTypesText),
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dataset.nombre,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dataset.organizacionNombre != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        dataset.organizacionNombre!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),

                    // Stats row
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (dataset.transportTypesText.isNotEmpty)
                          _Chip(
                            icon: Icons.directions_transit,
                            text: dataset.transportTypesText,
                          ),
                        if (dataset.regionesText.isNotEmpty)
                          _Chip(
                            icon: Icons.place_outlined,
                            text: dataset.regionesText,
                          ),
                        if (fichero != null) ...[
                          if (fichero.numeroRutas != null)
                            _Chip(
                              icon: Icons.route,
                              text: '${fichero.numeroRutas} rutas',
                            ),
                          if (fichero.numeroParadas != null)
                            _Chip(
                              icon: Icons.pin_drop_outlined,
                              text: '${fichero.numeroParadas} paradas',
                            ),
                          if (fichero.sizeText.isNotEmpty)
                            _Chip(
                              icon: Icons.storage,
                              text: fichero.sizeText,
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Import button
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.download, color: AppTheme.primary),
                tooltip: 'Importar',
                onPressed: onImport,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _transportIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('metro') || lower.contains('suburbano')) {
      return Icons.subway;
    }
    if (lower.contains('tren') || lower.contains('ferrocarril') || lower.contains('cercanías')) {
      return Icons.train;
    }
    if (lower.contains('tranvía') || lower.contains('tram')) {
      return Icons.tram;
    }
    if (lower.contains('barco') || lower.contains('ferry') || lower.contains('marítimo')) {
      return Icons.directions_boat;
    }
    return Icons.directions_bus;
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
