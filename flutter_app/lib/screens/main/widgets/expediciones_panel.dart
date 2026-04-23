import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/simulation_providers.dart';
import 'create_expedicion_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showExpedicionesPanel(
  BuildContext context,
  WidgetRef ref,
  RouteModel route,
  GtfsFileModel gtfsFile,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _ExpedicionesPanel(route: route, gtfsFile: gtfsFile),
    ),
  );
  // Invalidate simulation after possible edits
  ref.invalidate(activeTripsProvider);
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel widget
// ─────────────────────────────────────────────────────────────────────────────

class _ExpedicionesPanel extends StatefulWidget {
  final RouteModel route;
  final GtfsFileModel gtfsFile;

  const _ExpedicionesPanel({required this.route, required this.gtfsFile});

  @override
  State<_ExpedicionesPanel> createState() => _ExpedicionesPanelState();
}

class _ExpedicionesPanelState extends State<_ExpedicionesPanel>
    with TickerProviderStateMixin {
  List<ExpedicionSummary> _all = [];
  List<String> _serviceIds = [];
  TabController? _tabController;
  bool _loading = true;
  String? _loadError;
  // Which trip ids are pending deletion (show spinner)
  final Set<int> _deleting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _loadError = null; });
    try {
      final all =
          await GtfsRepository.getExpedicionesForRoute(widget.route.id);
      if (!mounted) return;
      final sids = all.map((e) => e.serviceId).toSet().toList()..sort();
      final prevIndex = _tabController?.index ?? 0;

      // Build new controller BEFORE disposing the old one to avoid
      // the TabBarView referencing a disposed controller mid-frame.
      final tc = sids.isNotEmpty
          ? TabController(
              length: sids.length,
              vsync: this,
              initialIndex:
                  prevIndex.clamp(0, (sids.length - 1).clamp(0, 999)),
            )
          : null;

      final old = _tabController;
      setState(() {
        _all = all;
        _serviceIds = sids;
        _tabController = tc;
        _loading = false;
      });
      // Dispose AFTER setState so the widget is no longer referencing it.
      old?.dispose();
    } catch (e, st) {
      debugPrint('Error loading expediciones: $e\n$st');
      if (mounted) setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  List<ExpedicionSummary> _forService(String sid) =>
      _all.where((e) => e.serviceId == sid).toList();

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _openCreate() async {
    final count = await showCreateExpedicionDialog(
        context, widget.route, widget.gtfsFile);
    if (count > 0 && mounted) await _load();
  }

  Future<void> _deleteTrip(int tripDbId) async {
    setState(() => _deleting.add(tripDbId));
    await GtfsRepository.deleteTrip(tripDbId);
    await _load();
    setState(() => _deleting.remove(tripDbId));
  }

  Future<void> _confirmDeleteService(String serviceId) async {
    final trips = _forService(serviceId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2129),
        title: Text(
          'Eliminar servicio "$serviceId"',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          'Se eliminarán ${trips.length} expedición${trips.length != 1 ? 'es' : ''} '
          'de este servicio. Esta acción no se puede deshacer.',
          style: const TextStyle(color: Color(0xFF8B9299), fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar todas'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final t in trips) {
      await GtfsRepository.deleteTrip(t.tripDbId);
    }
    await _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E2129),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: SizedBox(
        width: 620,
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else if (_loadError != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 32),
                        const SizedBox(height: 10),
                        Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFF9BA3AF), fontSize: 12)),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_serviceIds.isEmpty)
              Expanded(child: _buildEmpty())
            else ...[
              _buildTabBar(),
              Expanded(child: _buildTabContent()),
            ],
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Color(0xFF2A2F3A)))),
      child: Row(
        children: [
          const Icon(Icons.departure_board,
              size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Expediciones',
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
          if (!_loading)
            Text(
              '${_all.length} expedición${_all.length != 1 ? 'es' : ''} en total',
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 11),
            ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close,
                size: 16, color: Color(0xFF6B7280)),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Color(0xFF2A2F3A)))),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppTheme.primary,
              unselectedLabelColor: const Color(0xFF6B7280),
              indicatorColor: AppTheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 12),
              tabs: _serviceIds
                  .map((sid) => Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(sid),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2F3A),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_forService(sid).length}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF9BA3AF)),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Delete service button
          if (_tabController != null)
            Tooltip(
              message: 'Eliminar todas las expediciones de este servicio',
              child: IconButton(
                icon: const Icon(Icons.delete_sweep_outlined,
                    size: 16, color: Color(0xFF6B7280)),
                onPressed: () {
                  final idx = _tabController!.index;
                  if (idx < _serviceIds.length) {
                    _confirmDeleteService(_serviceIds[idx]);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    if (_tabController == null) return const SizedBox.shrink();
    return TabBarView(
      controller: _tabController,
      children: _serviceIds
          .map((sid) => _ServiceTab(
                expediciones: _forService(sid),
                deleting: _deleting,
                onDelete: _deleteTrip,
              ))
          .toList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.departure_board_outlined,
              size: 40, color: Color(0xFF2A2F3A)),
          const SizedBox(height: 12),
          const Text(
            'No hay expediciones para esta ruta',
            style:
                TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crea la primera expedición con el botón de abajo.',
            style:
                TextStyle(color: Color(0xFF4B5563), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
          border:
              Border(top: BorderSide(color: Color(0xFF2A2F3A)))),
      child: Row(
        children: [
          if (!_loading && _all.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh,
                  size: 16, color: Color(0xFF6B7280)),
              tooltip: 'Recargar',
              onPressed: _load,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 28, minHeight: 28),
            ),
          ],
          const Spacer(),
          FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nueva expedición'),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One tab: list of expediciones for a service_id
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceTab extends StatelessWidget {
  final List<ExpedicionSummary> expediciones;
  final Set<int> deleting;
  final Future<void> Function(int tripDbId) onDelete;

  const _ServiceTab({
    required this.expediciones,
    required this.deleting,
    required this.onDelete,
  });

  // Group by displayLabel (headsign / direction)
  Map<String, List<ExpedicionSummary>> get _grouped {
    final map = <String, List<ExpedicionSummary>>{};
    for (final e in expediciones) {
      map.putIfAbsent(e.displayLabel, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (expediciones.isEmpty) {
      return const Center(
        child: Text('Sin expediciones en este servicio.',
            style: TextStyle(color: Color(0xFF4B5563), fontSize: 12)),
      );
    }
    final groups = _grouped;
    final groupKeys = groups.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groupKeys.length,
      itemBuilder: (context, i) {
        final key = groupKeys[i];
        final items = groups[key]!;
        return _GroupSection(
          label: key.isEmpty ? 'Sin headsign' : key,
          expediciones: items,
          deleting: deleting,
          onDelete: onDelete,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group section (collapsible by headsign/pattern)
// ─────────────────────────────────────────────────────────────────────────────

class _GroupSection extends StatefulWidget {
  final String label;
  final List<ExpedicionSummary> expediciones;
  final Set<int> deleting;
  final Future<void> Function(int) onDelete;

  const _GroupSection({
    required this.label,
    required this.expediciones,
    required this.deleting,
    required this.onDelete,
  });

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group header
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Color(0xFF9BA3AF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2F3A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.expediciones.length}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF9BA3AF)),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Trips grid (only when expanded)
        if (_expanded)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.expediciones
                  .map((e) => _TripChip(
                        exp: e,
                        deleting: widget.deleting.contains(e.tripDbId),
                        onDelete: () => widget.onDelete(e.tripDbId),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single trip chip
// ─────────────────────────────────────────────────────────────────────────────

class _TripChip extends StatelessWidget {
  final ExpedicionSummary exp;
  final bool deleting;
  final VoidCallback onDelete;

  const _TripChip({
    required this.exp,
    required this.deleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 9, top: 5, bottom: 5, right: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF161A22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2F3A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Departure
          Text(
            exp.depHHMM,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
          // Arrow + arrival (if different)
          if (exp.arrHHMM != exp.depHHMM) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.arrow_forward,
                  size: 10, color: Color(0xFF4B5563)),
            ),
            Text(
              exp.arrHHMM,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(width: 4),
          // Delete
          if (deleting)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Colors.redAccent),
            )
          else
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.redAccent.withOpacity(0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
