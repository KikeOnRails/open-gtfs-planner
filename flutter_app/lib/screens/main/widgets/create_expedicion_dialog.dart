import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the dialog and returns the number of expediciones created (0 = cancelled).
Future<int> showCreateExpedicionDialog(
    BuildContext context, RouteModel route, GtfsFileModel gtfsFile) async {
  return await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _CreateExpedicionDialog(route: route, gtfsFile: gtfsFile),
      ) ??
      0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

int? _parseHHMM(String s) {
  final parts = s.trim().split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || m < 0 || m > 59) return null;
  return h * 3600 + m * 60;
}

String _fmtSeconds(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String _fmtDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}min';
  return '${m}min';
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog widget
// ─────────────────────────────────────────────────────────────────────────────

class _CreateExpedicionDialog extends StatefulWidget {
  final RouteModel route;
  final GtfsFileModel gtfsFile;

  const _CreateExpedicionDialog({required this.route, required this.gtfsFile});

  @override
  State<_CreateExpedicionDialog> createState() =>
      _CreateExpedicionDialogState();
}

class _CreateExpedicionDialogState extends State<_CreateExpedicionDialog> {
  // Loaded
  List<RoutePatternModel> _patterns = [];
  List<String> _serviceIds = [];

  // Selections
  RoutePatternModel? _selectedPattern;
  List<RoutePatternStopModel> _patternStops = [];
  String _serviceId = '';

  // Mode
  bool _rangeMode = true;

  // Controllers
  final _serviceCtrl = TextEditingController();
  final _startCtrl = TextEditingController(text: '08:00');
  final _endCtrl = TextEditingController(text: '22:00');
  final _freqCtrl = TextEditingController(text: '15');

