import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/simulation_providers.dart';
import '../../../providers/project_providers.dart';

enum _PositionChoice { stopA, stopB, midpoint }

/// Shows the merge-stops dialog and returns the merged [StopModel] on success.
Future<StopModel?> showMergeStopsDialog(
  BuildContext context,
  WidgetRef ref,
  StopModel stopA,
  StopModel stopB,
) {
  return showDialog<StopModel>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MergeStopsDialog(stopA: stopA, stopB: stopB, ref: ref),
  );
}

/// Shows a dialog to pick the destination GTFS file for a cross-file merge.
/// Returns the selected [GtfsFileModel] or null if cancelled.
Future<GtfsFileModel?> showPickTargetGtfsDialog(
  BuildContext context,
  GtfsFileModel fileA,
  GtfsFileModel fileB,
) {
  return showDialog<GtfsFileModel>(
    context: context,
    builder: (_) => _PickTargetGtfsDialog(fileA: fileA, fileB: fileB),
  );
}

class _PickTargetGtfsDialog extends StatelessWidget {
  final GtfsFileModel fileA;
  final GtfsFileModel fileB;
  const _PickTargetGtfsDialog({required this.fileA, required this.fileB});

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF1E2129);
    const textPrimary = Colors.white;
    const textSecondary = Color(0xFF8B9299);

    return Dialog(
      backgroundColor: dark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder_copy_outlined,
                      color: Colors.teal, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GTFS destino',
                        style: TextStyle(
                            color: textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text('¿En qué archivo GTFS se creará la parada unificada?',
                        style: TextStyle(color: textSecondary, fontSize: 11)),
                  ],
                ),
              ]),
              const SizedBox(height: 20),
              _GtfsFileOption(
                file: fileA,
                label: 'Archivo A',
                color: Colors.orange,
                onTap: () => Navigator.of(context).pop(fileA),
              ),
              const SizedBox(height: 10),
              _GtfsFileOption(
                file: fileB,
                label: 'Archivo B',
                color: Colors.cyan,
                onTap: () => Navigator.of(context).pop(fileB),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar',
                      style: TextStyle(color: textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GtfsFileOption extends StatelessWidget {
  final GtfsFileModel file;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _GtfsFileOption({
    required this.file,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(file.filename,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.6), size: 18),
          ],
        ),
      ),
    );
  }
}

class _MergeStopsDialog extends StatefulWidget {
  final StopModel stopA;
  final StopModel stopB;
  final WidgetRef ref;

  const _MergeStopsDialog({
    required this.stopA,
    required this.stopB,
    required this.ref,
  });

  @override
  State<_MergeStopsDialog> createState() => _MergeStopsDialogState();
}

