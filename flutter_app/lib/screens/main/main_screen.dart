import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/project_model.dart';
import '../../providers/project_providers.dart';
import '../../providers/simulation_providers.dart';
import 'widgets/info_panels.dart';
import 'widgets/layers_panel.dart';
import 'widgets/map_widget.dart';
import 'widgets/right_panel.dart';
import 'widgets/simulation_bar.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int projectId;
  const MainScreen({required this.projectId, super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _leftPanelOpen = true;
  bool _rightPanelOpen = true;

  @override
  void initState() {
    super.initState();
    // Load project if not already set
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final current = ref.read(currentProjectProvider);
      if (current?.id != widget.projectId) {
        // Try to find from list
        final projects = await ref.read(projectsProvider.future);
        final project = projects
            .where((p) => p.id == widget.projectId)
            .firstOrNull;
        if (project != null) {
          ref.read(currentProjectProvider.notifier).state = project;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final selectedStop = ref.watch(selectedStopProvider);
    final selectedTrip = ref.watch(selectedTripProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildTopBar(context, project),
          Expanded(
            child: Row(
              children: [
                // Left Panel - Layers
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _leftPanelOpen ? 260 : 0,
                  child: _leftPanelOpen
                      ? const LayersPanel()
                      : const SizedBox.shrink(),
                ),

                // Center - Map + Simulation Bar
                Expanded(
                  child: Column(
                    children: [
                      // Simulation bar
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: const SimulationBar(),
                      ),

                      // Map
                      Expanded(
                        child: Stack(
                          children: [
                            // Map
                            const MapWidget(),

                            // Info panels overlay (bottom-left)
                            if (selectedStop != null || selectedTrip != null)
                              Positioned(
                                bottom: 16,
                                left: 16,
                                child: SizedBox(
                                  width: 320,
                                  child: selectedStop != null
                                      ? const StopInfoPanel()
                                      : const TripInfoPanel(),
                                ),
                              ),

                            // Panel toggle buttons
                            Positioned(
                              top: 12,
                              left: 12,
                              child: _PanelToggleButton(
                                icon: _leftPanelOpen
                                    ? Icons.chevron_left
                                    : Icons.chevron_right,
                                tooltip: _leftPanelOpen
                                    ? 'Ocultar capas'
                                    : 'Mostrar capas',
                                onTap: () => setState(
                                  () => _leftPanelOpen = !_leftPanelOpen,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: _PanelToggleButton(
                                icon: _rightPanelOpen
                                    ? Icons.chevron_right
                                    : Icons.chevron_left,
                                tooltip: _rightPanelOpen
                                    ? 'Ocultar panel'
                                    : 'Mostrar panel',
                                onTap: () => setState(
                                  () => _rightPanelOpen = !_rightPanelOpen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Panel - Trips/Stops/Info
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _rightPanelOpen ? 280 : 0,
                  child: _rightPanelOpen
                      ? const RightPanel()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ProjectModel? project) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E3340), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back,
                      size: 16, color: AppTheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Proyectos',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 1,
            height: 20,
            color: const Color(0xFF2E3340),
          ),
          const SizedBox(width: 16),
          // App icon
          const Icon(Icons.directions_bus, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          // Project name
          Text(
            project?.name ?? 'Cargando...',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Active trips count
          const _ActiveTripsIndicator(),
        ],
      ),
    );
  }
}

class _ActiveTripsIndicator extends ConsumerWidget {
  const _ActiveTripsIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(activeTripsProvider);
    final simVis = ref.watch(routeSimulationVisibilityProvider);

    return tripsAsync.when(
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppTheme.primary),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (trips) {
        final visibleCount = simVis.isEmpty
            ? trips.length
            : trips.where((t) => simVis[t.routeDbId] == true).length;

        if (visibleCount == 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$visibleCount vehículo${visibleCount != 1 ? 's' : ''}',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PanelToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _PanelToggleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.mapOverlay,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E3340)),
          ),
          child: Icon(icon, size: 16, color: AppTheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