  // State
  List<int> _previewTimes = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  int? get _tripDuration {
    if (_patternStops.isEmpty) return null;
    return _patternStops.last.timeFromOriginSeconds;
  }

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_startCtrl, _endCtrl, _freqCtrl]) {
      c.addListener(_recompute);
    }
  }

  @override
  void dispose() {
    _serviceCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _freqCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final patterns = await GtfsRepository.getRoutePatterns(widget.route.id);
    final sids = await GtfsRepository.getServiceIds(widget.gtfsFile.id);
    setState(() {
      _patterns = patterns;
      _serviceIds = sids;
      _selectedPattern = patterns.isNotEmpty ? patterns.first : null;
      _serviceId = sids.isNotEmpty ? sids.first : '';
      _serviceCtrl.text = _serviceId;
      _loading = false;
    });
    if (_selectedPattern != null) await _loadStops();
    _recompute();
  }

  Future<void> _loadStops() async {
    if (_selectedPattern == null) return;
    final stops = await GtfsRepository.getPatternStops(_selectedPattern!.id);
    setState(() => _patternStops = stops);
  }

  void _recompute() {
    final start = _parseHHMM(_startCtrl.text);
    if (!_rangeMode) {
      setState(() => _previewTimes = start != null ? [start] : []);
      return;
    }
    final end = _parseHHMM(_endCtrl.text);
    final freq = int.tryParse(_freqCtrl.text.trim());
    if (start == null ||
        end == null ||
        freq == null ||
        freq <= 0 ||
        end <= start) {
      setState(() => _previewTimes = []);
      return;
    }
    final times = <int>[];
    for (int t = start; t <= end; t += freq * 60) {
      times.add(t);
    }
    setState(() => _previewTimes = times);
  }

  Future<void> _create() async {
    if (_selectedPattern == null ||
        _serviceId.isEmpty ||
        _previewTimes.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final count = await GtfsRepository.insertExpediciones(
        gtfsFileId: widget.gtfsFile.id,
        routeDbId: widget.route.id,
        patternId: _selectedPattern!.id,
        serviceId: _serviceId,
        departureTimesSeconds: _previewTimes,
      );
      if (mounted) Navigator.of(context).pop(count);
    } catch (e) {
      setState(() {
        _creating = false;
        _error = e.toString();
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E2129),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPatternSection(),
                          const SizedBox(height: 18),
                          _buildServiceSection(),
                          const SizedBox(height: 18),
                          _buildTimeSection(),
                          const SizedBox(height: 18),
                          _buildPreview(),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(_error!,
                                style: TextStyle(
                                    color: Colors.red[400], fontSize: 12)),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: Color(0xFF2A2F3A), width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.departure_board, size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nueva expedición',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(widget.route.displayName,
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
            onPressed: () => Navigator.of(context).pop(0),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Trayecto'),
        const SizedBox(height: 8),
        if (_patterns.isEmpty)
          _infoBox(
              'No hay trayectos definidos. Crea uno primero desde el panel de capas.')
        else
          _darkDropdown<RoutePatternModel>(
            value: _selectedPattern,
            items: _patterns
                .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.displayName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ))
                .toList(),
            onChanged: (p) async {
              setState(() {
                _selectedPattern = p;
                _patternStops = [];
              });
              if (p != null) await _loadStops();
            },
          ),
        if (_patternStops.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${_patternStops.length} paradas'
            '${_tripDuration != null && _tripDuration! > 0 ? ' · duración ${_fmtDuration(_tripDuration!)}' : ''}',
            style:
                const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildServiceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Servicio (service_id)'),
        const SizedBox(height: 8),
        _darkTextField(
          controller: _serviceCtrl,
          hint: 'Ej: LABORABLE, L-V, 1…',
          onChanged: (v) => setState(() => _serviceId = v),
        ),
        if (_serviceIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _serviceIds.take(12).map((sid) {
              final selected = _serviceId == sid;
              return GestureDetector(
                onTap: () => setState(() {
                  _serviceId = sid;
                  _serviceCtrl.text = sid;
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withOpacity(0.18)
                        : const Color(0xFF161A22),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : const Color(0xFF2A2F3A)),
                  ),
                  child: Text(
                    sid,
                    style: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? AppTheme.primary
                          : const Color(0xFF8B9299),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTimeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Horarios'),
        const SizedBox(height: 8),
        // Mode toggle
        Row(
          children: [
            _modeButton('Una expedición', !_rangeMode, () {
              setState(() => _rangeMode = false);
              _recompute();
            }),
            const SizedBox(width: 8),
            _modeButton('Franja horaria', _rangeMode, () {
              setState(() => _rangeMode = true);
              _recompute();
            }),
          ],
        ),
        const SizedBox(height: 12),
        if (!_rangeMode)
          SizedBox(
            width: 140,
            child: _labeledField('Hora de salida', _startCtrl, 'HH:MM'),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _labeledField('Inicio', _startCtrl, 'HH:MM')),
              const SizedBox(width: 12),
              Expanded(child: _labeledField('Fin', _endCtrl, 'HH:MM')),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: _labeledField('Cadencia (min)', _freqCtrl, '15',
                    numeric: true),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('Vista previa'),
            const Spacer(),
            if (_previewTimes.isNotEmpty)
              Text(
                '${_previewTimes.length} expedición${_previewTimes.length != 1 ? 'es' : ''}',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 44, maxHeight: 108),
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF161A22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2A2F3A)),
          ),
          child: _previewTimes.isEmpty
              ? const Center(
                  child: Text(
                    'Define los horarios para ver la vista previa',
                    style:
                        TextStyle(color: Color(0xFF4B5563), fontSize: 12),
                  ),
                )
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _previewTimes
                        .map((t) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _fmtSeconds(t),
                                style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontFamily: 'monospace'),
                              ),
                            ))
                        .toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final canCreate = !_loading &&
        _selectedPattern != null &&
        _serviceId.isNotEmpty &&
        _previewTimes.isNotEmpty &&
        !_creating;

    final label = _previewTimes.isEmpty
        ? 'Crear expedición'
        : _previewTimes.length == 1
            ? 'Crear 1 expedición'
            : 'Crear ${_previewTimes.length} expediciones';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2F3A), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _creating ? null : () => Navigator.of(context).pop(0),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: canCreate ? _create : null,
            icon: _creating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add, size: 16),
            label: Text(label),
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF9BA3AF),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5),
      );

  Widget _infoBox(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161A22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2F3A)),
        ),
        child: Text(text,
            style:
                const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
      );

  Widget _modeButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primary.withOpacity(0.15)
              : const Color(0xFF161A22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? AppTheme.primary : const Color(0xFF2A2F3A)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? AppTheme.primary : const Color(0xFF8B9299),
            fontWeight:
                active ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _labeledField(
    String label,
    TextEditingController ctrl,
    String hint, {
    bool numeric = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF6B7280), fontSize: 10)),
        const SizedBox(height: 4),
        _darkTextField(controller: ctrl, hint: hint, numeric: numeric),
      ],
    );
  }

  Widget _darkTextField({
    required TextEditingController controller,
    String hint = '',
    bool numeric = false,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType:
          numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(0xFF4B5563), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF161A22),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:
              const BorderSide(color: Color(0xFF2A2F3A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:
              const BorderSide(color: Color(0xFF2A2F3A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _darkDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161A22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2F3A)),
      ),
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        dropdownColor: const Color(0xFF1E2129),
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.keyboard_arrow_down,
            color: Color(0xFF6B7280), size: 18),
      ),
    );
  }
}
