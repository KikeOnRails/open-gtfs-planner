import 'dart:math' as math;

import '../../models/gtfs_models.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Represents a single line's schedule at a stop, with its detected headway.
class LineScheduleData {
  final RouteModel route;

  /// Sorted arrival times in minutes from midnight (e.g. 6:20 → 380).
  final List<int> arrivalMinutes;

  /// Detected headway in minutes (most common interval between arrivals).
  final int headway;

  const LineScheduleData({
    required this.route,
    required this.arrivalMinutes,
    required this.headway,
  });
}

/// A single arrival event mapped into a [0, window) periodic window.
class SyncEvent {
  final int minuteInWindow;
  final RouteModel route;

  const SyncEvent({required this.minuteInWindow, required this.route});
}

/// Per-line suggestion from the optimisation.
class SyncLineSuggestion {
  final RouteModel route;

  /// How many minutes to shift this line's schedule.
  /// Positive = delay, negative = advance.
  /// 0 = no change (reference line).
  final int shiftMinutes;

  /// Headway of the line (used for display).
  final int headwayMinutes;

  const SyncLineSuggestion({
    required this.route,
    required this.shiftMinutes,
    required this.headwayMinutes,
  });

  bool get hasChange => shiftMinutes != 0;

  String get shiftLabel {
    if (shiftMinutes == 0) return 'Sin cambio (referencia)';
    final abs = shiftMinutes.abs();
    final sign = shiftMinutes > 0 ? '+' : '-';
    return '${sign}${abs} min';
  }
}

/// Result returned by [TransferSyncAlgorithm.optimize].
class SyncResult {
  /// The window (period) used for analysis in minutes.
  final int windowMinutes;

  /// Minimum gap between ANY two consecutive arrivals with the original schedule.
  final double originalMinGapMinutes;

  /// Minimum gap after optimisation.
  final double optimizedMinGapMinutes;

  /// Range (max-min) of inter-arrival gaps — 0 = perfectly uniform cadence.
  final double originalGapRange;
  final double optimizedGapRange;

  /// Average inter-arrival gap (total_time / arrivals).
  final double originalAvgGap;
  final double optimizedAvgGap;

  /// Per-line suggestions (line 0 always has shift = 0, kept as reference).
  final List<SyncLineSuggestion> suggestions;

  /// Events in the window before optimisation (sorted by minuteInWindow).
  final List<SyncEvent> originalEvents;

  /// Events in the window after optimisation (sorted by minuteInWindow).
  final List<SyncEvent> optimizedEvents;

  const SyncResult({
    required this.windowMinutes,
    required this.originalMinGapMinutes,
    required this.optimizedMinGapMinutes,
    required this.originalGapRange,
    required this.optimizedGapRange,
    required this.originalAvgGap,
    required this.optimizedAvgGap,
    required this.suggestions,
    required this.originalEvents,
    required this.optimizedEvents,
  });

  double get improvementMinutes =>
      optimizedMinGapMinutes - originalMinGapMinutes;

  bool get isImproved => improvementMinutes > 0.5;

  /// Cadence uniformity improvement: positive = more uniform after optimisation.
  double get uniformityImprovement => originalGapRange - optimizedGapRange;
}

// ---------------------------------------------------------------------------
// Algorithm
// ---------------------------------------------------------------------------

