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

  /// Interpolate position along a shape path between two stops
  /// Uses precomputed shape indices for each stop to avoid direction confusion
  static (double lat, double lon)? interpolateAlongShape(
    List<LatLng> shapePath,
    double prevStopLat,
    double prevStopLon,
    double nextStopLat,
    double nextStopLon,
    double fraction, {
    int? prevShapeIndex,
    int? nextShapeIndex,
  }) {
    if (shapePath.isEmpty) return null;
    if (fraction <= 0) return (prevStopLat, prevStopLon);
    if (fraction >= 1) return (nextStopLat, nextStopLon);

    // If we don't have precomputed indices, fallback to direct interpolation
    if (prevShapeIndex == null || nextShapeIndex == null) {
      return null;
    }
    
    // Ensure valid indices
    if (prevShapeIndex < 0 || nextShapeIndex < 0 || 
        prevShapeIndex >= shapePath.length || nextShapeIndex >= shapePath.length ||
        prevShapeIndex >= nextShapeIndex) {
      return null;
    }

    // Extract the segment of the shape between the two stops
    final segment = shapePath.sublist(prevShapeIndex, nextShapeIndex + 1);
    if (segment.length < 2) return null;

    // Calculate cumulative distances along the shape segment
    final distances = <double>[0.0];
    double totalDistance = 0.0;
    
    for (int i = 1; i < segment.length; i++) {
      final dist = haversineMeters(
        segment[i - 1].latitude, segment[i - 1].longitude,
        segment[i].latitude, segment[i].longitude,
      );
      totalDistance += dist;
      distances.add(totalDistance);
    }

    if (totalDistance < 1.0) return null; // Too short, use direct interpolation

    // Find the target distance along the path
    final targetDistance = totalDistance * fraction;

    // Find the segment containing the target distance
    for (int i = 1; i < distances.length; i++) {
      if (targetDistance <= distances[i]) {
        // Interpolate between points i-1 and i
        final segmentFraction = (targetDistance - distances[i - 1]) / 
                                 (distances[i] - distances[i - 1]);
        
        return interpolateGeodetic(
          segment[i - 1].latitude,
          segment[i - 1].longitude,
          segment[i].latitude,
          segment[i].longitude,
          segmentFraction,
        );
      }
    }

    // Fallback to last point
    return (segment.last.latitude, segment.last.longitude);
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
    
    for (final stop in stopCoords) {
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
      searchStartIndex = bestIndex;
    }
    
    return indices;
  }
}
