import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/simulation_providers.dart';

/// The main Corredores tab.
///
/// Flow:
///  1. User presses "Detectar" → detection runs.
///  2. Results list shows detected corridors sorted by route count then length.
///  3. Tapping a corridor opens the analysis view (headway, per-route stats, chart).
class CorredoresPanel extends ConsumerWidget {
  const CorredoresPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detectedAsync = ref.watch(detectedCorridorsProvider);
    final selected = ref.watch(selectedDetectedCorredorProvider);
    final minExpeditions = ref.watch(corredorMinExpeditionsFilterProvider);

    return Column(
      children: [
        _PanelHeader(detectedAsync: detectedAsync, selected: selected),
        Expanded(
          child: detectedAsync.when(
            loading: _buildLoading,
            error: (e, _) => _buildError(e),
            data: (corridors) {
              if (selected != null) {
                return _CorredorAnalysisView(corredor: selected);
              }
              final filtered = corridors
                  .where((c) => c.totalTrips >= minExpeditions)
                  .toList();
              if (filtered.isEmpty) {
                if (corridors.isEmpty) return _buildPrompt(context);
                return _buildNoMatchesForFilter(context, minExpeditions);
              }
              return _CorredoresList(corridors: filtered);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 14),
            Text(
              'Analizando secuencias de parada…',
              style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant),
            ),
          ],
        ),
      );

  Widget _buildError(Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $e',
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 12)),
        ),
      );

  Widget _buildPrompt(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined,
                  size: 44, color: AppTheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Detectar corredores',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppTheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Pulsa "Detectar" para analizar automáticamente qué tramos '
                'de paradas son compartidos por varias líneas.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );

  Widget _buildNoMatchesForFilter(BuildContext context, int minExpeditions) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_alt_outlined,
                  size: 44, color: AppTheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Sin corredores para ≥$minExpeditions exp.',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppTheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba a bajar el filtro de expediciones para ver más resultados.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _PanelHeader extends ConsumerStatefulWidget {
  final AsyncValue<List<CorredorDetectado>> detectedAsync;
  final CorredorDetectado? selected;

  const _PanelHeader({required this.detectedAsync, required this.selected});

  @override
  ConsumerState<_PanelHeader> createState() => _PanelHeaderState();
}

class _PanelHeaderState extends ConsumerState<_PanelHeader> {
  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final corridors = widget.detectedAsync.valueOrNull ?? [];
    final minExpeditions = ref.watch(corredorMinExpeditionsFilterProvider);
    final filteredCount =
      corridors.where((c) => c.totalTrips >= minExpeditions).length;
    final isLoading = widget.detectedAsync is AsyncLoading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2E3340), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (selected != null) ...[
                InkWell(
                  onTap: () => ref
                      .read(selectedDetectedCorredorProvider.notifier)
                      .state = null,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.arrow_back,
                        size: 16, color: AppTheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.route_outlined,
                  color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: selected != null
                    ? Text(
                        selected.displayName,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Row(
                        children: [
                          Text('Corredores',
                              style: Theme.of(context).textTheme.titleSmall),
                          if (corridors.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$filteredCount',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              if (selected == null) ...[
                if (corridors.isNotEmpty) _MapToggleButton(),
                _DetectButton(
                  isLoading: isLoading,
                  onDetect: _runDetection,
                ),
              ],
            ],
          ),
          // Min-expeditions filter chips — only when results are visible
          if (selected == null && corridors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 6,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Text('Mín. exps.:',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.onSurfaceVariant)),
                ),
                ...[0, 50, 100, 200, 300].map((val) {
                  final active = minExpeditions == val;
                  return InkWell(
                    onTap: () {
                      ref
                          .read(corredorMinExpeditionsFilterProvider.notifier)
                          .state = val;
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: active
                            ? AppTheme.primary
                            : AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: active
                                ? AppTheme.primary
                                : const Color(0xFF2E3340)),
                      ),
                      child: Text(val == 0 ? 'Todos' : '$val+',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: active
                                ? Colors.white
                                : AppTheme.onSurfaceVariant,
                          )),
                    ),
                  );
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runDetection() async {
    final services = await ref.read(activeServicesProvider.future);
    final serviceIds = services.map((s) => s.serviceId).toList();
    final gtfsFileIds = services.map((s) => s.gtfsFileId).toSet().toList();
    ref.read(detectedCorridorsProvider.notifier).detect(
          serviceIds: serviceIds,
          gtfsFileIds: gtfsFileIds,
        );
    ref.read(selectedDetectedCorredorProvider.notifier).state = null;
  }
}

