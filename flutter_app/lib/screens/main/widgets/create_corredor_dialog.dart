import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';

/// Dialog to create or edit a corridor (corredor).
///
/// Pass [editing] to pre-populate the form for an existing corridor.
class CreateCorredorDialog extends ConsumerStatefulWidget {
  final CorredorModel? editing;
  const CreateCorredorDialog({super.key, this.editing});

  @override
  ConsumerState<CreateCorredorDialog> createState() =>
      _CreateCorredorDialogState();
}

class _CreateCorredorDialogState
    extends ConsumerState<CreateCorredorDialog> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<int> _selectedStopIds = [];
  List<StopModel> _selectedStops = []; // same order as _selectedStopIds

  List<StopModel> _allStops = [];
  List<StopModel> _filteredStops = [];

  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      _nameCtrl.text = widget.editing!.name;
      _selectedStopIds = List.from(widget.editing!.stopIds);
      _selectedStops = List.from(widget.editing!.stops);
    }
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStops());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStops() async {
    setState(() => _loading = true);
    try {
      final files =
          ref.read(gtfsFilesProvider).valueOrNull ?? [];
      final stops = <StopModel>[];
      for (final file in files) {
        final fileStops = await GtfsRepository.getStops(file.id);
        stops.addAll(fileStops);
      }
      // Sort by name for easier search
      stops.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (mounted) {
        setState(() {
          _allStops = stops;
          _filteredStops = _filter(stops, _searchCtrl.text);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    setState(() {
      _filteredStops = _filter(_allStops, _searchCtrl.text);
    });
  }

  List<StopModel> _filter(List<StopModel> stops, String q) {
    if (q.trim().isEmpty) return stops;
    final lower = q.toLowerCase();
    return stops
        .where((s) =>
            s.displayName.toLowerCase().contains(lower) ||
            s.stopId.toLowerCase().contains(lower))
        .toList();
  }

  void _addStop(StopModel stop) {
    if (_selectedStopIds.contains(stop.id)) return;
    setState(() {
      _selectedStopIds.add(stop.id);
      _selectedStops.add(stop);
    });
  }

  void _removeStop(int index) {
    setState(() {
      _selectedStopIds.removeAt(index);
      _selectedStops.removeAt(index);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final id = _selectedStopIds.removeAt(oldIndex);
      _selectedStopIds.insert(newIndex, id);
      final stop = _selectedStops.removeAt(oldIndex);
      _selectedStops.insert(newIndex, stop);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    if (_selectedStopIds.length < 2) {
      setState(() => _error = 'Añade al menos 2 paradas.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.editing != null) {
        await ref.read(corredoresProvider.notifier).updateCorredor(
              widget.editing!.id,
              name,
              _selectedStopIds,
            );
      } else {
        await ref
            .read(corredoresProvider.notifier)
            .createCorredor(name, _selectedStopIds);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  const Icon(Icons.route_outlined,
                      color: AppTheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    widget.editing != null
                        ? 'Editar corredor'
                        : 'Nuevo corredor',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: AppTheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Name field
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del corredor',
                  hintText: 'Ej: Avenida de la Paz',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),

              // Two-column layout: stop search | selected stops chain
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: searchable stop list
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paradas disponibles',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: AppTheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _searchCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Buscar parada…',
                              prefixIcon: Icon(Icons.search, size: 16),
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                        color: AppTheme.primary))
                                : _filteredStops.isEmpty
                                    ? const Center(
                                        child: Text('Sin resultados',
                                            style: TextStyle(
                                                color: AppTheme
                                                    .onSurfaceVariant,
                                                fontSize: 12)))
                                    : ListView.builder(
                                        itemCount: _filteredStops.length,
                                        itemBuilder: (ctx, i) {
                                          final stop = _filteredStops[i];
                                          final selected = _selectedStopIds
                                              .contains(stop.id);
                                          return ListTile(
                                            dense: true,
                                            leading: Icon(
                                              selected
                                                  ? Icons.check_circle
                                                  : Icons.place_outlined,
                                              size: 16,
                                              color: selected
                                                  ? AppTheme.primary
                                                  : AppTheme
                                                      .onSurfaceVariant,
                                            ),
                                            title: Text(
                                              stop.displayName,
                                              style: const TextStyle(
                                                  fontSize: 12),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              stop.stopId,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme
                                                      .onSurfaceVariant),
                                            ),
                                            onTap: selected
                                                ? null
                                                : () => _addStop(stop),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Right: selected stops in order (reorderable)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paradas del corredor (en orden)',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: AppTheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: _selectedStops.isEmpty
                                ? Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: const Color(0xFF2E3340)),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'Toca una parada\nde la lista para añadirla',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                : ReorderableListView.builder(
                                    onReorder: _reorder,
                                    itemCount: _selectedStops.length,
                                    itemBuilder: (ctx, i) {
                                      final stop = _selectedStops[i];
                                      return _SelectedStopTile(
                                        key: ValueKey(stop.id),
                                        stop: stop,
                                        index: i,
                                        isFirst: i == 0,
                                        isLast:
                                            i == _selectedStops.length - 1,
                                        onRemove: () => _removeStop(i),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent,
                        fontSize: 12)),
              ],

              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(
                        widget.editing != null ? 'Guardar' : 'Crear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small tile for a selected stop showing the chain connector
// ---------------------------------------------------------------------------

class _SelectedStopTile extends StatelessWidget {
  final StopModel stop;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onRemove;

  const _SelectedStopTile({
    super.key,
    required this.stop,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Chain visualisation
          SizedBox(
            width: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isFirst)
                  Container(width: 2, height: 8,
                      color: AppTheme.primary.withOpacity(0.4)),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.surface, width: 2),
                  ),
                ),
                if (!isLast)
                  Container(width: 2, height: 8,
                      color: AppTheme.primary.withOpacity(0.4)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: const Color(0xFF2E3340)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      stop.displayName,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Drag handle (provided by ReorderableListView)
                  const Icon(Icons.drag_handle,
                      size: 14, color: AppTheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onRemove,
                    child: const Icon(Icons.close,
                        size: 14, color: AppTheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
