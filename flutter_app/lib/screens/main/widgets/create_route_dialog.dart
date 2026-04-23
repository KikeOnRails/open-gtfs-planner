import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/route_editor_providers.dart';

// ---------------------------------------------------------------------------
// Route type options (GTFS spec)
// ---------------------------------------------------------------------------

const _routeTypes = [
  (0, 'Tranvía / tren ligero'),
  (1, 'Metro / subte'),
  (2, 'Tren'),
  (3, 'Autobús'),
  (4, 'Ferry'),
  (5, 'Teleférico'),
  (6, 'Góndola / funicular aéreo'),
  (7, 'Funicular'),
  (11, 'Trolebús'),
  (12, 'Monorraíl'),
];

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

Future<void> showCreateRouteDialog(
    BuildContext context, WidgetRef ref, GtfsFileModel gtfsFile) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreateRouteDialog(ref: ref, gtfsFile: gtfsFile),
  );
}

// ---------------------------------------------------------------------------
// Dialog
// ---------------------------------------------------------------------------

class _CreateRouteDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final GtfsFileModel gtfsFile;
  const _CreateRouteDialog({required this.ref, required this.gtfsFile});

  @override
  ConsumerState<_CreateRouteDialog> createState() => _CreateRouteDialogState();
}

class _CreateRouteDialogState extends ConsumerState<_CreateRouteDialog> {
  final _shortNameCtrl = TextEditingController();
  final _longNameCtrl = TextEditingController();
  final _routeIdCtrl = TextEditingController();

  AgencyModel? _selectedAgency;
  int _routeType = 3; // Bus by default
  Color _routeColor = Colors.teal;
  bool _isBusy = false;
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
    _routeIdCtrl.text = 'route_${_randomHex(6)}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final agencies = ref.read(agenciesProvider(widget.gtfsFile.id)).valueOrNull ?? [];
      if (agencies.length == 1 && mounted) {
        setState(() => _selectedAgency = agencies.first);
      }
    });
  }

  static String _randomHex(int length) {
    const chars = '0123456789abcdef';
    final rng = math.Random();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _shortNameCtrl.dispose();
    _longNameCtrl.dispose();
    _routeIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final shortName = _shortNameCtrl.text.trim();
    final longName = _longNameCtrl.text.trim();
    final routeId = _routeIdCtrl.text.trim().isEmpty ? 'route_${_randomHex(6)}' : _routeIdCtrl.text.trim();

    if (shortName.isEmpty && longName.isEmpty) {
      setState(() => _error = 'Introduce al menos nombre corto o largo.');
      return;
    }

    setState(() { _isBusy = true; _error = null; });
    try {
      final colorHex = _routeColor.value.toRadixString(16).substring(2).toUpperCase();
      final id = await GtfsRepository.insertRoute(
        widget.gtfsFile.id,
        _selectedAgency?.id,
        {
          'route_id': routeId,
          'route_short_name': shortName.isEmpty ? null : shortName,
          'route_long_name': longName.isEmpty ? null : longName,
          'route_type': _routeType.toString(),
          'route_color': colorHex,
          'route_text_color': 'FFFFFF',
        },
      );
      widget.ref.invalidate(gtfsFilesProvider);
      widget.ref.invalidate(routesProvider(widget.gtfsFile.id));

      final route = await GtfsRepository.getRouteById(id);
      if (route != null && mounted) {
        Navigator.of(context).pop();
        // Launch trayecto editor
        widget.ref.read(patternEditorProvider.notifier).start(route, widget.gtfsFile);
      }
    } catch (e) {
      setState(() { _isBusy = false; _error = e.toString(); });
    }
  }

  void _pickColor() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bg,
        title: const Text('Color de la ruta', style: TextStyle(color: _textPrimary, fontSize: 14)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _routeColor,
            onColorChanged: (c) => setState(() => _routeColor = c),
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agencies = ref.watch(agenciesProvider(widget.gtfsFile.id)).valueOrNull ?? [];

    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
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
                  child: const Icon(Icons.route, color: _accent, size: 18),
                ),
                const SizedBox(width: 10),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Crear ruta', style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Nueva ruta GTFS', style: TextStyle(color: _textSecondary, fontSize: 12)),
                ]),
              ]),

              const SizedBox(height: 20),

              // Agency selector
              if (agencies.isNotEmpty) ...[
                _label('Agencia (opcional)'),
                const SizedBox(height: 6),
                _agencyDropdown(agencies),
                const SizedBox(height: 14),
              ],

              // Short name + color row
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label('Nombre corto *'),
                    const SizedBox(height: 6),
                    _field(_shortNameCtrl, 'Ej: L1, 30, EMT'),
                  ]),
                ),
                const SizedBox(width: 12),
                Column(children: [
                  _label('Color'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickColor,
                    child: Container(
                      width: 44, height: 40,
                      decoration: BoxDecoration(
                        color: _routeColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _border, width: 1.5),
                      ),
                    ),
                  ),
                ]),
              ]),
              const SizedBox(height: 14),

              // Long name
              _label('Nombre largo'),
              const SizedBox(height: 6),
              _field(_longNameCtrl, 'Ej: Línea 1 - Norte-Sur'),
              const SizedBox(height: 14),

              // Route ID
              _label('ID de ruta (route_id)'),
              const SizedBox(height: 6),
              _field(_routeIdCtrl, 'Auto-generado si está vacío'),
              const SizedBox(height: 14),

              // Route type
              _label('Tipo de transporte'),
              const SizedBox(height: 6),
              _typeDropdown(),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],

              const SizedBox(height: 20),

              // Actions
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar', style: TextStyle(color: _textSecondary)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isBusy ? null : _confirm,
                  style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
                  icon: _isBusy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: Text(_isBusy ? 'Creando…' : 'Crear ruta'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w600));

  Widget _field(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: const TextStyle(color: _textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4A5568)),
          filled: true,
          fillColor: _surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _accent)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );

  Widget _agencyDropdown(List<AgencyModel> agencies) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AgencyModel?>(
          value: _selectedAgency,
          hint: const Text('Sin agencia', style: TextStyle(color: Color(0xFF4A5568), fontSize: 13)),
          dropdownColor: _surface,
          isExpanded: true,
          iconEnabledColor: _textSecondary,
          style: const TextStyle(color: _textPrimary, fontSize: 13),
          items: [
            const DropdownMenuItem<AgencyModel?>(value: null, child: Text('Sin agencia', style: TextStyle(color: Color(0xFF4A5568)))),
            ...agencies.map((a) => DropdownMenuItem(value: a, child: Text(a.agencyName, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: (a) => setState(() => _selectedAgency = a),
        ),
      ),
    );
  }

  Widget _typeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _routeType,
          dropdownColor: _surface,
          isExpanded: true,
          iconEnabledColor: _textSecondary,
          style: const TextStyle(color: _textPrimary, fontSize: 13),
          items: _routeTypes
              .map((t) => DropdownMenuItem(value: t.$1, child: Text('${t.$1} – ${t.$2}', overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _routeType = v ?? 3),
        ),
      ),
    );
  }
}