class _MapToggleButton extends ConsumerWidget {
  const _MapToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(corredorMapVisibleProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () => ref.read(corredorMapVisibleProvider.notifier).state =
            !visible,
        borderRadius: BorderRadius.circular(6),
        child: Tooltip(
          message: visible ? 'Ocultar en mapa' : 'Mostrar en mapa',
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              visible ? Icons.layers : Icons.layers_outlined,
              size: 16,
              color: visible ? AppTheme.primary : AppTheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onDetect;

  const _DetectButton({required this.isLoading, required this.onDetect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FilledButton.icon(
        onPressed: isLoading ? null : onDetect,
        icon: isLoading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome, size: 13),
        label: const Text('Detectar', style: TextStyle(fontSize: 11)),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results list
// ---------------------------------------------------------------------------

class _CorredoresList extends ConsumerWidget {
  final List<CorredorDetectado> corridors;
  const _CorredoresList({required this.corridors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sorted = [...corridors]
      ..sort((a, b) {
        final cmp = b.totalTrips.compareTo(a.totalTrips);
        if (cmp != 0) return cmp;
        return b.stopIds.length.compareTo(a.stopIds.length);
      });
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: sorted.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFF2E3340)),
      itemBuilder: (ctx, i) =>
          _CorredorTile(corredor: sorted[i], rank: i + 1),
    );
  }
}

class _CorredorTile extends ConsumerWidget {
  final CorredorDetectado corredor;
  final int rank;

  const _CorredorTile({required this.corredor, required this.rank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        ref.read(corredorMapVisibleProvider.notifier).state = true;
        ref.read(selectedDetectedCorredorProvider.notifier).state = corredor;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rank badge
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text('$rank',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    corredor.displayName,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _MetaChip(
                          icon: Icons.route_outlined,
                          label:
                              '${corredor.routeIds.length} línea${corredor.routeIds.length != 1 ? 's' : ''}'),
                      _MetaChip(
                          icon: Icons.place_outlined,
                          label: '${corredor.stopIds.length} paradas'),
                      if (corredor.totalTrips > 0)
                        _MetaChip(
                            icon: Icons.directions_bus_outlined,
                            label: '${corredor.totalTrips} exp.'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Route colour pills
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: corredor.routes.take(8).map((r) {
                      Color c;
                      try {
                        final hex = r.hexColor.replaceFirst('#', '');
                        c = Color(int.parse('FF$hex', radix: 16));
                      } catch (_) {
                        c = AppTheme.primary;
                      }
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 92),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: c.withOpacity(0.5)),
                          ),
                          child: Text(
                            r.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: c),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 16, color: AppTheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppTheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Analysis view for a selected corridor
// ---------------------------------------------------------------------------

class _CorredorAnalysisView extends ConsumerStatefulWidget {
  final CorredorDetectado corredor;
  const _CorredorAnalysisView({required this.corredor});

  @override
  ConsumerState<_CorredorAnalysisView> createState() =>
      _CorredorAnalysisViewState();
}

class _CorredorAnalysisViewState
    extends ConsumerState<_CorredorAnalysisView> {
  CorredorAnalysis? _analysis;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  @override
  void didUpdateWidget(_CorredorAnalysisView old) {
    super.didUpdateWidget(old);
    if (old.corredor.stopIds.join() != widget.corredor.stopIds.join()) {
      _runAnalysis();
    }
  }

  Future<void> _runAnalysis() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = await ref.read(activeServicesProvider.future);
      final serviceIds = services.map((s) => s.serviceId).toList();
      final gtfsFileIds =
          services.map((s) => s.gtfsFileId).toSet().toList();

      final analysis = await GtfsRepository.analyzeCorredore(
        stopIds: widget.corredor.stopIds,
        displayName: widget.corredor.displayName,
        serviceIds: serviceIds,
        gtfsFileIds: gtfsFileIds,
      );
      if (mounted) setState(() => _analysis = analysis);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Center(
          child: Text('Error: $_error',
              style: const TextStyle(color: Colors.redAccent)));
    }
    if (_analysis == null) return const SizedBox.shrink();

    final a = _analysis!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCards(analysis: a),
          const SizedBox(height: 14),
          _StopsChain(stops: widget.corredor.stops),
          const SizedBox(height: 14),
          if (a.routeStats.isNotEmpty) ...[
            Text('Líneas que recorren el corredor',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            _RouteStatsTable(stats: a.routeStats),
            const SizedBox(height: 14),
            _HourlyChart(analysis: a),
          ] else
            _buildNoTrips(),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _runAnalysis,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Recalcular'),
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTrips() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline,
                size: 16, color: AppTheme.onSurfaceVariant),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No se encontraron expediciones para el día de simulación activo.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Summary cards
// ---------------------------------------------------------------------------

class _SummaryCards extends StatelessWidget {
  final CorredorAnalysis analysis;
  const _SummaryCards({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
            label: 'Exps. totales',
            value: '${analysis.totalTrips}',
            icon: Icons.directions_bus_outlined),
        const SizedBox(width: 8),
        _StatCard(
            label: 'Cadencia global',
            value: analysis.globalHeadwayLabel,
            icon: Icons.timer_outlined),
        const SizedBox(width: 8),
        _StatCard(
            label: 'Líneas',
            value: '${analysis.routeStats.length}',
            icon: Icons.route_outlined),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2E3340)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.onSurface)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stops chain visualisation
// ---------------------------------------------------------------------------

class _StopsChain extends StatelessWidget {
  final List<StopModel> stops;
  const _StopsChain({required this.stops});

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paradas del corredor',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                )),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E3340)),
          ),
          child: Column(
            children: List.generate(stops.length, (i) {
              final isLast = i == stops.length - 1;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.surface, width: 2),
                        ),
                      ),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 28,
                          color: AppTheme.primary.withOpacity(0.4),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding:
                          EdgeInsets.only(bottom: isLast ? 0 : 16),
                      child: Text(stops[i].displayName,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.onSurface),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Per-route stats table
// ---------------------------------------------------------------------------

class _RouteStatsTable extends StatelessWidget {
  final List<CorredorRouteStats> stats;
  const _RouteStatsTable({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2E3340)),
      ),
      child: Column(
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('Línea',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.onSurfaceVariant))),
                Expanded(
                    flex: 2,
                    child: Text('Exps.',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.onSurfaceVariant))),
                Expanded(
                    flex: 2,
                    child: Text('Cadencia',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.onSurfaceVariant))),
                Expanded(
                    flex: 3,
                    child: Text('Min/Max',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.onSurfaceVariant))),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2E3340)),
          ...stats.asMap().entries.map((e) {
            return Column(
              children: [
                _RouteRow(stats: e.value),
                if (e.key < stats.length - 1)
                  const Divider(height: 1, color: Color(0xFF2E3340)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final CorredorRouteStats stats;
  const _RouteRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    Color color;
    try {
      final hex = stats.route.hexColor.replaceFirst('#', '');
      color = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      color = AppTheme.primary;
    }

    final minH = stats.minHeadwayMinutes;
    final maxH = stats.maxHeadwayMinutes;
    final minMaxLabel = (minH != null && maxH != null)
        ? '${minH.round()}/${maxH.round()} min'
        : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Text(stats.route.displayName,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          Expanded(
              flex: 2,
              child: Text('${stats.totalTrips}',
                  style: const TextStyle(fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text(stats.avgHeadwayLabel,
                  style: const TextStyle(fontSize: 12))),
          Expanded(
              flex: 3,
              child: Text(minMaxLabel,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hourly distribution chart
// ---------------------------------------------------------------------------

class _HourlyChart extends StatelessWidget {
  final CorredorAnalysis analysis;
  const _HourlyChart({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final Map<int, int> byHour = {};
    for (final t in analysis.allDepartureTimes) {
      final h = int.tryParse(t.split(':').first) ?? 0;
      byHour[h] = (byHour[h] ?? 0) + 1;
    }
    if (byHour.isEmpty) return const SizedBox.shrink();

    final maxVal = byHour.values.reduce((a, b) => a > b ? a : b);
    final minHour = byHour.keys.reduce((a, b) => a < b ? a : b);
    final maxHour = byHour.keys.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Distribución horaria de salidas',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                )),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E3340)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 80,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(maxHour - minHour + 1, (i) {
                    final hour = minHour + i;
                    final count = byHour[hour] ?? 0;
                    final frac =
                        maxVal > 0 ? count / maxVal : 0.0;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Tooltip(
                          message: '${hour % 24}h: $count exp.',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (count > 0)
                                AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 400),
                                  height: 60 * frac,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withOpacity(
                                        0.6 + 0.4 * frac),
                                    borderRadius:
                                        const BorderRadius.vertical(
                                            top: Radius.circular(2)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: List.generate(maxHour - minHour + 1, (i) {
                  final hour = minHour + i;
                  return Expanded(
                    child: Text(
                      hour % 2 == 0 ? '${hour % 24}' : '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.onSurfaceVariant),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
