import 'dart:ui' show FontFeature;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/simulation_providers.dart';

class SimulationBar extends ConsumerStatefulWidget {
  const SimulationBar({super.key});

  @override
  ConsumerState<SimulationBar> createState() => _SimulationBarState();
}

class _SimulationBarState extends ConsumerState<SimulationBar> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final notifier = ref.read(simulationTimeProvider.notifier);
      notifier.advance();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final simTime = ref.watch(simulationTimeProvider);
    final servicesAsync = ref.watch(activeServicesProvider);

    // Sync timer state
    if (simTime.isPlaying && (_timer == null || !_timer!.isActive)) {
      _startTimer();
    } else if (!simTime.isPlaying && (_timer?.isActive ?? false)) {
      _stopTimer();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007E65), AppTheme.primary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Date picker
          _SimBarLabel(label: 'Fecha'),
          const SizedBox(width: 6),
          _DateButton(
            date: simTime.dateTime,
            onChanged: (d) =>
                ref.read(simulationTimeProvider.notifier).setDate(d),
          ),

          _simDivider(),

          // Time display / editor
          _SimBarLabel(label: 'Hora'),
          const SizedBox(width: 6),
          _TimeDisplay(
            dateTime: simTime.dateTime,
            onChanged: (h, m, s) =>
                ref.read(simulationTimeProvider.notifier).setTime(h, m, s),
          ),

          _simDivider(),

          // Speed button
          _SpeedButton(
            speed: simTime.speedMultiplier,
            onTap: () =>
                ref.read(simulationTimeProvider.notifier).nextSpeed(),
          ),

          _simDivider(),

          // Play / Pause
          _PlayPauseButtons(
            isPlaying: simTime.isPlaying,
            onPlay: () =>
                ref.read(simulationTimeProvider.notifier).play(),
            onPause: () =>
                ref.read(simulationTimeProvider.notifier).pause(),
          ),

          _simDivider(),

          // Services count
          servicesAsync.when(
            loading: () => const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (services) => _ServicesChip(count: services.length),
          ),
        ],
      ),
    );
  }

  Widget _simDivider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: Colors.white.withOpacity(0.3),
      );
}

class _SimBarLabel extends StatelessWidget {
  final String label;
  const _SimBarLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  const _DateButton({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.dark(primary: AppTheme.primary),
            ),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          DateFormat('dd/MM/yyyy').format(date),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _TimeDisplay extends StatelessWidget {
  final DateTime dateTime;
  final void Function(int h, int m, int s) onChanged;
  const _TimeDisplay({required this.dateTime, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');

    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime:
              TimeOfDay(hour: dateTime.hour, minute: dateTime.minute),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.dark(primary: AppTheme.primary),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          onChanged(picked.hour, picked.minute, 0);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$h:$m:$s',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final int speed;
  final VoidCallback onTap;
  const _SpeedButton({required this.speed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${speed}x',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButtons extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  const _PlayPauseButtons({
    required this.isPlaying,
    required this.onPlay,
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SimBarIconButton(
          icon: Icons.play_arrow_rounded,
          active: isPlaying,
          onTap: onPlay,
          tooltip: 'Iniciar',
        ),
        const SizedBox(width: 4),
        _SimBarIconButton(
          icon: Icons.pause_rounded,
          active: !isPlaying,
          onTap: onPause,
          tooltip: 'Pausar',
        ),
      ],
    );
  }
}

class _SimBarIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;
  const _SimBarIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
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
            color: active
                ? Colors.white.withOpacity(0.25)
                : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color:
                active ? Colors.white : Colors.white.withOpacity(0.5),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _ServicesChip extends StatelessWidget {
  final int count;
  const _ServicesChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined,
              size: 12, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            '$count servicio${count != 1 ? 's' : ''}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
