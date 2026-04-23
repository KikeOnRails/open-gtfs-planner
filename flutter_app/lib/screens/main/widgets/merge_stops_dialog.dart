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

  StopModel get _a => widget.stopA;
  StopModel get _b => widget.stopB;

  @override
  void initState() {
    super.initState();
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

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final (lat, lon) = _resolvedLatLon;

      // Both stops must belong to the same gtfs_file
      // (UI should enforce this, but guard here)
      if (_a.gtfsFileId != _b.gtfsFileId) {
        throw Exception(
            'Las paradas pertenecen a archivos GTFS distintos. No se pueden unificar.');
      }

      final merged = await GtfsRepository.mergeStops(
        gtfsFileId: _a.gtfsFileId,
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

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF1E2129);
    const border = Color(0xFF2E3340);
    const textPrimary = Colors.white;
    const textSecondary = Color(0xFF8B9299);

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
                  Expanded(child: _StopCard(stop: _a, label: 'Parada A')),
                  const SizedBox(width: 8),
                  const Icon(Icons.add, color: textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: _StopCard(stop: _b, label: 'Parada B')),
                ],
              ),
              const SizedBox(height: 20),

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

  const _StopCard({required this.stop, required this.label});

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
