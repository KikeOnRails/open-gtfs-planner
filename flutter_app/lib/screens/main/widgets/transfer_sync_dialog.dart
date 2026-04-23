import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/transfer_sync_algorithm.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/simulation_providers.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> showTransferSyncDialog(
    BuildContext context, WidgetRef ref, StopModel stop) async {
  final services = await ref.read(activeServicesProvider.future);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _TransferSyncDialog(
        stop: stop,
        serviceIds: services.map((s) => s.serviceId).toList(),
        simDateTime: ref.read(simulationTimeProvider).dateTime,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _TransferSyncDialog extends ConsumerStatefulWidget {
  final StopModel stop;
  final List<String> serviceIds;
  final DateTime simDateTime;

  const _TransferSyncDialog({
    required this.stop,
    required this.serviceIds,
    required this.simDateTime,
  });

  @override
  ConsumerState<_TransferSyncDialog> createState() =>
      _TransferSyncDialogState();
}

class _TransferSyncDialogState extends ConsumerState<_TransferSyncDialog>
    with SingleTickerProviderStateMixin {
  // Data
  List<RouteModel>? _routes;
  List<StopTimeModel>? _stopTimes;
  bool _loading = true;

  // Active lines (selected for synchronisation)
  Set<int> _activeRouteIds = {};

  // Pinned (reference) lines — their schedule is kept as-is; others adapt.
  Set<int> _fixedRouteIds = {};

  // Algorithm result
  SyncResult? _result;
  List<RouteModel> _orderedRoutes = []; // order used in the last optimization
  bool _running = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _load();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final routes = await GtfsRepository.getRoutesForStop(
        widget.stop.id, widget.serviceIds);
    final stopTimes = await GtfsRepository.getStopTimesByStop(
        widget.stop.id, widget.serviceIds, widget.simDateTime);
    if (mounted) {
      setState(() {
        _routes = routes;
        _stopTimes = stopTimes;
        _loading = false;
        // Activate all routes by default
        _activeRouteIds = routes.map((r) => r.id).toSet();
        // Pin the first route as reference by default
        _fixedRouteIds = routes.isNotEmpty ? {routes.first.id} : {};
      });
    }
  }

  // ---- Helpers ------------------------------------------------------------

  List<StopTimeModel> _timesForRoute(RouteModel route) {
    if (_stopTimes == null) return [];
    return _stopTimes!
        .where((st) => st.trip?.route?.id == route.id)
        .toList()
      ..sort((a, b) => a
          .getArrivalTimeInDate(widget.simDateTime)
          .compareTo(b.getArrivalTimeInDate(widget.simDateTime)));
  }

  List<RouteModel> get _activeRoutes =>
      (_routes ?? []).where((r) => _activeRouteIds.contains(r.id)).toList();

  Color _routeColor(RouteModel route) {
    try {
      final hex = route.hexColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppTheme.primary;
    }
  }

  // ---- Algorithm ----------------------------------------------------------

  Future<void> _runOptimization() async {
    final active = _activeRoutes;
    if (active.length < 2) return;

    setState(() => _running = true);

    // Build LineScheduleData for each active route.
    // Fixed (pinned) routes go first so the algorithm treats them as
    // reference lines (shift = 0). Non-fixed routes are optimised around them.
    final fixed = active.where((r) => _fixedRouteIds.contains(r.id)).toList();
    final free  = active.where((r) => !_fixedRouteIds.contains(r.id)).toList();
    final ordered = [...fixed, ...free];

    final schedules = ordered.map((r) {
      return TransferSyncAlgorithm.buildLineSchedule(
        r,
        _timesForRoute(r),
        widget.simDateTime,
      );
    }).toList();

    // The fixed indices correspond to the positions of fixed routes in `ordered`
    final fixedIndices = <int>{};
    for (int i = 0; i < ordered.length; i++) {
      if (_fixedRouteIds.contains(ordered[i].id)) fixedIndices.add(i);
    }

    // Run in the same isolate (fast enough for typical headways)
    final result = TransferSyncAlgorithm.optimize(
      schedules,
      fixedIndices: fixedIndices,
    );

    if (mounted) {
      setState(() {
        _result = result;
        _orderedRoutes = ordered;
        _running = false;
      });
      _fadeController.forward(from: 0);
    }
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 860),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              )
            else if (_routes == null || _routes!.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No se encontraron líneas para esta parada\nen los servicios activos.',
                      style: TextStyle(
                          color: AppTheme.onSurfaceVariant, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLinesSelector(),
                      const SizedBox(height: 16),
                      _buildCurrentScheduleSection(),
                      const SizedBox(height: 16),
                      _buildOptimizeButton(),
                      if (_result != null) ...[
                        const SizedBox(height: 20),
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: _buildResultSection(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- Header -------------------------------------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.sync_alt_rounded,
                color: Color(0xFF7C3AED), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sincronización de horarios',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.onSurface,
                  ),
                ),
                Text(
                  widget.stop.displayName,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close,
                  size: 18, color: AppTheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Lines selector -----------------------------------------------------

  Widget _buildLinesSelector() {
    final routes = _routes ?? [];

    return _SectionCard(
      icon: Icons.route_outlined,
      title: 'Líneas en esta parada',
      subtitle:
          'Activa las líneas a cadenciar (≥ 2). Fija 📌 las que deben mantener su horario.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: routes.map((r) {
          final active = _activeRouteIds.contains(r.id);
          final fixed  = _fixedRouteIds.contains(r.id);
          final color  = _routeColor(r);
          return _LineChip(
            route: r,
            color: color,
            active: active,
            fixed: fixed,
            headway: _detectedHeadway(r),
            onToggle: () {
              setState(() {
                if (active) {
                  _activeRouteIds.remove(r.id);
                  _fixedRouteIds.remove(r.id);
                } else {
                  _activeRouteIds.add(r.id);
                }
                _result = null;
              });
            },
            onToggleFixed: active
                ? () {
                    setState(() {
                      if (fixed) {
                        _fixedRouteIds.remove(r.id);
                      } else {
                        _fixedRouteIds.add(r.id);
                      }
                      _result = null;
                    });
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }

  int _detectedHeadway(RouteModel route) {
    final times = _timesForRoute(route);
    if (times.isEmpty) return 0;
    final arrivals = times
        .map((st) {
          final dt = st.getArrivalTimeInDate(widget.simDateTime);
          return dt.hour * 60 + dt.minute;
        })
        .toList()
      ..sort();
    return TransferSyncAlgorithm.detectHeadway(arrivals);
  }

  // ---- Current schedule section ------------------------------------------

  Widget _buildCurrentScheduleSection() {
    final active = _activeRoutes;
    if (active.isEmpty) return const SizedBox.shrink();

    // Full-day arrivals (all trips, no window filter)
    final Map<int, List<int>> arrivalsByRoute = {};
    for (final r in active) {
      final times = _timesForRoute(r);
      arrivalsByRoute[r.id] = times
          .map((st) {
            final dt = st.getArrivalTimeInDate(widget.simDateTime);
            return dt.hour * 60 + dt.minute;
          })
          .toList()
        ..sort();
    }

    return _SectionCard(
      icon: Icons.schedule_outlined,
      title: 'Horario actual',
      subtitle: 'Todos los pasos del día ordenados por hora.',
      child: _DayScheduleTable(
        routes: active,
        arrivalsByRoute: arrivalsByRoute,
        routeColor: _routeColor,
        highlightFromMinute:
            widget.simDateTime.hour * 60 + widget.simDateTime.minute,
      ),
    );
  }

  // ---- Optimize button ----------------------------------------------------

  Widget _buildOptimizeButton() {
    final canRun = _activeRoutes.length >= 2;

    return Center(
      child: FilledButton.icon(
        onPressed: canRun && !_running ? _runOptimization : null,
        icon: _running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white),
              )
            : const Icon(Icons.auto_fix_high_rounded, size: 16),
        label: Text(
          _running
              ? 'Calculando…'
              : canRun
                  ? 'Calcular sincronización óptima'
                  : 'Selecciona al menos 2 líneas',
        ),
        style: FilledButton.styleFrom(
          backgroundColor: canRun
              ? const Color(0xFF7C3AED)
              : AppTheme.surfaceVariant,
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ---- Result section ------------------------------------------------------

  Widget _buildResultSection() {
    final result = _result!;
    final active = _orderedRoutes; // preserves fixed-first order
    final simMin = widget.simDateTime.hour * 60 + widget.simDateTime.minute;

    // Full-day optimised arrivals per route
    final Map<int, List<int>> optimisedArrivals = {};
    final Map<int, int> shiftByRouteId = {};
    for (int i = 0; i < active.length; i++) {
      final r = active[i];
      final shift = result.suggestions[i].shiftMinutes;
      shiftByRouteId[r.id] = shift;
      final times = _timesForRoute(r);
      optimisedArrivals[r.id] = times
          .map((st) {
            final dt = st.getArrivalTimeInDate(widget.simDateTime);
            return dt.hour * 60 + dt.minute + shift;
          })
          .toList()
        ..sort();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- KPI comparison ---
        _buildKpiRow(result),
        const SizedBox(height: 16),

        // --- Suggestions list ---
        _SectionCard(
          icon: Icons.tips_and_updates_outlined,
          title: 'Modificaciones propuestas',
          subtitle:
              'Desplazamientos de horario por línea para maximizar el hueco mínimo.',
          child: Column(
            children: result.suggestions.map((s) {
              return _SuggestionRow(
                suggestion: s,
                color: _routeColor(s.route),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // --- Full-day optimised schedule ---
        _SectionCard(
          icon: Icons.auto_graph_outlined,
          title: 'Horario optimizado',
          subtitle:
              'Todos los pasos del día aplicando los desplazamientos propuestos.',
          child: _DayScheduleTable(
            routes: active,
            arrivalsByRoute: optimisedArrivals,
            routeColor: _routeColor,
            shiftByRouteId: shiftByRouteId,
            highlightFromMinute: simMin,
          ),
        ),
        const SizedBox(height: 16),

        // --- Periodic window visualisation ---
        _SectionCard(
          icon: Icons.repeat_rounded,
          title: 'Ventana periódica (${result.windowMinutes} min)',
          subtitle:
              'Distribución dentro de un ciclo completo según frecuencias detectadas.',
          child: _PeriodicTimeline(result: result, routeColor: _routeColor),
        ),
      ],
    );
  }

  Widget _buildKpiRow(SyncResult result) {
    final origMin = result.originalMinGapMinutes;
    final optMin = result.optimizedMinGapMinutes;
    final origRange = result.originalGapRange;
    final optRange = result.optimizedGapRange;
    final improved = result.isImproved;
    final moreUniform = result.uniformityImprovement > 0.5;

    return Column(
      children: [
        // --- Row 1: minimum gap ------------------------------------------
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Hueco mínimo actual',
                value: '${origMin.toStringAsFixed(1)} min',
                icon: Icons.warning_amber_rounded,
                color: _gapColor(origMin),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                improved
                    ? Icons.arrow_forward_rounded
                    : Icons.remove_rounded,
                color: improved
                    ? AppTheme.primary
                    : AppTheme.onSurfaceVariant,
                size: 16,
              ),
            ),
            Expanded(
              child: _KpiCard(
                label: 'Hueco mínimo óptimo',
                value: '${optMin.toStringAsFixed(1)} min',
                icon: Icons.check_circle_outline_rounded,
                color: _gapColor(optMin),
                highlight: improved,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // --- Row 2: gap range (uniformity) -------------------------------
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Dispersión actual',
                value: '${origRange.toStringAsFixed(1)} min',
                icon: Icons.unfold_more_rounded,
                color: _gapColor(origRange == 0
                    ? 15
                    : origRange < 5
                        ? 12
                        : origRange < 15
                            ? 6
                            : 0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                moreUniform
                    ? Icons.arrow_forward_rounded
                    : Icons.remove_rounded,
                color: moreUniform
                    ? AppTheme.primary
                    : AppTheme.onSurfaceVariant,
                size: 16,
              ),
            ),
            Expanded(
              child: _KpiCard(
                label: 'Dispersión óptima',
                value: '${optRange.toStringAsFixed(1)} min',
                icon: Icons.unfold_less_rounded,
                color: _gapColor(optRange == 0
                    ? 15
                    : optRange < 5
                        ? 12
                        : optRange < 15
                            ? 6
                            : 0),
                highlight: moreUniform,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _gapColor(double gap) {
    if (gap >= 10) return AppTheme.primary;
    if (gap >= 4) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: const Border.fromBorderSide(
            BorderSide(color: Color(0xFF2E3340))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppTheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.onSurface)),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2E3340)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ---- Line chip -------------------------------------------------------------

class _LineChip extends StatelessWidget {
  final RouteModel route;
  final Color color;
  final bool active;
  final bool fixed;
  final int headway;
  final VoidCallback onToggle;
  final VoidCallback? onToggleFixed;

  const _LineChip({
    required this.route,
    required this.color,
    required this.active,
    required this.fixed,
    required this.headway,
    required this.onToggle,
    this.onToggleFixed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.only(left: 10, top: 6, bottom: 6, right: 4),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.18) : const Color(0xFF1E2128),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? (fixed ? color : color.withOpacity(0.6))
                : const Color(0xFF3E4450),
            width: fixed ? 2.0 : (active ? 1.5 : 1.0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? color : const Color(0xFF3E4450),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              route.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? color : AppTheme.onSurfaceVariant,
              ),
            ),
            if (headway > 0) ...[
              const SizedBox(width: 6),
              Text(
                'c/${headway}min',
                style: TextStyle(
                  fontSize: 10,
                  color: active
                      ? color.withOpacity(0.7)
                      : AppTheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ],
            const SizedBox(width: 4),
            // ── Visibility indicator ───────────────────────────────────
            Icon(
              active ? Icons.visibility : Icons.visibility_off_outlined,
              size: 12,
              color: active ? color : AppTheme.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            // ── Pin (reference) toggle ─────────────────────────────────
            if (active)
              Tooltip(
                message: fixed
                    ? 'Referencia fijada (toca para liberar)'
                    : 'Fijar como referencia — su horario no cambiará',
                child: GestureDetector(
                  onTap: onToggleFixed,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    child: Icon(
                      fixed ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 13,
                      color: fixed
                          ? color
                          : AppTheme.onSurfaceVariant.withOpacity(0.45),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
// ---- Gap indicator ---------------------------------------------------------

/// A merged, chronologically sorted list of all arrivals for the given routes.
/// [shiftByRouteId] is provided in the optimised view: for each route with a
/// non-zero shift the row shows the original time and a +/- delta badge.
/// [highlightFromMinute] marks a horizontal divider at the current sim time.
class _DayScheduleTable extends StatelessWidget {
  final List<RouteModel> routes;
  final Map<int, List<int>> arrivalsByRoute;
  final Color Function(RouteModel) routeColor;
  final Map<int, int>? shiftByRouteId;
  final int highlightFromMinute;

  const _DayScheduleTable({
    required this.routes,
    required this.arrivalsByRoute,
    required this.routeColor,
    this.shiftByRouteId,
    this.highlightFromMinute = -1,
  });

  // ---- Gap colouring -------------------------------------------------------
  static Color _gapColor(int gapMin) {
    if (gapMin >= 10) return const Color(0xFF34D399); // green
    if (gapMin >= 4) return const Color(0xFFF59E0B);  // amber
    return const Color(0xFFEF4444);                    // red
  }

  @override
  Widget build(BuildContext context) {
    // Build merged sorted list
    final events = <_ScheduleEvent>[];
    for (final r in routes) {
      final arrivals = arrivalsByRoute[r.id] ?? [];
      final shift = shiftByRouteId?[r.id] ?? 0;
      for (final m in arrivals) {
        events.add(_ScheduleEvent(
            displayMinutes: m, originalMinutes: m - shift, route: r, shift: shift));
      }
    }
    events.sort((a, b) => a.displayMinutes.compareTo(b.displayMinutes));

    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('Sin datos para mostrar.',
              style: TextStyle(
                  color: AppTheme.onSurfaceVariant, fontSize: 12)),
        ),
      );
    }

    // Pre-compute inter-expedition gap for each event (null for the first)
    final gaps = List<int?>.filled(events.length, null);
    for (int i = 1; i < events.length; i++) {
      gaps[i] = events[i].displayMinutes - events[i - 1].displayMinutes;
    }

    // Find the index just after highlightFromMinute ("now" divider)
    int nowIndex = events.indexWhere((e) => e.displayMinutes >= highlightFromMinute);
    if (nowIndex < 0) nowIndex = events.length;

    final hasShiftCol = shiftByRouteId != null &&
        shiftByRouteId!.values.any((s) => s != 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Header row ---------------------------------------------------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF1E2230),
            border: Border(bottom: BorderSide(color: Color(0xFF2E3340))),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 48,
                child: Text('Hora', style: _headerStyle),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 76,
                child: Text('Línea', style: _headerStyle),
              ),
              const SizedBox(width: 8),
              const Expanded(
                flex: 2,
                child: Text('Espera desde anterior',
                    style: _headerStyle),
              ),
              if (hasShiftCol)
                const SizedBox(
                  width: 100,
                  child: Text('Desplazamiento', style: _headerStyle),
                ),
            ],
          ),
        ),
        // ---- Rows ---------------------------------------------------------
        SizedBox(
          height: 300,
          child: ListView.builder(
            itemCount: events.length +
                (nowIndex > 0 && nowIndex < events.length ? 1 : 0),
            itemBuilder: (ctx, idx) {
              final hasDivider = nowIndex > 0 && nowIndex < events.length;
              final dividerIdx = hasDivider ? nowIndex : -1;

              if (hasDivider && idx == dividerIdx) {
                return _NowDivider(minute: highlightFromMinute);
              }
              final eventIdx =
                  hasDivider && idx > dividerIdx ? idx - 1 : idx;
              final e = events[eventIdx];
              final gap = gaps[eventIdx];
              final color = routeColor(e.route);
              final isPast = e.displayMinutes < highlightFromMinute;
              final hasShift = e.shift != 0;
              final opacity = isPast ? 0.38 : 1.0;

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: Color(0xFF24283A), width: 1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // --- Time ----------------------------------------------
                    SizedBox(
                      width: 48,
                      child: Text(
                        _fmt(e.displayMinutes),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: (isPast
                                  ? AppTheme.onSurfaceVariant
                                  : AppTheme.onSurface)
                              .withOpacity(opacity),
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // --- Route badge ---------------------------------------
                    SizedBox(
                      width: 76,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(isPast ? 0.05 : 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: color.withOpacity(isPast ? 0.15 : 0.5)),
                        ),
                        child: Text(
                          e.route.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: color.withOpacity(opacity),
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // --- Gap from previous arrival -------------------------
                    Expanded(
                      flex: 2,
                      child: gap == null
                          ? const SizedBox.shrink()
                          : Row(
                              children: [
                                // Colour bar
                                Container(
                                  width: 3,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: _gapColor(gap)
                                        .withOpacity(isPast ? 0.25 : 0.85),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '+${gap}min',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _gapColor(gap)
                                        .withOpacity(isPast ? 0.35 : 0.9),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    // --- Shift badge (optimised view only) ----------------
                    if (hasShiftCol)
                      SizedBox(
                        width: 100,
                        child: hasShift
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    _fmt(e.originalMinutes),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.onSurfaceVariant
                                          .withOpacity(
                                              isPast ? 0.3 : 0.6),
                                      decoration:
                                          TextDecoration.lineThrough,
                                      decorationColor:
                                          AppTheme.onSurfaceVariant
                                              .withOpacity(0.4),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (e.shift > 0
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF60A5FA))
                                          .withOpacity(isPast ? 0.06 : 0.18),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      e.shift > 0
                                          ? '+${e.shift}m'
                                          : '${e.shift}m',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: (e.shift > 0
                                                ? const Color(0xFFF59E0B)
                                                : const Color(0xFF60A5FA))
                                            .withOpacity(
                                                isPast ? 0.4 : 1.0),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static const _headerStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppTheme.onSurfaceVariant,
    letterSpacing: 0.5,
  );

  static String _fmt(int m) {
    final h = ((m ~/ 60) % 24).toString().padLeft(2, '0');
    final min = (m % 60).toString().padLeft(2, '0');
    return '$h:$min';
  }
}

class _ScheduleEvent {
  final int displayMinutes;
  final int originalMinutes;
  final RouteModel route;
  final int shift;

  const _ScheduleEvent({
    required this.displayMinutes,
    required this.originalMinutes,
    required this.route,
    required this.shift,
  });
}

class _NowDivider extends StatelessWidget {
  final int minute;
  const _NowDivider({required this.minute});

  @override
  Widget build(BuildContext context) {
    final h = ((minute ~/ 60) % 24).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Ahora · $h:$m',
              style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          const Expanded(
              child: Divider(color: AppTheme.primary, thickness: 0.8)),
        ],
      ),
    );
  }
}

// ---- KPI card --------------------------------------------------------------

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool highlight;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: highlight ? color : color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                fontSize: 10, color: AppTheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---- Suggestion row --------------------------------------------------------

class _SuggestionRow extends StatelessWidget {
  final SyncLineSuggestion suggestion;
  final Color color;

  const _SuggestionRow({
    required this.suggestion,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isRef = suggestion.shiftMinutes == 0;
    final shift = suggestion.shiftMinutes;
    final absShift = shift.abs();
    final icon = isRef
        ? Icons.push_pin_outlined
        : shift > 0
            ? Icons.arrow_forward_rounded
            : Icons.arrow_back_rounded;
    final shiftColor = isRef
        ? AppTheme.onSurfaceVariant
        : shift > 0
            ? const Color(0xFFF59E0B)
            : const Color(0xFF60A5FA);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Color dot
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          // Route name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.route.displayName,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface),
                ),
                Text(
                  'Frecuencia: ${suggestion.headwayMinutes} min',
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Shift badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: shiftColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: shiftColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: shiftColor),
                const SizedBox(width: 4),
                Text(
                  isRef
                      ? 'Referencia (sin cambio)'
                      : '${shift > 0 ? "Retrasar" : "Adelantar"} $absShift min',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: shiftColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Periodic timeline (full window) ----------------------------------------

class _PeriodicTimeline extends StatefulWidget {
  final SyncResult result;
  final Color Function(RouteModel) routeColor;

  const _PeriodicTimeline({
    required this.result,
    required this.routeColor,
  });

  @override
  State<_PeriodicTimeline> createState() => _PeriodicTimelineState();
}

class _PeriodicTimelineState extends State<_PeriodicTimeline> {
  /// How many full cycles to render side-by-side.
  static const int _cycles = 3;

  double _zoom = 1.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 8.0;

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  SyncResult get result => widget.result;
  Color Function(RouteModel) get routeColor => widget.routeColor;

  static List<double> _gaps(List<SyncEvent> events, int window) {
    if (events.length < 2) return [];
    final gaps = <double>[];
    for (int i = 1; i < events.length; i++) {
      gaps.add(
          (events[i].minuteInWindow - events[i - 1].minuteInWindow).toDouble());
    }
    final wrap = (window - events.last.minuteInWindow +
            events.first.minuteInWindow)
        .toDouble();
    gaps.add(wrap);
    return gaps;
  }

  Widget _dashed(Color color) {
    return SizedBox(
      width: 28,
      height: 2,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = result.windowMinutes;
    final origGaps = _gaps(result.originalEvents, w);
    final optGaps = _gaps(result.optimizedEvents, w);
    final ideal = w / result.suggestions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Legend ──────────────────────────────────────────────────────
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: result.suggestions.map((s) {
            final color = routeColor(s.route);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 4,
                          spreadRadius: 1)
                    ],
                  ),
                  child: Center(
                    child: Text(
                      s.route.displayName.isNotEmpty
                          ? s.route.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(s.route.displayName,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.onSurface)),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 6),

        // ── Ideal spacing info + zoom controls ──────────────────────────
        Row(
          children: [
            _dashed(AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Distribución ideal: cada ${ideal.toStringAsFixed(1)} min  '
                '· Mostrando $_cycles ciclos (${w * _cycles} min)',
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.onSurfaceVariant),
              ),
            ),
            // ── Zoom controls ──────────────────────────────────────────
            _ZoomControls(
              zoom: _zoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onZoomIn: () => setState(
                  () => _zoom = (_zoom * 1.5).clamp(_minZoom, _maxZoom)),
              onZoomOut: () => setState(
                  () => _zoom = (_zoom / 1.5).clamp(_minZoom, _maxZoom)),
              onReset: () => setState(() => _zoom = 1.0),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Rows: labels pinned left, painters scroll, trailing pinned right ─
        LayoutBuilder(builder: (ctx, constraints) {
          const labelW = 52.0;
          const trailW = 38.0;
          const rowGap = 6.0;
          final availW = (constraints.maxWidth - labelW - trailW - rowGap)
              .clamp(0.0, double.infinity);
          final painterW = availW * _zoom;

          final trailingLabel = Text(
            '${w * _cycles}min',
            style: const TextStyle(fontSize: 9, color: AppTheme.onSurfaceVariant),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Pinned labels column ───────────────────────────────
              SizedBox(
                width: labelW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Antes" vertically centred to the 60px painter
                    SizedBox(
                      height: 60,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Antes',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onSurfaceVariant)),
                      ),
                    ),
                    const SizedBox(height: 4 + 24 + 16), // gap + GapSummaryRow + spacer
                    SizedBox(
                      height: 60,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Después',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary)),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Scrollable painters column ─────────────────────────
              Expanded(
                child: Scrollbar(
                  controller: _scrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: painterW,
                          height: 60,
                          child: CustomPaint(
                            painter: _PeriodicPainter(
                              events: result.originalEvents,
                              gaps: origGaps,
                              window: w,
                              cycles: _cycles,
                              ideal: ideal,
                              routeColor: routeColor,
                              highlight: false,
                              anchorMinute: result.windowAnchorMinute,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: painterW,
                          child: _GapSummaryRow(gaps: origGaps, ideal: ideal),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: painterW,
                          height: 60,
                          child: CustomPaint(
                            painter: _PeriodicPainter(
                              events: result.optimizedEvents,
                              gaps: optGaps,
                              window: w,
                              cycles: _cycles,
                              ideal: ideal,
                              routeColor: routeColor,
                              highlight: true,
                              anchorMinute: result.windowAnchorMinute,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: painterW,
                          child: _GapSummaryRow(
                              gaps: optGaps,
                              ideal: ideal,
                              showImprovement: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Pinned trailing column ─────────────────────────────
              SizedBox(
                width: trailW,
                child: Column(
                  children: [
                    SizedBox(
                      height: 60,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: rowGap),
                          child: trailingLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ---- Zoom controls --------------------------------------------------------

class _ZoomControls extends StatelessWidget {
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final atMin = zoom <= minZoom;
    final atMax = zoom >= maxZoom;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ZoomBtn(
          icon: Icons.remove,
          onTap: atMin ? null : onZoomOut,
        ),
        GestureDetector(
          onTap: atMin ? null : onReset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              '${zoom.toStringAsFixed(zoom == 1.0 ? 0 : 1)}×',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: atMin
                    ? AppTheme.onSurfaceVariant.withOpacity(0.4)
                    : AppTheme.primary,
              ),
            ),
          ),
        ),
        _ZoomBtn(
          icon: Icons.add,
          onTap: atMax ? null : onZoomIn,
        ),
      ],
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ZoomBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.primary.withOpacity(0.12)
              : AppTheme.onSurfaceVariant.withOpacity(0.06),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled
              ? AppTheme.primary
              : AppTheme.onSurfaceVariant.withOpacity(0.3),
        ),
      ),
    );
  }
}

/// Compact summary: min gap / max gap / spread shown as chips
class _GapSummaryRow extends StatelessWidget {
  final List<double> gaps;
  final double ideal;
  final bool showImprovement;

  const _GapSummaryRow(
      {required this.gaps,
      required this.ideal,
      this.showImprovement = false});

  @override
  Widget build(BuildContext context) {
    if (gaps.isEmpty) return const SizedBox.shrink();

    final minG = gaps.reduce((a, b) => a < b ? a : b);
    final maxG = gaps.reduce((a, b) => a > b ? a : b);
    final spread = maxG - minG;

    Color spreadColor() {
      if (spread < 2) return const Color(0xFF22C55E);
      if (spread < 8) return const Color(0xFFF59E0B);
      return const Color(0xFFEF4444);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Row(
        children: [
          _GapChip(
            icon: Icons.arrow_downward_rounded,
            label: 'Mín',
            value: '${minG.toStringAsFixed(1)}\'',
            color: minG < ideal * 0.6
                ? const Color(0xFFEF4444)
                : const Color(0xFF22C55E),
          ),
          const SizedBox(width: 6),
          _GapChip(
            icon: Icons.arrow_upward_rounded,
            label: 'Máx',
            value: '${maxG.toStringAsFixed(1)}\'',
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 6),
          _GapChip(
            icon: Icons.unfold_more_rounded,
            label: 'Dispersión',
            value: '${spread.toStringAsFixed(1)}\'',
            color: spreadColor(),
          ),
        ],
      ),
    );
  }
}

class _GapChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _GapChip(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 9,
                  color: color.withOpacity(0.75))),
          Text(value,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

class _PeriodicPainter extends CustomPainter {
  final List<SyncEvent> events;
  final List<double> gaps;
  final int window;
  final int cycles;
  final double ideal;
  final Color Function(RouteModel) routeColor;
  final bool highlight;
  /// Real minute-of-day (0–1439) that corresponds to position 0 of the window.
  final int anchorMinute;

  const _PeriodicPainter({
    required this.events,
    required this.gaps,
    required this.window,
    required this.cycles,
    required this.ideal,
    required this.routeColor,
    required this.highlight,
    required this.anchorMinute,
  });

  static const double _trackH = 6;
  static const double _dotR = 9;
  static const double _trackY = 38;
  static const double _labelY = 16;

  /// Formats a minute-of-day as HH:mm.
  static String _hhmm(int minuteOfDay) {
    final m = minuteOfDay % (24 * 60);
    final h = m ~/ 60;
    final min = m % 60;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (events.isEmpty) return;

    final totalWindow = window * cycles;

    // ── Track background ────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, _trackY - _trackH / 2, size.width, _trackH),
        const Radius.circular(3),
      ),
      Paint()
        ..color = (highlight ? AppTheme.primary : AppTheme.onSurfaceVariant)
            .withOpacity(0.10)
        ..style = PaintingStyle.fill,
    );

    // ── Ideal spacing dashed guide ──────────────────────────────────────
    final dashPaint = Paint()
      ..color = AppTheme.primary.withOpacity(0.20)
      ..strokeWidth = 1;
    double idealPx = ideal / totalWindow * size.width;
    double dxPos = idealPx;
    while (dxPos < size.width - 4) {
      canvas.drawLine(
          Offset(dxPos, _trackY), Offset(dxPos + 4, _trackY), dashPaint);
      dxPos += idealPx;
    }

    // ── Expand events across all cycles ─────────────────────────────────
    final allEvents = <({double x, Color color, String label})>[];
    for (int c = 0; c < cycles; c++) {
      for (final e in events) {
        final minute = e.minuteInWindow + c * window;
        final x = minute / totalWindow * size.width;
        final rawName = e.route.displayName.isNotEmpty
            ? e.route.displayName.toUpperCase()
            : '?';
        // Keep up to 4 characters so short names like "R12" fit in the dot
        final label = rawName.length > 4 ? rawName.substring(0, 4) : rawName;
        allEvents.add((
          x: x,
          color: routeColor(e.route),
          label: label,
        ));
      }
    }
    allEvents.sort((a, b) => a.x.compareTo(b.x));

    // ── Gap spans and labels ─────────────────────────────────────────────
    for (int i = 0; i < allEvents.length - 1; i++) {
      final x1 = allEvents[i].x;
      final x2 = allEvents[i + 1].x;
      final gMin = (x2 - x1) / size.width * totalWindow;

      Color spanColor;
      if (gMin < ideal * 0.7) {
        spanColor = const Color(0xFFEF4444);
      } else if (gMin > ideal * 1.4) {
        spanColor = const Color(0xFFF59E0B);
      } else {
        spanColor = const Color(0xFF22C55E);
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              x1 + 1, _trackY - _trackH / 2, x2 - x1 - 2, _trackH),
          const Radius.circular(2),
        ),
        Paint()
          ..color = spanColor.withOpacity(0.22)
          ..style = PaintingStyle.fill,
      );

      if (x2 - x1 >= 20) {
        final gStr =
            '${gMin.toStringAsFixed(gMin.truncateToDouble() == gMin ? 0 : 1)}\'';
        final mid = (x1 + x2) / 2;
        final tp = TextPainter(
          text: TextSpan(
            text: gStr,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: spanColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid - tp.width / 2, _labelY - tp.height / 2));
      }
    }

    // ── Cycle dividers ───────────────────────────────────────────────────
    final divPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1;
    for (int c = 1; c < cycles; c++) {
      final x = c / cycles * size.width;
      double y = 0;
      while (y < size.height - 3) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 4), divPaint);
        y += 7;
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${c * window}\'',
          style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.30)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, _trackY + _trackH / 2 + 4));
    }

    // ── Event dots ──────────────────────────────────────────────────────
    for (final e in allEvents) {
      // Scale dot radius and font size based on label length
      final len = e.label.length;
      final dotR = len <= 1 ? _dotR : (len == 2 ? _dotR + 1.5 : _dotR + 3.0);
      final fontSize = len <= 1 ? 9.0 : (len == 2 ? 7.5 : (len == 3 ? 6.5 : 5.5));
      canvas.drawCircle(Offset(e.x, _trackY), dotR + 3,
          Paint()
            ..color = e.color.withOpacity(0.15)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(Offset(e.x, _trackY), dotR,
          Paint()
            ..color = e.color
            ..style = PaintingStyle.fill);
      final tp = TextPainter(
        text: TextSpan(
          text: e.label,
          style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(e.x - tp.width / 2, _trackY - tp.height / 2));
    }

    // ── Axis ticks & HH:mm labels ────────────────────────────────────────
    //
    // Draw one tick per headway cycle boundary across the full display window.
    // Each boundary at position p minutes → real time = anchorMinute + p.
    // Minimum pixel gap between ticks so labels never overlap.
    const minTickPx = 46.0;
    final axisPaint = Paint()
      ..color = AppTheme.onSurfaceVariant.withOpacity(0.28)
      ..strokeWidth = 1;
    final tickStyle = TextStyle(
      fontSize: 8,
      color: AppTheme.onSurfaceVariant.withOpacity(0.7),
    );

    double lastLabelEnd = -minTickPx;
    for (int t = 0; t <= totalWindow; t += window) {
      final x = t / totalWindow * size.width;
      // Tick line
      canvas.drawLine(
          Offset(x, _trackY - 6), Offset(x, _trackY + 6), axisPaint);
      // Label
      final label = _hhmm(anchorMinute + t);
      final tp = TextPainter(
        text: TextSpan(text: label, style: tickStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      if (labelX > lastLabelEnd) {
        tp.paint(canvas, Offset(labelX, _trackY + _trackH / 2 + 4));
        lastLabelEnd = labelX + tp.width + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_PeriodicPainter old) =>
      old.events != events || old.gaps != gaps || old.cycles != cycles ||
      old.anchorMinute != anchorMinute;
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + 4).clamp(0, size.width), size.height / 2), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
