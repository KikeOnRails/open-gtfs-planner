import 'dart:convert';
import 'package:http/http.dart' as http;

/// A point on the map (lat, lon).
typedef LatLon = (double lat, double lon);

/// Fetches road-following geometry between an ordered list of waypoints
/// using the OSRM public demo server.
///
/// Falls back to straight-line segments if the request fails.
class OsrmService {
  /// Base URL – can be overridden (e.g. self-hosted OSRM).
  static String baseUrl = 'https://router.project-osrm.org';

  /// Profile to use. Use 'driving' for buses, 'foot' for trams in pedestrian areas.
  static String profile = 'driving';

  /// Returns the road-following polyline (as a list of lat/lon pairs) that
  /// passes through [waypoints] in order.
  ///
  /// Splits the request into chunks of [chunkSize] stops to stay within URL
  /// length limits, then joins the segments (dropping duplicate junction points).
  static Future<List<LatLon>> getRouteGeometry(
    List<LatLon> waypoints, {
    int chunkSize = 25,
  }) async {
    if (waypoints.length < 2) return waypoints;

    final result = <LatLon>[];
    bool first = true;

    // Process in overlapping chunks so the route is continuous
    int i = 0;
    while (i < waypoints.length - 1) {
      final end = (i + chunkSize).clamp(0, waypoints.length);
      final chunk = waypoints.sublist(i, end);

      final segment = await _fetchSegment(chunk);
      if (first) {
        result.addAll(segment);
        first = false;
      } else {
        // Skip the first point (duplicate of the last point of previous chunk)
        if (segment.length > 1) result.addAll(segment.skip(1));
      }

      i = end - 1; // overlap by one point
    }

    return result.isEmpty ? waypoints : result;
  }

  static Future<List<LatLon>> _fetchSegment(List<LatLon> waypoints) async {
    // Build the coordinate string: lon,lat;lon,lat;...
    final coords =
        waypoints.map((p) => '${p.$2},${p.$1}').join(';');

    final uri = Uri.parse(
      '$baseUrl/route/v1/$profile/$coords'
      '?overview=full&geometries=geojson&steps=false',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return _straightLine(waypoints);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final code = json['code'] as String?;
      if (code != 'Ok') return _straightLine(waypoints);

      final routes = json['routes'] as List<dynamic>;
      if (routes.isEmpty) return _straightLine(waypoints);

      final geometry =
          routes[0]['geometry'] as Map<String, dynamic>;
      final coordinates =
          geometry['coordinates'] as List<dynamic>;

      return coordinates
          .map((c) {
            final arr = c as List<dynamic>;
            return (
              (arr[1] as num).toDouble(), // lat
              (arr[0] as num).toDouble(), // lon
            );
          })
          .toList();
    } catch (_) {
      return _straightLine(waypoints);
    }
  }

  /// Straight-line fallback: just return the waypoints themselves.
  static List<LatLon> _straightLine(List<LatLon> waypoints) => waypoints;
}
