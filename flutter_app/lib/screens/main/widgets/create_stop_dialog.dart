import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';

// ---------------------------------------------------------------------------
// Provider: when non-null the map is in "pick stop location" mode.
// Holds a callback that receives the tapped LatLng.
// ---------------------------------------------------------------------------

final pickStopLocationProvider =
    StateProvider<void Function(LatLng)?>((_) => null);

// ---------------------------------------------------------------------------
// Entry point: activate pick mode. The dialog is shown automatically once
// the user taps the map (via [deliverPickedStopLocation]).
// ---------------------------------------------------------------------------

void activatePickStopMode(BuildContext context, WidgetRef ref) {
  ref.read(pickStopLocationProvider.notifier).state = (latLng) {
    ref.read(pickStopLocationProvider.notifier).state = null;
    deliverPickedStopLocation(context, ref, latLng);
  };
}

// ---------------------------------------------------------------------------
// Dialog
// ---------------------------------------------------------------------------

class _CreateStopDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final double? initialLat;
  final double? initialLon;
  const _CreateStopDialog({required this.ref, this.initialLat, this.initialLon});

  @override
  ConsumerState<_CreateStopDialog> createState() => _CreateStopDialogState();
}

class _CreateStopDialogState extends ConsumerState<_CreateStopDialog> {
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();

  GtfsFileModel? _selectedFile;
  bool _isBusy = false;
  bool _isPicking = false;
  String? _error;

  static const _bg = Color(0xFF1E2129);
  static const _surface = Color(0xFF252930);
  static const _border = Color(0xFF2E3340);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFF8B9299);
  static const _accent = Colors.teal;

  @override
  void initState() {
    super.initState();
    // Auto-generate stop_id
    _idCtrl.text = 'stop_${_randomHex(6)}';
    if (widget.initialLat != null) {
      _latCtrl.text = widget.initialLat!.toStringAsFixed(6);
    }
    if (widget.initialLon != null) {
      _lonCtrl.text = widget.initialLon!.toStringAsFixed(6);
    }
    // Auto-select the GTFS file when there is exactly one loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final files = ref.read(gtfsFilesProvider).valueOrNull ?? [];
      if (files.length == 1 && mounted) {
        setState(() => _selectedFile = files.first);
      }
    });
  }

  static String _randomHex(int length) {
    const chars = '0123456789abcdef';
    final rng = math.Random();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _codeCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    // Ensure pick mode is cleared
    widget.ref.read(pickStopLocationProvider.notifier).state = null;
    super.dispose();
  }

  Future<void> _pickFromMap() async {
    if (_isPicking) return;

    // Temporarily close the dialog
    setState(() => _isPicking = true);

    // Dismiss the dialog — it will be re-opened after pick
    if (mounted) Navigator.of(context).pop(kPickStopSentinel);
  }

  Future<void> _confirm() async {
    final name = _nameCtrl.text.trim();
    final stopId =
        _idCtrl.text.trim().isEmpty ? 'stop_${_randomHex(6)}' : _idCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());

    if (_selectedFile == null) {
      setState(() => _error = 'Selecciona el archivo GTFS de destino.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'El nombre de la parada no puede estar vacío.');
      return;
    }
    if (lat == null || lon == null) {
      setState(() => _error = 'Introduce una ubicación válida (lat/lon).');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      await GtfsRepository.insertStop(_selectedFile!.id, {
        'stop_id': stopId,
        'stop_name': name,
        'stop_lat': lat.toString(),
        'stop_lon': lon.toString(),
        'stop_code': _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
      });

      // Reload GTFS file cache
      widget.ref.invalidate(gtfsFilesProvider);
      widget.ref.read(stopsCacheVersionProvider.notifier).state++;

      final rows = await GtfsRepository.getStops(_selectedFile!.id);
      final created = rows.lastWhere((s) => s.stopId == stopId);

      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      setState(() {
        _isBusy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gtfsFilesAsync = ref.watch(gtfsFilesProvider);
    final files = gtfsFilesAsync.valueOrNull ?? [];

    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.add_location_alt, color: _accent, size: 18),
                ),
                const SizedBox(width: 10),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Crear parada',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  Text('Añadir nueva parada al GTFS',
                      style: TextStyle(color: _textSecondary, fontSize: 12)),
                ]),
              ]),

              const SizedBox(height: 20),

              // GTFS file selector
              _label('Archivo GTFS de destino'),
              const SizedBox(height: 6),
              _fileDropdown(files),

              const SizedBox(height: 14),

              // Name
              _label('Nombre de la parada *'),
              const SizedBox(height: 6),
              _field(_nameCtrl, 'Ej: Avenida Principal'),

              const SizedBox(height: 14),

              // Stop ID
              _label('ID de la parada (stop_id)'),
              const SizedBox(height: 6),
              _field(_idCtrl, 'Auto-generado si está vacío'),

              const SizedBox(height: 14),

              // Code (optional)
              _label('Código de parada (stop_code) — opcional'),
              const SizedBox(height: 6),
              _field(_codeCtrl, 'Ej: 1234'),

              const SizedBox(height: 14),

              // Location
              _label('Ubicación *'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _field(_latCtrl, 'Latitud  Ej: 40.4168'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(_lonCtrl, 'Longitud  Ej: -3.7038'),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Seleccionar ubicación en el mapa',
                  child: InkWell(
                    onTap: _pickFromMap,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _accent.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.my_location,
                          size: 18, color: _accent),
                    ),
                  ),
                ),
              ]),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],

              const SizedBox(height: 20),

              // Actions
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed:
                      _isBusy ? null : () => Navigator.of(context).pop(null),
                  child: const Text('Cancelar',
                      style: TextStyle(color: _textSecondary)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isBusy ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                  ),
                  icon: _isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_location_alt, size: 16),
                  label: Text(_isBusy ? 'Creando…' : 'Crear parada'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w600));

  Widget _field(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: const TextStyle(color: _textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4A5568)),
          filled: true,
          fillColor: _surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accent)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );

  Widget _fileDropdown(List<GtfsFileModel> files) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<GtfsFileModel>(
          value: _selectedFile,
          hint: const Text('Selecciona un archivo GTFS',
              style: TextStyle(color: Color(0xFF4A5568), fontSize: 13)),
          dropdownColor: _surface,
          isExpanded: true,
          iconEnabledColor: _textSecondary,
          style: const TextStyle(color: _textPrimary, fontSize: 13),
          items: files
              .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(f.filename,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (f) => setState(() => _selectedFile = f),
        ),
      ),
    );
  }
}

// Sentinel value returned when the user triggers "pick from map"
const kPickStopSentinel = PickStopSentinel();

class PickStopSentinel {
  const PickStopSentinel();
}

// ---------------------------------------------------------------------------
// Helper called by the map widget tap handler to deliver a picked location.
// Also re-opens the dialog continuing the creation flow.
// ---------------------------------------------------------------------------

/// Called from map_widget when the user taps in pick-stop-location mode.
Future<void> deliverPickedStopLocation(
    BuildContext context, WidgetRef ref, LatLng location) async {
  // Exit pick mode
  ref.read(pickStopLocationProvider.notifier).state = null;

  // Re-open the dialog pre-filled with the chosen location
  await showDialog<StopModel>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _CreateStopDialog(ref: ref, initialLat: location.latitude, initialLon: location.longitude),
  ).then((created) {
    if (created != null && created is! PickStopSentinel) {
      // Refresh
      ref.invalidate(gtfsFilesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: const Color(0xFF0D5C47),
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Parada "${created.displayName}" creada',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ]),
        ));
      }
    }
  });
}
