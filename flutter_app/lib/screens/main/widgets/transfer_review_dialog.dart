import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/simulation_providers.dart';

// ---------------------------------------------------------------------------
// Entry point: open the dialog
// ---------------------------------------------------------------------------

Future<void> showTransferReviewDialog(
    BuildContext context, WidgetRef ref, StopModel stop) async {
  final services = await ref.read(activeServicesProvider.future);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _TransferReviewDialog(
        stop: stop,
        serviceIds: services.map((s) => s.serviceId).toList(),
        simDateTime: ref.read(simulationTimeProvider).dateTime,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Stats data class
// ---------------------------------------------------------------------------

class _TransferStats {
  final int totalExpeditions;
  final int withTransfer;
  final int withoutTransfer;
  final double avgWaitMinutes;
  final int maxWaitMinutes;
  final int maxGapMinutes; // longest continuous gap without any transfer
  final double transferPercent;
  // hour (0-23) → best wait minutes for that hour, null = no transfer
  final Map<int, int?> waitByHour;

  const _TransferStats({
    required this.totalExpeditions,
    required this.withTransfer,
    required this.withoutTransfer,
    required this.avgWaitMinutes,
    required this.maxWaitMinutes,
    required this.maxGapMinutes,
    required this.transferPercent,
    required this.waitByHour,
  });
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _TransferReviewDialog extends ConsumerStatefulWidget {
  final StopModel stop;
  final List<String> serviceIds;
  final DateTime simDateTime;

  const _TransferReviewDialog({
    required this.stop,
    required this.serviceIds,
    required this.simDateTime,
  });

  @override
  ConsumerState<_TransferReviewDialog> createState() =>
      _TransferReviewDialogState();
}

class _TransferReviewDialogState extends ConsumerState<_TransferReviewDialog>
    with SingleTickerProviderStateMixin {
  // Data
  List<RouteModel>? _routes;
  List<StopTimeModel>? _stopTimes;
  bool _loading = true;

  // Selection state
  RouteModel? _routeA;
  RouteModel? _routeB;
  int _transferWindowMin = 10;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        if (routes.length >= 1) _routeA = routes.first;
        if (routes.length >= 2) _routeB = routes[1];
      });
    }
  }

  // Stop times for a specific route, sorted by arrival
  List<StopTimeModel> _timesForRoute(RouteModel? route) {
    if (route == null || _stopTimes == null) return [];
    return _stopTimes!
        .where((st) => st.trip?.route?.id == route.id)
        .toList()
      ..sort((a, b) => a
          .getArrivalTimeInDate(widget.simDateTime)
          .compareTo(b.getArrivalTimeInDate(widget.simDateTime)));
  }

  // Given an arrival from Route A, find Route B departures within the window
  List<_TransferOption> _findTransfers(StopTimeModel arrival) {
    if (_routeB == null) return [];
    final arrivalDt = arrival.getArrivalTimeInDate(widget.simDateTime);
    final windowEnd = arrivalDt.add(Duration(minutes: _transferWindowMin));

    return _timesForRoute(_routeB).where((st) {
      final dep = st.getArrivalTimeInDate(widget.simDateTime);
      return (dep.isAfter(arrivalDt) || dep.isAtSameMomentAs(arrivalDt)) &&
          dep.isBefore(windowEnd);
    }).map((st) {
      final dep = st.getArrivalTimeInDate(widget.simDateTime);
      final wait = dep.difference(arrivalDt).inMinutes;
      return _TransferOption(stopTime: st, waitMinutes: wait);
    }).toList();
  }

  // Compute statistics from current selection
  _TransferStats? _computeStats() {
    final timesA = _timesForRoute(_routeA);
    if (timesA.isEmpty || _routeA == null || _routeB == null) return null;

    int withTransfer = 0;
    int totalWait = 0;
    int maxWait = 0;
    final Map<int, int?> waitByHour = {};

    // best wait per expedition
    final List<int?> bestWaits = [];

    for (final arrival in timesA) {
      final transfers = _findTransfers(arrival);
      final hour = arrival.getArrivalTimeInDate(widget.simDateTime).hour;

      if (transfers.isEmpty) {
        bestWaits.add(null);
        // keep null for this hour if no better value
        waitByHour.putIfAbsent(hour, () => null);
      } else {
        final best = transfers
            .map((t) => t.waitMinutes)
            .reduce((a, b) => a < b ? a : b);
        bestWaits.add(best);
        withTransfer++;
        totalWait += best;
        if (best > maxWait) maxWait = best;
        // keep minimum wait per hour
        final prev = waitByHour[hour];
        if (prev == null || best < prev) waitByHour[hour] = best;
      }
    }

    // Max gap: longest consecutive run of arrivals without transfer
    int maxGap = 0;
    int gapStart = 0;
    bool inGap = false;
    for (int i = 0; i < timesA.length; i++) {
      if (bestWaits[i] == null) {
        if (!inGap) {
          gapStart = i;
          inGap = true;
        }
      } else {
        if (inGap) {
          final gapLen = i - gapStart;
          if (gapLen > maxGap) maxGap = gapLen;
          inGap = false;
        }
      }
    }
    if (inGap) {
      final gapLen = timesA.length - gapStart;
      if (gapLen > maxGap) maxGap = gapLen;
    }

    return _TransferStats(
      totalExpeditions: timesA.length,
      withTransfer: withTransfer,
      withoutTransfer: timesA.length - withTransfer,
      avgWaitMinutes: withTransfer > 0 ? totalWait / withTransfer : 0,
      maxWaitMinutes: maxWait,
      maxGapMinutes: maxGap,
      transferPercent:
          timesA.isEmpty ? 0 : withTransfer / timesA.length * 100,
      waitByHour: waitByHour,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
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
                  child: Text(
                    'No se encontraron líneas para esta parada\nen los servicios activos.',
                    style: TextStyle(
                        color: AppTheme.onSurfaceVariant, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              _buildControls(),
              const Divider(height: 1),
              // Tab bar
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.onSurfaceVariant,
                labelStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.bar_chart_outlined, size: 14),
                    text: 'ESTADÍSTICAS',
                  ),
                  Tab(
                    icon: Icon(Icons.list_alt_outlined, size: 14),
                    text: 'EXPEDICIONES',
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStatsTab(),
                    _buildTransferList(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.transfer_within_a_station,
                color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revisión de transbordos',
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

  Widget _buildControls() {
    final routes = _routes!;
    return Container(
      color: AppTheme.surfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _RouteDropdown(
                  label: 'Línea A (llegada)',
                  routes: routes,
                  value: _routeA,
                  exclude: _routeB,
                  onChanged: (r) => setState(() => _routeA = r),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward,
                    color: AppTheme.primary, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RouteDropdown(
                  label: 'Línea B (transbordo)',
                  routes: routes,
                  value: _routeB,
                  exclude: _routeA,
                  onChanged: (r) => setState(() => _routeB = r),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  size: 14, color: AppTheme.onSurfaceVariant),
              const SizedBox(width: 6),
              const Text('Ventana de transbordo:',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Text('$_transferWindowMin min',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  )),
              Expanded(
                child: Slider(
                  value: _transferWindowMin.toDouble(),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  activeColor: AppTheme.primary,
                  inactiveColor: AppTheme.primary.withOpacity(0.2),
                  onChanged: (v) =>
                      setState(() => _transferWindowMin = v.round()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Stats tab
  // -----------------------------------------------------------------------

  Widget _buildStatsTab() {
    final stats = _computeStats();
    if (stats == null) {
      return const Center(
        child: Text('Selecciona las dos líneas para ver las estadísticas.',
            style: TextStyle(
                color: AppTheme.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat cards grid
          _StatsGrid(stats: stats, windowMin: _transferWindowMin),
          const SizedBox(height: 16),
          // Hourly chart
          _HourlyChart(
            waitByHour: stats.waitByHour,
            windowMin: _transferWindowMin,
            routeA: _routeA!,
            routeB: _routeB!,
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Transfer list tab
  // -----------------------------------------------------------------------

  Widget _buildTransferList() {
    final timesA = _timesForRoute(_routeA);
    if (_routeA == null || _routeB == null) {
      return const Center(
        child: Text('Selecciona las dos líneas para ver los transbordos.',
            style: TextStyle(
                color: AppTheme.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center),
      );
    }
    if (timesA.isEmpty) {
      return const Center(
        child: Text(
            'Sin horarios para la Línea A en los servicios activos.',
            style: TextStyle(
                color: AppTheme.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: timesA.length,
      itemBuilder: (_, i) {
        final arrival = timesA[i];
        final transfers = _findTransfers(arrival);
        return _TransferRow(
          arrival: arrival,
          transfers: transfers,
          routeA: _routeA!,
          routeB: _routeB!,
          simDateTime: widget.simDateTime,
          windowMin: _transferWindowMin,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stats grid
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  final _TransferStats stats;
  final int windowMin;

  const _StatsGrid({required this.stats, required this.windowMin});

  @override
  Widget build(BuildContext context) {
    final pct = stats.transferPercent;
    final pctColor = pct >= 80
        ? const Color(0xFF4CAF50)
        : pct >= 50
            ? Colors.orange
            : Colors.redAccent;

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.0,
      children: [
        _StatCard(
          icon: Icons.swap_horiz_rounded,
          label: 'Transbordos posibles',
          value: '${stats.withTransfer}',
          color: AppTheme.primary,
        ),
        _StatCard(
          icon: Icons.block_outlined,
          label: 'Sin transbordo',
          value: '${stats.withoutTransfer}',
          color: stats.withoutTransfer == 0
              ? const Color(0xFF4CAF50)
              : Colors.redAccent,
        ),
        _StatCard(
          icon: Icons.percent_rounded,
          label: 'Cobertura',
          value: '${pct.toStringAsFixed(1)}%',
          color: pctColor,
        ),
        _StatCard(
          icon: Icons.schedule_outlined,
          label: 'Espera media',
          value: stats.withTransfer > 0
              ? '${stats.avgWaitMinutes.toStringAsFixed(1)} min'
              : '—',
          color: AppTheme.onSurface,
        ),
        _StatCard(
          icon: Icons.arrow_upward_rounded,
          label: 'Espera máxima',
          value: stats.withTransfer > 0
              ? '${stats.maxWaitMinutes} min'
              : '—',
          color: stats.maxWaitMinutes >= windowMin * 0.8
              ? Colors.orange
              : AppTheme.onSurface,
        ),
        _StatCard(
          icon: Icons.warning_amber_rounded,
          label: 'Mayor hueco sin transbordo',
          value: stats.maxGapMinutes > 0
              ? '${stats.maxGapMinutes} exp.'
              : 'Ninguno',
          color: stats.maxGapMinutes >= 3
              ? Colors.redAccent
              : stats.maxGapMinutes > 0
                  ? Colors.orange
                  : const Color(0xFF4CAF50),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hourly chart
// ---------------------------------------------------------------------------

class _HourlyChart extends StatelessWidget {
  final Map<int, int?> waitByHour;
  final int windowMin;
  final RouteModel routeA;
  final RouteModel routeB;

  const _HourlyChart({
    required this.waitByHour,
    required this.windowMin,
    required this.routeA,
    required this.routeB,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bar_chart_outlined,
                size: 14, color: AppTheme.onSurfaceVariant),
            const SizedBox(width: 6),
            const Text(
              'Espera mínima por hora del día',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
            ),
            const Spacer(),
            // Legend
            _LegendDot(
                color: const Color(0xFF4CAF50), label: '≤ 33% ventana'),
            const SizedBox(width: 8),
            _LegendDot(color: Colors.orange, label: '≤ 66%'),
            const SizedBox(width: 8),
            _LegendDot(color: Colors.redAccent, label: 'Sin transbordo'),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: const Color(0xFF2E3340).withOpacity(0.5)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CustomPaint(
              painter: _HourlyChartPainter(
                waitByHour: waitByHour,
                windowMin: windowMin,
              ),
              child: Container(),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 9, color: AppTheme.onSurfaceVariant)),
      ],
    );
  }
}

class _HourlyChartPainter extends CustomPainter {
  final Map<int, int?> waitByHour;
  final int windowMin;

  _HourlyChartPainter({
    required this.waitByHour,
    required this.windowMin,
  });

  Color _barColor(int? waitMin) {
    if (waitMin == null) return Colors.redAccent.withOpacity(0.75);
    final ratio = waitMin / windowMin;
    if (ratio <= 0.33) return const Color(0xFF4CAF50).withOpacity(0.85);
    if (ratio <= 0.66) return Colors.orange.withOpacity(0.85);
    return Colors.deepOrange.withOpacity(0.85);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 36.0;
    const rightPad = 8.0;
    const topPad = 10.0;
    const bottomPad = 24.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF2E3340).withOpacity(0.5)
      ..strokeWidth = 0.5;
    final labelStyle = TextStyle(
      color: AppTheme.onSurfaceVariant.withOpacity(0.6),
      fontSize: 9,
    );

    // Y axis labels + grid lines (0, 33%, 66%, max)
    final yValues = [0, windowMin ~/ 3, (windowMin * 2) ~/ 3, windowMin];
    for (final yVal in yValues) {
      final y = topPad + chartH - (yVal / windowMin) * chartH;
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '$yVal', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // Bars — 24 slots
    final barW = chartW / 24;
    const barGap = 1.5;

    final barPaint = Paint();
    final noDataPaint = Paint()
      ..color = const Color(0xFF2E3340).withOpacity(0.3);

    for (int h = 0; h < 24; h++) {
      final x = leftPad + h * barW;
      final hasData = waitByHour.containsKey(h);
      final waitVal = waitByHour[h]; // null = expedition exists but no transfer

      if (!hasData) {
        // No expedition at this hour → faint placeholder
        final rect = Rect.fromLTWH(
            x + barGap / 2, topPad + chartH - 4, barW - barGap, 4);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            noDataPaint);
      } else {
        final barH = waitVal == null
            ? chartH
            : math.max(4.0, (waitVal / windowMin) * chartH);
        final rect = Rect.fromLTWH(
            x + barGap / 2, topPad + chartH - barH, barW - barGap, barH);
        barPaint.color = _barColor(waitVal);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            barPaint);
      }

      // X axis label (every 3h)
      if (h % 3 == 0) {
        final tp = TextPainter(
          text: TextSpan(
              text: '${h.toString().padLeft(2, '0')}h', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(x + barW / 2 - tp.width / 2, topPad + chartH + 6));
      }
    }

    // Y axis line
    canvas.drawLine(Offset(leftPad, topPad),
        Offset(leftPad, topPad + chartH), gridPaint);
  }

  @override
  bool shouldRepaint(_HourlyChartPainter old) =>
      old.waitByHour != waitByHour || old.windowMin != windowMin;
}

// ---------------------------------------------------------------------------
// Route dropdown
// ---------------------------------------------------------------------------

class _RouteDropdown extends StatelessWidget {
  final String label;
  final List<RouteModel> routes;
  final RouteModel? value;
  final RouteModel? exclude;
  final ValueChanged<RouteModel?> onChanged;

  const _RouteDropdown({
    required this.label,
    required this.routes,
    required this.value,
    required this.exclude,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final available = routes.where((r) => r.id != exclude?.id).toList();
    final currentValue =
        available.any((r) => r.id == value?.id) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E3340)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<RouteModel>(
              value: currentValue,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceVariant,
              style: const TextStyle(fontSize: 12, color: AppTheme.onSurface),
              hint: const Text('Seleccionar línea',
                  style: TextStyle(
                      color: AppTheme.onSurfaceVariant, fontSize: 12)),
              items: available.map((r) {
                final color = hexToColor(r.routeColor);
                return DropdownMenuItem<RouteModel>(
                  value: r,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          r.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (r.routeLongName?.isNotEmpty == true) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r.routeLongName!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transfer option data class
// ---------------------------------------------------------------------------

class _TransferOption {
  final StopTimeModel stopTime;
  final int waitMinutes;

  const _TransferOption(
      {required this.stopTime, required this.waitMinutes});
}

// ---------------------------------------------------------------------------
// Transfer row widget
// ---------------------------------------------------------------------------

class _TransferRow extends StatelessWidget {
  final StopTimeModel arrival;
  final List<_TransferOption> transfers;
  final RouteModel routeA;
  final RouteModel routeB;
  final DateTime simDateTime;
  final int windowMin;

  const _TransferRow({
    required this.arrival,
    required this.transfers,
    required this.routeA,
    required this.routeB,
    required this.simDateTime,
    required this.windowMin,
  });

  @override
  Widget build(BuildContext context) {
    final colorA = hexToColor(routeA.routeColor);
    final colorB = hexToColor(routeB.routeColor);
    final hasTransfer = transfers.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: hasTransfer
            ? AppTheme.primary.withOpacity(0.04)
            : AppTheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasTransfer
              ? AppTheme.primary.withOpacity(0.15)
              : const Color(0xFF2E3340).withOpacity(0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RouteBadge(route: routeA, color: colorA),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    arrival.getHeadsign(),
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  arrival.arrivalHourMin,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorA,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!hasTransfer)
              Row(
                children: [
                  const SizedBox(width: 4),
                  const Icon(Icons.block,
                      size: 13, color: AppTheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Sin conexión de ${routeB.displayName} en $windowMin min',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: transfers
                    .map((t) => _TransferChip(
                          option: t,
                          colorB: colorB,
                          routeB: routeB,
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route badge
// ---------------------------------------------------------------------------

class _RouteBadge extends StatelessWidget {
  final RouteModel route;
  final Color color;

  const _RouteBadge({required this.route, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        route.displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transfer chip
// ---------------------------------------------------------------------------

class _TransferChip extends StatelessWidget {
  final _TransferOption option;
  final Color colorB;
  final RouteModel routeB;

  const _TransferChip({
    required this.option,
    required this.colorB,
    required this.routeB,
  });

  @override
  Widget build(BuildContext context) {
    final isVeryTight = option.waitMinutes <= 2;
    final borderColor =
        isVeryTight ? Colors.orange : colorB.withOpacity(0.5);
    final bgColor = isVeryTight
        ? Colors.orange.withOpacity(0.08)
        : colorB.withOpacity(0.08);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colorB,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              routeB.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            option.stopTime.arrivalHourMin,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isVeryTight ? Colors.orange : AppTheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '(${option.waitMinutes} min)',
            style: TextStyle(
              fontSize: 10,
              color: isVeryTight
                  ? Colors.orange.withOpacity(0.8)
                  : AppTheme.onSurfaceVariant,
            ),
          ),
          if (isVeryTight) ...[
            const SizedBox(width: 3),
            const Icon(Icons.warning_amber_rounded,
                size: 12, color: Colors.orange),
          ],
        ],
      ),
    );
  }
}


