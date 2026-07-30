import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Geodetic (spherical) interpolation between two lat/lon points.
/// Equivalent to the original TypeScript InterpolationHelper.
class InterpolationHelper {
  static double toRadians(double degrees) => degrees * math.pi / 180;
  static double toDegrees(double radians) => radians * 180 / math.pi;

  /// Returns the interpolated [lat, lon] between point1 and point2 at [fraction] (0..1).
  static (double lat, double lon) interpolateGeodetic(
    double lat1Deg,
    double lon1Deg,
    double lat2Deg,
    double lon2Deg,
    double fraction,
  ) {
    if (fraction <= 0) return (lat1Deg, lon1Deg);
    if (fraction >= 1) return (lat2Deg, lon2Deg);

    final lat1 = toRadians(lat1Deg);
    final lon1 = toRadians(lon1Deg);
    final lat2 = toRadians(lat2Deg);
    final lon2 = toRadians(lon2Deg);

    final sinHalfLat = math.sin((lat2 - lat1) / 2);
    final sinHalfLon = math.sin((lon2 - lon1) / 2);

    final d = 2 *
        math.asin(math.sqrt(sinHalfLat * sinHalfLat +
            math.cos(lat1) * math.cos(lat2) * sinHalfLon * sinHalfLon));

    if (d.abs() < 1e-10) return (lat1Deg, lon1Deg); // Same point

    final a = math.sin((1 - fraction) * d) / math.sin(d);
    final b = math.sin(fraction * d) / math.sin(d);

    final x = a * math.cos(lat1) * math.cos(lon1) +
        b * math.cos(lat2) * math.cos(lon2);
    final y = a * math.cos(lat1) * math.sin(lon1) +
        b * math.cos(lat2) * math.sin(lon2);
    final z = a * math.sin(lat1) + b * math.sin(lat2);

    final latResult = math.atan2(z, math.sqrt(x * x + y * y));
    final lonResult = math.atan2(y, x);

    return (toDegrees(latResult), toDegrees(lonResult));
  }

