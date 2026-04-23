import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/route_editor_providers.dart';

// ---------------------------------------------------------------------------
// Panel: shown as a left-side overlay while editing a trayecto
// ---------------------------------------------------------------------------

class TrayectoEditorPanel extends ConsumerStatefulWidget {
  const TrayectoEditorPanel({super.key});

  @override
  ConsumerState<TrayectoEditorPanel> createState() => _TrayectoEditorPanelState();
}

class _TrayectoEditorPanelState extends ConsumerState<TrayectoEditorPanel> {
  final _nameCtrl = TextEditingController();
  // Controllers for time inputs, keyed by stop index
  final _nameFocus = FocusNode();
  final Map<int, TextEditingController> _timeCtrl = {};

  static const _bg = Color(0xFF1E2129);
  static const _surface = Color(0xFF252930);
  static const _border = Color(0xFF2E3340);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFF8B9299);
  static const _accent = Colors.teal;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    for (final c in _timeCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Ensure controller exists for the given index
  TextEditingController _ctrl(int index, int? currentSeconds) {
    if (!_timeCtrl.containsKey(index)) {
      _timeCtrl[index] = TextEditingController(
        text: currentSeconds != null ? _secondsToMmSs(currentSeconds) : '',
      );
    }
    return _timeCtrl[index]!;
  }

  // Clean up controllers that no longer have a corresponding stop
  void _pruneControllers(int stopCount) {
    _timeCtrl.removeWhere((k, c) {
      if (k >= stopCount) {
        c.dispose();
        return true;
      }
      return false;
    });
  }

  static String _secondsToMmSs(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static int? _mmSsToSeconds(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final parts = t.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m != null && s != null) return m * 60 + s;
    }
    // Plain minutes
    final mins = int.tryParse(t);
    if (mins != null) return mins * 60;
    return null;
  }

  Color _routeColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.teal;
    try {
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patternEditorProvider);
    if (state == null) return const SizedBox.shrink();

    _pruneControllers(state.stops.length);

    // Sync name controller without clobbering cursor
    if (_nameCtrl.text != state.patternName && !_nameFocus.hasFocus) {
      _nameCtrl.text = state.patternName;
    }

    final rColor = _routeColor(state.route.routeColor);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: _bg,
        border: const Border(right: BorderSide(color: _border)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(state, rColor),
          _buildPickBanner(state),
          Expanded(child: _buildBody(state)),
          _buildFooter(state),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _buildHeader(PatternEditorState state, Color rColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: rColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.route.displayName,
                style: const TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () => ref.read(patternEditorProvider.notifier).cancel(),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: _textSecondary),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // Pattern name field
          TextField(
            controller: _nameCtrl,
            focusNode: _nameFocus,
            onChanged: (v) => ref.read(patternEditorProvider.notifier).setPatternName(v),
            style: const TextStyle(color: _textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Nombre del trayecto (ej: Ida)',
              hintStyle: const TextStyle(color: Color(0xFF4A5568), fontSize: 12),
              filled: true,
              fillColor: _surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _accent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickBanner(PatternEditorState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: _accent.withOpacity(0.12),
      child: Row(children: [
        Icon(Icons.touch_app, size: 13, color: _accent.withOpacity(0.9)),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Haz clic en las paradas del mapa para añadirlas al trayecto',
            style: TextStyle(color: Color(0xFF80CBC4), fontSize: 11),
          ),
        ),
      ]),
    );
  }

  Widget _buildBody(PatternEditorState state) {
    if (state.stops.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No hay paradas aún.\nHaz clic en el mapa para añadir.',
            style: TextStyle(color: _textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: state.stops.length,
      onReorder: (oldIdx, newIdx) =>
          ref.read(patternEditorProvider.notifier).reorderStops(oldIdx, newIdx),
      itemBuilder: (_, index) {
        final stop = state.stops[index];
        final timeSec = state.timesFromOriginSeconds[index];
        return _StopRow(
          key: ValueKey(stop.id * 1000 + index),
          index: index,
          stop: stop,
          timeCtrl: _ctrl(index, timeSec),
          isFirst: index == 0,
          onRemove: () =>
              ref.read(patternEditorProvider.notifier).removeStop(index),
          onTimeChanged: (text) {
            final sec = _mmSsToSeconds(text);
            ref.read(patternEditorProvider.notifier).setTimeFromOrigin(index, sec);
          },
        );
      },
    );
  }

  Widget _buildFooter(PatternEditorState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shape button
          OutlinedButton.icon(
            onPressed: state.isCalculatingShape || state.stops.length < 2
                ? null
                : () => ref.read(patternEditorProvider.notifier).calculateShape(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withOpacity(state.stops.length < 2 ? 0.3 : 0.7)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            icon: state.isCalculatingShape
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                : Icon(Icons.route, size: 14, color: _accent.withOpacity(state.stops.length < 2 ? 0.3 : 1.0)),
            label: Text(
              state.isCalculatingShape ? 'Calculando…' : (state.shapePoints.isEmpty ? 'Calcular shape (OSRM)' : 'Recalcular shape'),
              style: TextStyle(fontSize: 12, color: _accent.withOpacity(state.stops.length < 2 ? 0.3 : 1.0)),
            ),
          ),

          if (state.shapePoints.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.check_circle, size: 12, color: Colors.green),
              const SizedBox(width: 4),
              Text('${state.shapePoints.length} puntos de shape', style: const TextStyle(color: Colors.green, fontSize: 11)),
            ]),
          ],

          if (state.error != null) ...[
            const SizedBox(height: 4),
            Text(state.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          ],

          const SizedBox(height: 8),

          // Save
          FilledButton.icon(
            onPressed: state.isSaving || state.stops.isEmpty
                ? null
                : () async {
                    final saved = await ref.read(patternEditorProvider.notifier).save();
                    if (saved != null && context.mounted) {
                      // Bust the map's shape + route-to-shape caches so the
                      // newly saved shape appears immediately.
                      ref.read(shapeCacheVersionProvider.notifier).state++;
                      ref.read(patternCacheVersionProvider.notifier).state++;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        backgroundColor: const Color(0xFF0D5C47),
                        content: Row(children: [
                          const Icon(Icons.check_circle, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Trayecto "${saved.displayName}" guardado', style: const TextStyle(color: Colors.white))),
                        ]),
                      ));
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: state.isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: Text(state.isSaving ? 'Guardando…' : 'Guardar trayecto', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual stop row in the list
// ---------------------------------------------------------------------------

class _StopRow extends StatelessWidget {
  final int index;
  final StopModel stop;
  final TextEditingController timeCtrl;
  final bool isFirst;
  final VoidCallback onRemove;
  final ValueChanged<String> onTimeChanged;

  const _StopRow({
    super.key,
    required this.index,
    required this.stop,
    required this.timeCtrl,
    required this.isFirst,
    required this.onRemove,
    required this.onTimeChanged,
  });

  static const _bg = Color(0xFF252930);
  static const _border = Color(0xFF2E3340);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFF8B9299);
  static const _accent = Colors.teal;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          // Sequence badge
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          // Stop name
          Expanded(
            child: Text(
              stop.displayName,
              style: const TextStyle(color: _textPrimary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          // Time from origin
          SizedBox(
            width: 54,
            child: TextField(
              controller: timeCtrl,
              readOnly: isFirst,
              onChanged: onTimeChanged,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isFirst ? _textSecondary : _textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: InputDecoration(
                hintText: isFirst ? '00:00' : 'mm:ss',
                hintStyle: const TextStyle(color: Color(0xFF4A5568), fontSize: 11),
                filled: true,
                fillColor: const Color(0xFF1A1E26),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: _accent)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Remove
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.remove_circle_outline, size: 14, color: Colors.redAccent),
            ),
          ),
          // Drag handle (auto-provided by ReorderableListView via ReorderableDragStartListener)
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.drag_handle, size: 14, color: Color(0xFF4A5568)),
            ),
          ),
        ],
      ),
    );
  }
}
