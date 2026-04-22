import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/gtfs_models.dart';
import '../../../providers/simulation_providers.dart';
import 'transfer_review_dialog.dart';
import 'transfer_sync_dialog.dart';

class StopInfoPanel extends ConsumerWidget {
  const StopInfoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stop = ref.watch(selectedStopProvider);

    if (stop == null) return const SizedBox.shrink();

    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanelHeader(
            icon: Icons.place_outlined,
            title: stop.displayName,
            subtitle: 'Parada · ID ${stop.stopId}',
            onClose: () =>
                ref.read(selectedStopProvider.notifier).state = null,
          ),
          // Transfer review action
          InkWell(
            onTap: () => showTransferReviewDialog(context, ref, stop),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.07),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF2E3340), width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.transfer_within_a_station,
                      size: 14, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Revisión de transbordos',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 14, color: AppTheme.primary),
                ],
              ),
            ),
          ),
          // Transfer sync action
          InkWell(
            onTap: () => showTransferSyncDialog(context, ref, stop),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.07),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF2E3340), width: 1),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sync_alt_rounded,
                      size: 14, color: Color(0xFF7C3AED)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sincronización de horarios',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 14, color: Color(0xFF7C3AED)),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          const _NextArrivals(),
        ],
      ),
    );
  }
}

class _NextArrivals extends ConsumerWidget {
  const _NextArrivals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stopTimesAsync = ref.watch(selectedStopTimesProvider);
    final simTime = ref.watch(simulationTimeProvider);

    return stopTimesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.primary),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error: $e',
            style: const TextStyle(color: Colors.red, fontSize: 12)),
      ),
      data: (stopTimes) {
        if (stopTimes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                'Sin horarios para la fecha seleccionada',
                style: TextStyle(
                    color: AppTheme.onSurfaceVariant, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        // Show next arrivals from simulation time
        final upcoming = stopTimes
            .where((st) =>
                st.getArrivalTimeInDate(simTime.dateTime)
                    .isAfter(simTime.dateTime))
            .take(10)
            .toList();

        final past = stopTimes
            .where((st) =>
                !st.getArrivalTimeInDate(simTime.dateTime)
                    .isAfter(simTime.dateTime))
            .toList()
            .reversed
            .take(3)
            .toList()
            .reversed
            .toList();

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 350),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              if (past.isNotEmpty) ...[
                _SectionHeader(label: 'Pasados'),
                ...past.map((st) => _StopTimeRow(
                      stopTime: st,
                      isPast: true,
                      simDateTime: simTime.dateTime,
                    )),
              ],
              _SectionHeader(label: 'Próximas llegadas'),
              if (upcoming.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text(
                    'No hay más llegadas hoy',
                    style: TextStyle(
                        color: AppTheme.onSurfaceVariant, fontSize: 12),
                  ),
                )
              else
                ...upcoming.map((st) => _StopTimeRow(
                      stopTime: st,
                      isPast: false,
                      simDateTime: simTime.dateTime,
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _StopTimeRow extends StatelessWidget {
  final StopTimeModel stopTime;
  final bool isPast;
  final DateTime simDateTime;

  const _StopTimeRow({
    required this.stopTime,
    required this.isPast,
    required this.simDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final route = stopTime.trip?.route;
    final routeColor = route != null
        ? hexToColor(route.routeColor)
        : AppTheme.primary;

    final arrivalDt = stopTime.getArrivalTimeInDate(simDateTime);
    final diff = arrivalDt.difference(simDateTime);
    final minsAway = diff.inMinutes;
    final String timeLabel;
    if (isPast) {
      timeLabel = 'hace ${(-minsAway).abs()} min';
    } else if (minsAway < 1) {
      timeLabel = '< 1 min';
    } else {
      timeLabel = '$minsAway min';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isPast ? Colors.transparent : AppTheme.primary.withOpacity(0.04),
        border: Border(
          bottom: BorderSide(
              color: const Color(0xFF2E3340).withOpacity(0.5), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Route badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: routeColor.withOpacity(isPast ? 0.3 : 1.0),
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
          const SizedBox(width: 10),
          // Headsign
          Expanded(
            child: Text(
              stopTime.getHeadsign(),
              style: TextStyle(
                fontSize: 12,
                color: isPast
                    ? AppTheme.onSurfaceVariant.withOpacity(0.5)
                    : AppTheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stopTime.arrivalHourMin,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isPast
                      ? AppTheme.onSurfaceVariant.withOpacity(0.5)
                      : AppTheme.onSurface,
                ),
              ),
              Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: isPast
                      ? AppTheme.onSurfaceVariant.withOpacity(0.4)
                      : (minsAway < 3 ? Colors.orange : AppTheme.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trip Info Panel
// ---------------------------------------------------------------------------

class TripInfoPanel extends ConsumerWidget {
  const TripInfoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(selectedTripProvider);
    if (trip == null) return const SizedBox.shrink();

    final simTime = ref.watch(simulationTimeProvider);
    final route = trip.route;
    final routeColor = route != null
        ? hexToColor(route.routeColor)
        : AppTheme.primary;

    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanelHeader(
            icon: Icons.directions_bus_outlined,
            title: route?.displayName ?? 'Vehículo',
            subtitle: trip.tripHeadsign ?? 'Dirección desconocida',
            badgeColor: routeColor,
            onClose: () =>
                ref.read(selectedTripProvider.notifier).state = null,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Trip ID', value: trip.tripId),
                _InfoRow(label: 'Servicio', value: trip.serviceId),
                _InfoRow(
                    label: 'Inicio', value: trip.getStartHour()),
                _InfoRow(label: 'Fin', value: trip.getEndHour()),
                _InfoRow(
                  label: 'Progreso',
                  value:
                      '${trip.getTripPercent(simTime.dateTime).toStringAsFixed(1)}%',
                ),
                const SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: trip.getTripPercent(simTime.dateTime) / 100,
                    backgroundColor: routeColor.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(routeColor),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          // Stop times list
          if (trip.stopTimes != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child: Text(
                'PARADAS EN RUTA',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurfaceVariant,
                  letterSpacing: 1,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: trip.stopTimes!.length,
                itemBuilder: (_, i) {
                  final st = trip.stopTimes![i];
                  final arrivalDt =
                      st.getArrivalTimeInDate(simTime.dateTime);
                  final isPast = arrivalDt.isBefore(simTime.dateTime);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isPast
                                ? routeColor.withOpacity(0.3)
                                : routeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            st.stop?.displayName ?? 'Parada ${st.stopSequence}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isPast
                                  ? AppTheme.onSurfaceVariant
                                      .withOpacity(0.5)
                                  : AppTheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          st.arrivalHourMin,
                          style: TextStyle(
                            fontSize: 11,
                            color: isPast
                                ? AppTheme.onSurfaceVariant.withOpacity(0.5)
                                : AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E3340)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? badgeColor;
  final VoidCallback onClose;

  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badgeColor,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: (badgeColor ?? AppTheme.primary).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                color: badgeColor ?? AppTheme.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close,
                  size: 16, color: AppTheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