  /// Distance in metres between two lat/lon points (Haversine).
  static double haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = toRadians(lat2 - lat1);
    final dLon = toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRadians(lat1)) *
            math.cos(toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  /// Build cumulative arc-length distances (metres) for each shape vertex.
  /// Result has the same length as [shapePath], with result[0] == 0.
  static List<double> buildCumulativeDistances(List<LatLng> shapePath) {
    final dists = <double>[0.0];
    for (int i = 1; i < shapePath.length; i++) {
      dists.add(dists.last + haversineMeters(
        shapePath[i - 1].latitude, shapePath[i - 1].longitude,
        shapePath[i].latitude, shapePath[i].longitude,
      ));
    }
    return dists;
  }

  /// Project [lat]/[lon] onto the shape polyline and return its arc-length
  /// from the shape start. [searchFromArcLen] is a lower bound to guarantee
  /// monotonically increasing results across successive stops.
  static double projectOntoPolyline(
    List<LatLng> shapePath,
    List<double> cumDist,
    double lat,
    double lon, {
    double searchFromArcLen = 0.0,
  }) => projectOntoPolylineInWindow(
    shapePath, cumDist, lat, lon,
    searchFromArcLen: searchFromArcLen,
    searchToArcLen: cumDist.last,
  );

  /// Like [projectOntoPolyline] but restricts the search to the arc-length
  /// window [searchFromArcLen]..[searchToArcLen].  This prevents snapping to
  /// a geometrically close but wrong pass on circular/overlapping routes.
  static double projectOntoPolylineInWindow(
    List<LatLng> shapePath,
    List<double> cumDist,
    double lat,
    double lon, {
    required double searchFromArcLen,
    required double searchToArcLen,
  }) {
    double bestDist = double.infinity;
    double bestArcLen = searchFromArcLen;

    for (int i = 0; i < shapePath.length - 1; i++) {
      // Skip segments entirely outside the search window
      if (cumDist[i + 1] < searchFromArcLen) continue;
      if (cumDist[i] > searchToArcLen) break;

      final (rawArcLen, perpDist) = _projectOntoSegment(
        shapePath[i], shapePath[i + 1],
        cumDist[i], cumDist[i + 1],
        lat, lon,
      );

      // Clamp to the allowed window
      final projArcLen = rawArcLen.clamp(searchFromArcLen, searchToArcLen);

      if (perpDist < bestDist) {
        bestDist = perpDist;
        bestArcLen = projArcLen;
      }
    }
    return bestArcLen;
  }

  /// Returns (arcLengthAlongSegment, perpendicularDistance) of [lat]/[lon]
  /// projected onto the segment from [a] to [b].
  static (double arcLen, double perpDist) _projectOntoSegment(
    LatLng a,
    LatLng b,
    double arcA,
    double arcB,
    double lat,
    double lon,
  ) {
    const deg2rad = math.pi / 180;
    final midLat = (a.latitude + b.latitude) / 2 * deg2rad;
    final cosLat = math.cos(midLat);

    // Work in a local flat-earth coordinate system (degrees scaled by cosLat)
    final ax = a.longitude * cosLat;
    final ay = a.latitude;
    final bx = b.longitude * cosLat;
    final by = b.latitude;
    final px = lon * cosLat;
    final py = lat;

    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;

    if (len2 < 1e-20) {
      return (arcA, haversineMeters(lat, lon, a.latitude, a.longitude));
    }

    final t = ((px - ax) * dx + (py - ay) * dy) / len2;
    final tc = t.clamp(0.0, 1.0);

    final projLon = (ax + tc * dx) / cosLat;
    final projLat = ay + tc * dy;

    return (
      arcA + tc * (arcB - arcA),
      haversineMeters(lat, lon, projLat, projLon),
    );
  }

  /// Return the [LatLng] at a given arc-length along [shapePath].
  static LatLng pointAtArcLength(
    List<LatLng> shapePath,
    List<double> cumDist,
    double arcLen,
  ) {
    if (arcLen <= 0) return shapePath.first;
    if (arcLen >= cumDist.last) return shapePath.last;

    // Binary search for the enclosing segment
    int lo = 0, hi = shapePath.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) ~/ 2;
      if (cumDist[mid] <= arcLen) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final segLen = cumDist[hi] - cumDist[lo];
    if (segLen < 1e-10) return shapePath[lo];

    final t = (arcLen - cumDist[lo]) / segLen;
    final result = interpolateGeodetic(
      shapePath[lo].latitude, shapePath[lo].longitude,
      shapePath[hi].latitude, shapePath[hi].longitude,
      t,
    );
    return LatLng(result.$1, result.$2);
  }
  
  /// Precompute shape indices for all stops in a trip
  /// Uses first two stops to determine the correct direction/segment of the shape
  static List<int> computeShapeIndicesForStops(
    List<LatLng> shapePath,
    List<(double lat, double lon)> stopCoords,
  ) {
    if (shapePath.isEmpty || stopCoords.isEmpty) return [];
    if (stopCoords.length < 2) {
      // Single stop: find closest point
      int bestIdx = 0;
      double minDist = double.infinity;
      for (int i = 0; i < shapePath.length; i++) {
        final dist = haversineMeters(
          stopCoords[0].$1, stopCoords[0].$2,
          shapePath[i].latitude, shapePath[i].longitude,
        );
        if (dist < minDist) {
          minDist = dist;
          bestIdx = i;
        }
      }
      return [bestIdx];
    }
    
    // Strategy: Find the best starting point by looking at PAIRS of stops
    // and finding where in the shape both stops are close AND in the right order
    
    final firstStop = stopCoords[0];
    final secondStop = stopCoords[1];
    
    // Find all candidate positions for the first stop
    final candidates = <(int firstIdx, int secondIdx, double score)>[];
    
    for (int i = 0; i < shapePath.length - 1; i++) {
      final distToFirst = haversineMeters(
        firstStop.$1, firstStop.$2,
        shapePath[i].latitude, shapePath[i].longitude,
      );
      
      // Only consider points reasonably close to the first stop
      if (distToFirst > 300) continue; // 300m threshold
      
      // Look for the second stop AFTER this point
      for (int j = i + 1; j < shapePath.length; j++) {
        final distToSecond = haversineMeters(
          secondStop.$1, secondStop.$2,
          shapePath[j].latitude, shapePath[j].longitude,
        );
        
        if (distToSecond > 300) continue;
        
        // Score: lower is better (sum of distances)
        final score = distToFirst + distToSecond;
        candidates.add((i, j, score));
        
        // Only keep the first match for this starting point i
        break;
      }
    }
    
    if (candidates.isEmpty) {
      // Fallback: just find closest points sequentially
      return _computeSequentialIndices(shapePath, stopCoords, 0);
    }
    
    // Find the candidate with the best score
    candidates.sort((a, b) => a.$3.compareTo(b.$3));
    final bestStart = candidates.first.$1;
    
    // Now compute all indices starting from bestStart
    return _computeSequentialIndices(shapePath, stopCoords, bestStart);
  }
  
  /// Helper: compute indices sequentially starting from a given position
  static List<int> _computeSequentialIndices(
    List<LatLng> shapePath,
    List<(double lat, double lon)> stopCoords,
    int startSearchFrom,
  ) {
    final indices = <int>[];
    int searchStartIndex = startSearchFrom;
    
    for (int stopIdx = 0; stopIdx < stopCoords.length; stopIdx++) {
      final stop = stopCoords[stopIdx];
      int bestIndex = searchStartIndex;
      double minDist = double.infinity;
      
      // Search from current position forward in the shape
      for (int i = searchStartIndex; i < shapePath.length; i++) {
        final dist = haversineMeters(
          stop.$1, stop.$2,
          shapePath[i].latitude, shapePath[i].longitude,
        );
        
        if (dist < minDist) {
          minDist = dist;
          bestIndex = i;
        }
        
        // Optimization: if distance is increasing and we're past the best, stop
        if (dist > minDist * 2 && i > bestIndex + 20) {
          break;
        }
      }
      
      indices.add(bestIndex);
      
      // Allow the next stop to map to the same index (non-strictly increasing).
      // Equal indices are handled by the arc-length interpolation in _getTripPosition.
      searchStartIndex = bestIndex;
    }
    
    return indices;
  }
}