class TransferSyncAlgorithm {
  // ---- Maths helpers -------------------------------------------------------

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a;
  }

  static int _lcm(int a, int b) {
    if (a == 0 || b == 0) return math.max(a, b);
    return (a ~/ _gcd(a, b)) * b;
  }

  // ---- Headway detection ---------------------------------------------------

  /// Detects the dominant headway from a sorted list of arrival times (minutes).
  /// Uses the mode of positive inter-arrival gaps, ignoring outliers.
  static int detectHeadway(List<int> sorted) {
    if (sorted.length < 2) return 60;

    final gaps = <int>[];
    for (int i = 1; i < sorted.length; i++) {
      final g = sorted[i] - sorted[i - 1];
      // Ignore gaps < 1 min (duplicates/rounding) and > 180 min (service breaks)
      if (g >= 1 && g <= 180) gaps.add(g);
    }

    if (gaps.isEmpty) return 60;

    // Mode
    final freq = <int, int>{};
    for (final g in gaps) {
      freq[g] = (freq[g] ?? 0) + 1;
    }
    return freq.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  // ---- Build LineScheduleData from stop times ------------------------------

  static LineScheduleData buildLineSchedule(
      RouteModel route, List<StopTimeModel> stopTimes, DateTime refDate) {
    final arrivals = stopTimes
        .map((st) {
          final dt = st.getArrivalTimeInDate(refDate);
          return dt.hour * 60 + dt.minute;
        })
        .toList()
      ..sort();

    final headway = detectHeadway(arrivals);
    return LineScheduleData(
      route: route,
      arrivalMinutes: arrivals,
      headway: headway,
    );
  }

  // ---- Periodic event generation -------------------------------------------

  /// Generates the positions of events in [0, window) for a line.
  ///
  /// The anchor is determined as:  firstArrival + shift  (mod headway)
  /// Events are placed at: anchor, anchor + headway, anchor + 2*headway, ...
  static List<int> _eventsInWindow({
    required int firstArrival,
    required int headway,
    required int shift,
    required int window,
  }) {
    // Shift the anchor within [0, headway)
    final anchor = ((firstArrival + shift) % headway + headway) % headway;

    final events = <int>[];
    for (int k = 0; anchor + k * headway < window; k++) {
      events.add(anchor + k * headway);
    }
    return events;
  }

  // ---- Gap metrics ---------------------------------------------------------

  /// Minimum gap between consecutive arrivals in a sorted list.
  static double _computeMinGapLinear(List<int> sorted) {
    if (sorted.length < 2) return double.infinity;
    double minGap = double.infinity;
    for (int i = 1; i < sorted.length; i++) {
      final g = (sorted[i] - sorted[i - 1]).toDouble();
      if (g < minGap) minGap = g;
    }
    return minGap;
  }

  /// Maximum gap between consecutive arrivals in a sorted list.
  static double _computeMaxGapLinear(List<int> sorted) {
    if (sorted.length < 2) return 0;
    double maxGap = 0;
    for (int i = 1; i < sorted.length; i++) {
      final g = (sorted[i] - sorted[i - 1]).toDouble();
      if (g > maxGap) maxGap = g;
    }
    return maxGap;
  }

  /// Gap range (max - min). 0 = perfectly uniform cadence.
  static double _computeGapRange(List<int> sorted) =>
      _computeMaxGapLinear(sorted) - _computeMinGapLinear(sorted);

  /// Average inter-arrival gap.
  static double _computeAvgGap(List<int> sorted) {
    if (sorted.length < 2) return 0;
    return (sorted.last - sorted.first) / (sorted.length - 1);
  }

  // ---- Main optimisation ---------------------------------------------------

  /// Given a list of lines, finds the optimal phase offsets to maximise the
  /// minimum gap between consecutive arrivals at the stop.
  ///
  /// Works directly on **real arrival times** (not a synthetic periodic model)
  /// so that:
  ///   - Irregular headways are handled correctly.
  ///   - The minimum gap is meaningful in the actual timetable window.
  ///   - Coprime headways (e.g. 13 and 15 min) don't produce spurious
  ///     all-zero gaps due to periodic collisions in the LCM window.
  ///
  /// Strategy:
  ///   1. Keep line 0 fixed (shift = 0 min).
  ///   2. For each subsequent line k, try every integer shift in
  ///      [0, headway_k) minutes and pick the value that maximises the minimum
  ///      gap across ALL combined arrivals (lines 0..k).
  ///   3. Normalise shifts to (−headway/2, headway/2] for display.
  static SyncResult optimize(List<LineScheduleData> lines) {
    assert(lines.isNotEmpty);

    // ------ Window for periodic visualisation only -----------------------
    int window = lines.first.headway;
    for (final line in lines.skip(1)) {
      window = _lcm(window, line.headway);
      if (window > 360) {
        window = lines.map((l) => l.headway).reduce(math.max);
        break;
      }
    }
    final maxH = lines.map((l) => l.headway).reduce(math.max);
    if (window < maxH) window = maxH;

    // ------ Original min gap on REAL arrivals ----------------------------
    final allOriginal = <int>[];
    for (final line in lines) {
      allOriginal.addAll(line.arrivalMinutes);
    }
    allOriginal.sort();
    final originalMinGap = _computeMinGapLinear(allOriginal);

    // ------ Greedy optimisation on REAL arrivals -------------------------
    // Scoring is lexicographic:
    //   1st: maximise minimum inter-arrival gap  (no two buses too close)
    //   2nd: minimise gap range (max-min)        (uniform cadence)
    final shifts = List.filled(lines.length, 0);

    for (int k = 1; k < lines.length; k++) {
      int bestShift = 0;
      double bestMinGap = -1;
      double bestRange = double.infinity;
      final headwayK = lines[k].headway;

      for (int delta = 0; delta < headwayK; delta++) {
        final combined = <int>[];
        for (int j = 0; j < k; j++) {
          if (lines[j].arrivalMinutes.isEmpty) continue;
          for (final t in lines[j].arrivalMinutes) {
            combined.add(t + shifts[j]);
          }
        }
        for (final t in lines[k].arrivalMinutes) {
          combined.add(t + delta);
        }
        combined.sort();

        final minGap = _computeMinGapLinear(combined);
        final range = _computeGapRange(combined);

        // Lexicographic: prefer larger min_gap; break ties with smaller range
        if (minGap > bestMinGap ||
            (minGap == bestMinGap && range < bestRange)) {
          bestMinGap = minGap;
          bestRange = range;
          bestShift = delta;
        }
      }
      shifts[k] = bestShift;
    }

    // ------ Normalise shifts to (−H/2, H/2] for display -----------------
    final normalisedShifts = List.generate(lines.length, (i) {
      final h = lines[i].headway;
      int s = shifts[i] % h;
      if (s > h ~/ 2) s -= h;
      return s;
    });

    // ------ Optimised min gap on REAL arrivals ---------------------------
    final allOptimised = <int>[];
    for (int j = 0; j < lines.length; j++) {
      for (final t in lines[j].arrivalMinutes) {
        allOptimised.add(t + shifts[j]);
      }
    }
    allOptimised.sort();
    final optimisedMinGap = _computeMinGapLinear(allOptimised);
    final optimisedGapRange = _computeGapRange(allOptimised);
    final optimisedAvgGap = _computeAvgGap(allOptimised);

    final origGapRange = _computeGapRange(allOriginal);
    final origAvgGap = _computeAvgGap(allOriginal);

    // ------ Periodic viz events (for the visualisation section only) -----
    final List<SyncEvent> originalEventsViz = [];
    for (final line in lines) {
      if (line.arrivalMinutes.isEmpty) continue;
      for (final t in _eventsInWindow(
        firstArrival: line.arrivalMinutes.first,
        headway: line.headway,
        shift: 0,
        window: window,
      )) {
        originalEventsViz.add(SyncEvent(minuteInWindow: t, route: line.route));
      }
    }
    originalEventsViz.sort((a, b) =>
        a.minuteInWindow.compareTo(b.minuteInWindow));

    final List<SyncEvent> optimisedEventsViz = [];
    for (int j = 0; j < lines.length; j++) {
      if (lines[j].arrivalMinutes.isEmpty) continue;
      for (final t in _eventsInWindow(
        firstArrival: lines[j].arrivalMinutes.first,
        headway: lines[j].headway,
        shift: shifts[j],
        window: window,
      )) {
        optimisedEventsViz
            .add(SyncEvent(minuteInWindow: t, route: lines[j].route));
      }
    }
    optimisedEventsViz.sort((a, b) =>
        a.minuteInWindow.compareTo(b.minuteInWindow));

    // ------ Build suggestions --------------------------------------------
    final suggestions = List.generate(lines.length, (i) {
      return SyncLineSuggestion(
        route: lines[i].route,
        shiftMinutes: normalisedShifts[i],
        headwayMinutes: lines[i].headway,
      );
    });

    return SyncResult(
      windowMinutes: window,
      originalMinGapMinutes: originalMinGap,
      optimizedMinGapMinutes: optimisedMinGap,
      originalGapRange: origGapRange,
      optimizedGapRange: optimisedGapRange,
      originalAvgGap: origAvgGap,
      optimizedAvgGap: optimisedAvgGap,
      suggestions: suggestions,
      originalEvents: originalEventsViz,
      optimizedEvents: optimisedEventsViz,
    );
  }

  // ---- Theoretical optimal gap ----------------------------------------

  /// Theoretical upper bound: if N lines share total T arrivals in a window W,
  /// the best possible min gap is W / T.
  static double theoreticalOptimalGap(List<LineScheduleData> lines, int window) {
    int total = 0;
    for (final l in lines) {
      total += (window / l.headway).ceil();
    }
    if (total == 0) return 0;
    return window / total;
  }
}
