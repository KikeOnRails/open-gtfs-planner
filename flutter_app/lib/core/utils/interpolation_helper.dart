import 'dart:math' as math;

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
}