class _MergeStopsDialogState extends State<_MergeStopsDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _idCtrl;
  _PositionChoice _positionChoice = _PositionChoice.midpoint;
  bool _deleteOriginals = true;
  bool _isBusy = false;
  String? _error;
  int? _targetGtfsFileId;

  StopModel get _a => widget.stopA;
  StopModel get _b => widget.stopB;

  bool get _isCrossFile => _a.gtfsFileId != _b.gtfsFileId;

  @override
  void initState() {
    super.initState();
    _targetGtfsFileId = _isCrossFile ? null : _a.gtfsFileId;
    // Default name: combine both names
    final nameA = _a.displayName;
    final nameB = _b.displayName;
    _nameCtrl = TextEditingController(
      text: nameA == nameB ? nameA : '$nameA / $nameB',
    );
    _idCtrl = TextEditingController(
      text: 'merged_${_a.stopId}_${_b.stopId}',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  (double, double) get _resolvedLatLon {
    return switch (_positionChoice) {
      _PositionChoice.stopA => (_a.stopLat, _a.stopLon),
      _PositionChoice.stopB => (_b.stopLat, _b.stopLon),
      _PositionChoice.midpoint => (
          (_a.stopLat + _b.stopLat) / 2,
          (_a.stopLon + _b.stopLon) / 2,
        ),
    };
  }

  Future<void> _confirm() async {
    final name = _nameCtrl.text.trim();
    final stopId = _idCtrl.text.trim();

    if (stopId.isEmpty) {
      setState(() => _error = 'El ID de parada no puede estar vacío.');
      return;
    }

    // For cross-file merges we need a target file
    if (_isCrossFile && _targetGtfsFileId == null) {
      setState(() => _error = 'Selecciona el GTFS destino de la parada unificada.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final (lat, lon) = _resolvedLatLon;
      final targetFileId = _targetGtfsFileId!;

      final merged = await GtfsRepository.mergeStops(
        gtfsFileId: targetFileId,
        stopAId: _a.id,
        stopBId: _b.id,
        newStopId: stopId,
        newStopName: name.isEmpty ? null : name,
        newLat: lat,
        newLon: lon,
        newStopCode: null,
        deleteOriginals: _deleteOriginals,
      );

      // Clear selections
      widget.ref.read(selectedStopProvider.notifier).state = null;
      widget.ref.read(secondSelectedStopProvider.notifier).state = null;

      // Invalidate stop caches
      widget.ref.invalidate(gtfsFilesProvider);
      widget.ref.read(stopsCacheVersionProvider.notifier).state++;

      if (mounted) Navigator.of(context).pop(merged);
    } catch (e) {
      setState(() {
        _isBusy = false;
        _error = e.toString();
      });
    }
  }

  /// Reads the GTFS files from the provider and returns the display name for
  /// a given [gtfsFileId], or the id as string if not found.
  String _gtfsFilename(List<GtfsFileModel> files, int id) {
    return files.firstWhere((f) => f.id == id, orElse: () => GtfsFileModel(
      id: id, projectId: 0, filename: 'GTFS $id',
      importPath: '', importedAt: DateTime.now(),
    )).filename;
  }

  /// Builds the cross-file target GTFS file selector widgets.
  List<Widget> _buildTargetGtfsSelector(Color textSecondary, Color border) {
    final gtfsFilesAsync = widget.ref.watch(gtfsFilesProvider);
    final files = gtfsFilesAsync.valueOrNull ?? [];

    final fileAName = _gtfsFilename(files, _a.gtfsFileId);
    final fileBName = _gtfsFilename(files, _b.gtfsFileId);

    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.amber, size: 15),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Las paradas pertenecen a GTFS distintos. Elige el archivo destino.',
                style: TextStyle(color: Colors.amber, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _Label('GTFS destino de la parada unificada'),
      const SizedBox(height: 8),
      _GtfsFileRadio(
        fileId: _a.gtfsFileId,
        label: 'Archivo A — $fileAName',
        icon: Icons.folder_open,
        color: Colors.orange,
        groupValue: _targetGtfsFileId,
        onChanged: (v) => setState(() => _targetGtfsFileId = v),
      ),
      const SizedBox(height: 4),
      _GtfsFileRadio(
        fileId: _b.gtfsFileId,
        label: 'Archivo B — $fileBName',
        icon: Icons.folder_open,
        color: Colors.cyan,
        groupValue: _targetGtfsFileId,
        onChanged: (v) => setState(() => _targetGtfsFileId = v),
      ),
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF1E2129);
    const border = Color(0xFF2E3340);
    const textPrimary = Colors.white;
    const textSecondary = Color(0xFF8B9299);

    // Resolve GTFS file names for cross-file display
    final gtfsFiles = widget.ref.watch(gtfsFilesProvider).valueOrNull ?? [];
    final fileAName = _isCrossFile ? _gtfsFilename(gtfsFiles, _a.gtfsFileId) : null;
    final fileBName = _isCrossFile ? _gtfsFilename(gtfsFiles, _b.gtfsFileId) : null;

    return Dialog(
      backgroundColor: dark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.merge_type,
                        color: Colors.teal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unificar paradas',
                          style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Combinar dos paradas en una',
                          style:
                              TextStyle(color: textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Stop A & B cards
              Row(
                children: [
                  Expanded(child: _StopCard(stop: _a, label: 'Parada A', gtfsFilename: fileAName)),
                  const SizedBox(width: 8),
                  const Icon(Icons.add, color: textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: _StopCard(stop: _b, label: 'Parada B', gtfsFilename: fileBName)),
                ],
              ),
              const SizedBox(height: 16),

              // Cross-file: GTFS target selector
              if (_isCrossFile) ..._buildTargetGtfsSelector(textSecondary, border),

              const SizedBox(height: 4),

              // New stop name
              _Label('Nombre de la parada unificada'),
              const SizedBox(height: 6),
              _Field(controller: _nameCtrl, hint: 'Nombre de la nueva parada'),
              const SizedBox(height: 14),

              // New stop ID
              _Label('ID de la nueva parada'),
              const SizedBox(height: 6),
              _Field(controller: _idCtrl, hint: 'stop_id_unificado'),
              const SizedBox(height: 16),

              // Position
              _Label('Posición en el mapa'),
              const SizedBox(height: 8),
              _PositionRadio(
                value: _PositionChoice.midpoint,
                groupValue: _positionChoice,
                label: 'Punto medio entre A y B',
                icon: Icons.my_location,
                color: Colors.teal,
                onChanged: (v) => setState(() => _positionChoice = v!),
              ),
              const SizedBox(height: 4),
              _PositionRadio(
                value: _PositionChoice.stopA,
                groupValue: _positionChoice,
                label:
                    'Usar posición de Parada A  (${_a.stopLat.toStringAsFixed(5)}, ${_a.stopLon.toStringAsFixed(5)})',
                icon: Icons.place,
                color: Colors.orange,
                onChanged: (v) => setState(() => _positionChoice = v!),
              ),
              const SizedBox(height: 4),
              _PositionRadio(
                value: _PositionChoice.stopB,
                groupValue: _positionChoice,
                label:
                    'Usar posición de Parada B  (${_b.stopLat.toStringAsFixed(5)}, ${_b.stopLon.toStringAsFixed(5)})',
                icon: Icons.place,
                color: Colors.cyan,
                onChanged: (v) => setState(() => _positionChoice = v!),
              ),
              const SizedBox(height: 16),

              // Delete originals
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (_deleteOriginals
                          ? Colors.red
                          : Colors.white)
                      .withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_deleteOriginals
                            ? Colors.red
                            : border)
                        .withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _deleteOriginals,
                      onChanged: (v) =>
                          setState(() => _deleteOriginals = v ?? true),
                      activeColor: Colors.red[400],
                      side: const BorderSide(color: textSecondary),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'Eliminar las paradas originales A y B tras la unificación',
                        style: TextStyle(color: textPrimary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _isBusy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar',
                        style: TextStyle(color: textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.merge_type, size: 16),
                    label: Text(_isBusy ? 'Unificando…' : 'Unificar paradas'),
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
// Helper widgets
// ---------------------------------------------------------------------------

class _StopCard extends StatelessWidget {
  final StopModel stop;
  final String label;
  final String? gtfsFilename;

  const _StopCard({required this.stop, required this.label, this.gtfsFilename});

  @override
  Widget build(BuildContext context) {
    final color = label == 'Parada A' ? Colors.orange : Colors.cyan;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.place, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(
            stop.displayName,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            stop.stopId,
            style: const TextStyle(color: Color(0xFF8B9299), fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
          if (gtfsFilename != null) ...[  
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.folder_open, size: 10, color: Color(0xFF8B9299)),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  gtfsFilename!,
                  style: const TextStyle(color: Color(0xFF5A6370), fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF8B9299),
            fontSize: 11,
            fontWeight: FontWeight.w600),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _Field({required this.controller, required this.hint});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4A5568)),
          filled: true,
          fillColor: const Color(0xFF252930),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2E3340)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2E3340)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.teal),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );
}

class _PositionRadio extends StatelessWidget {
  final _PositionChoice value;
  final _PositionChoice groupValue;
  final String label;
  final IconData icon;
  final Color color;
  final ValueChanged<_PositionChoice?> onChanged;

  const _PositionRadio({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.icon,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : const Color(0xFF2E3340),
          ),
        ),
        child: Row(
          children: [
            Radio<_PositionChoice>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: selected ? color : Colors.white38),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Radio row used to select the target GTFS file for cross-file merges.
class _GtfsFileRadio extends StatelessWidget {
  final int fileId;
  final int? groupValue;
  final String label;
  final IconData icon;
  final Color color;
  final ValueChanged<int?> onChanged;

  const _GtfsFileRadio({
    required this.fileId,
    required this.groupValue,
    required this.label,
    required this.icon,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = fileId == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(fileId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : const Color(0xFF2E3340),
          ),
        ),
        child: Row(
          children: [
            Radio<int>(
              value: fileId,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: selected ? color : Colors.white38),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
