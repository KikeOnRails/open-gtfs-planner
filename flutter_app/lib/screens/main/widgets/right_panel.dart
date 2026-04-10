import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/simulation_providers.dart';

class RightPanel extends ConsumerStatefulWidget {
  const RightPanel({super.key});

  @override
  ConsumerState<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends ConsumerState<RightPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          left: BorderSide(color: Color(0xFF2E3340), width: 1),
        ),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.onSurfaceVariant,
            labelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: 'VIAJES', icon: Icon(Icons.directions_bus_outlined, size: 14)),
              Tab(text: 'PARADAS', icon: Icon(Icons.place_outlined, size: 14)),
              Tab(text: 'GTFS INFO', icon: Icon(Icons.info_outline, size: 14)),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _TripsTab(),
                _StopsTab(),
                _GtfsInfoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trips Tab
// ---------------------------------------------------------------------------

class _TripsTab extends ConsumerWidget {
  const _TripsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(activeTripsProvider);
    final simVis = ref.watch(routeSimulationVisibilityProvider);
    final simTime = ref.watch(simulationTimeProvider);
    final selectedTrip = ref.watch(selectedTripProvider);

    return tripsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (trips) {
        final visibleTrips = simVis.isEmpty
            ? trips
            : trips.where((t) => simVis[t.routeDbId] == true).toList();

        if (visibleTrips.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.directions_bus_outlined,
                    color: AppTheme.onSurfaceVariant, size: 36),
                const SizedBox(height: 12),
                const Text(
                  'Sin viajes activos',
                  style: TextStyle(color: AppTheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Activa la simulación de una ruta\nen el panel de Capas',
                  style: TextStyle(
                    color: AppTheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Text(
                '${visibleTrips.length} viaje${visibleTrips.length != 1 ? 's' : ''} en ruta',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: visibleTrips.length,
                itemBuilder: (_, i) {
                  final trip = visibleTrips[i];
                  final isSelected = selectedTrip?.id == trip.id;
                  final route = trip.route;
                  final routeColor = route != null
                      ? hexToColor(route.routeColor)
                      : AppTheme.primary;

                  return InkWell(
                    onTap: () {
                      ref.read(selectedTripProvider.notifier).state =
                          trip;
                      ref.read(selectedStopProvider.notifier).state =
                          null;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withOpacity(0.1)
                            : null,
                        border: Border(
                          left: BorderSide(
                            color: isSelected
                                ? AppTheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                          bottom: const BorderSide(
                            color: Color(0xFF2E3340),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: routeColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              route?.displayName ?? '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trip.tripHeadsign ?? trip.tripId,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${trip.getStartHour()} → ${trip.getEndHour()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${trip.getTripPercent(simTime.dateTime).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: routeColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stops Tab
// ---------------------------------------------------------------------------

class _StopsTab extends ConsumerStatefulWidget {
  const _StopsTab();

  @override
  ConsumerState<_StopsTab> createState() => _StopsTabState();
}

class _StopsTabState extends ConsumerState<_StopsTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gtfsFilesAsync = ref.watch(gtfsFilesProvider);
    final selectedStop = ref.watch(selectedStopProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
            style:
                const TextStyle(fontSize: 12, color: AppTheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Buscar parada...',
              prefixIcon: const Icon(Icons.search,
                  size: 16, color: AppTheme.onSurfaceVariant),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          size: 14, color: AppTheme.onSurfaceVariant),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
            ),
          ),
        ),
        Expanded(
          child: gtfsFilesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (files) {
              if (files.isEmpty) {
                return const Center(
                  child: Text(
                    'Sin archivos GTFS importados',
                    style: TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return _StopsList(
                gtfsFiles: files,
                query: _query,
                selectedStop: selectedStop,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StopsList extends ConsumerWidget {
  final List<GtfsFileModel> gtfsFiles;
  final String query;
  final StopModel? selectedStop;

  const _StopsList({
    required this.gtfsFiles,
    required this.query,
    required this.selectedStop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: gtfsFiles.length,
      itemBuilder: (_, i) => _StopsForFile(
        gtfsFile: gtfsFiles[i],
        query: query,
        selectedStop: selectedStop,
      ),
    );
  }
}

class _StopsForFile extends ConsumerStatefulWidget {
  final GtfsFileModel gtfsFile;
  final String query;
  final StopModel? selectedStop;

  const _StopsForFile({
    required this.gtfsFile,
    required this.query,
    required this.selectedStop,
  });

  @override
  ConsumerState<_StopsForFile> createState() => _StopsForFileState();
}

class _StopsForFileState extends ConsumerState<_StopsForFile> {
  List<StopModel>? _stops;

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  Future<void> _loadStops() async {
    final stops = await GtfsRepository.getStops(widget.gtfsFile.id);
    if (mounted) setState(() => _stops = stops);
  }

  @override
  Widget build(BuildContext context) {
    final stops = _stops;
    if (stops == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(
            minHeight: 2, color: AppTheme.primary),
      );
    }

    final filtered = widget.query.isEmpty
        ? stops
        : stops
            .where((s) =>
                s.displayName
                    .toLowerCase()
                    .contains(widget.query) ||
                s.stopId.toLowerCase().contains(widget.query))
            .toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(
        widget.gtfsFile.filename,
        style: const TextStyle(
            fontSize: 11, color: AppTheme.onSurfaceVariant),
      ),
      trailing: Text(
        '${filtered.length}',
        style: const TextStyle(
            fontSize: 11, color: AppTheme.onSurfaceVariant),
      ),
      children: filtered.take(100).map((stop) {
        final isSelected = widget.selectedStop?.id == stop.id;
        return InkWell(
          onTap: () {
            ref.read(selectedStopProvider.notifier).state = stop;
            ref.read(selectedTripProvider.notifier).state = null;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withOpacity(0.1)
                  : null,
              border: const Border(
                bottom: BorderSide(
                    color: Color(0xFF2E3340), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 12, color: AppTheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stop.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  stop.stopId,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// GTFS Info Tab
// ---------------------------------------------------------------------------

class _GtfsInfoTab extends ConsumerWidget {
  const _GtfsInfoTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gtfsFilesAsync = ref.watch(gtfsFilesProvider);
    final servicesAsync = ref.watch(activeServicesProvider);

    return gtfsFilesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (files) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Services section
          servicesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (services) => _InfoSection(
              title: 'Servicios activos',
              icon: Icons.calendar_today_outlined,
              count: services.length,
              children: services
                  .map((s) => _InfoTile(
                        title: s.serviceId,
                        subtitle: s.gtfsFilename,
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Files info
          ...files.map((f) => _GtfsFileSummary(gtfsFile: f)),
        ],
      ),
    );
  }
}

class _GtfsFileSummary extends ConsumerStatefulWidget {
  final GtfsFileModel gtfsFile;
  const _GtfsFileSummary({required this.gtfsFile});

  @override
  ConsumerState<_GtfsFileSummary> createState() =>
      _GtfsFileSummaryState();
}

class _GtfsFileSummaryState extends ConsumerState<_GtfsFileSummary> {
  int? _stopCount;
  int? _routeCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stops = await GtfsRepository.getStops(widget.gtfsFile.id);
    final routes = await GtfsRepository.getRoutes(widget.gtfsFile.id);
    if (mounted) {
      setState(() {
        _stopCount = stops.length;
        _routeCount = routes.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined,
                    size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.gtfsFile.filename,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatChip(
                  label: 'Paradas',
                  value: _stopCount?.toString() ?? '...',
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'Rutas',
                  value: _routeCount?.toString() ?? '...',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final List<Widget> children;

  const _InfoSection({
    required this.title,
    required this.icon,
    required this.count,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon, size: 16, color: AppTheme.primary),
        title: Text(
          '$title ($count)',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        children: children,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final String subtitle;
  const _InfoTile({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(title,
          style: const TextStyle(fontSize: 11, color: AppTheme.onSurface)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 10, color: AppTheme.onSurfaceVariant)),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
