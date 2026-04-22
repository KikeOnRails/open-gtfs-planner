import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/database/gtfs_repository.dart';

// ---------------------------------------------------------------------------
// Edit mode
// ---------------------------------------------------------------------------

enum ShapeEditMode {
  /// Default: drag points to move, midpoint tap/drag to insert, right-click to delete
  normal,

  /// Click on any point to delete it immediately (visual hint: red handles)
  delete,

  /// Click anywhere on the map to append a point at the end of the shape
  append,

  /// Click anywhere on the map to prepend a point at the beginning of the shape
  prepend,
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class ShapeEditState {
  final int gtfsFileId;
  final String shapeId;
  final List<LatLng> points;
  final List<List<LatLng>> undoStack;
  final List<List<LatLng>> redoStack;
  final Color routeColor;
  final String routeName;
  final bool isSaving;
  final ShapeEditMode mode;
  /// True while the user is actively dragging a point (suppresses map pan).
  final bool isDraggingPoint;

  const ShapeEditState({
    required this.gtfsFileId,
    required this.shapeId,
    required this.points,
    this.undoStack = const [],
    this.redoStack = const [],
    this.routeColor = const Color(0xFF00AF8C),
    this.routeName = '',
    this.isSaving = false,
    this.mode = ShapeEditMode.normal,
    this.isDraggingPoint = false,
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  ShapeEditState copyWith({
    List<LatLng>? points,
    List<List<LatLng>>? undoStack,
    List<List<LatLng>>? redoStack,
    bool? isSaving,
    ShapeEditMode? mode,
    bool? isDraggingPoint,
  }) =>
      ShapeEditState(
        gtfsFileId: gtfsFileId,
        shapeId: shapeId,
        points: points ?? this.points,
        undoStack: undoStack ?? this.undoStack,
        redoStack: redoStack ?? this.redoStack,
        routeColor: routeColor,
        routeName: routeName,
        isSaving: isSaving ?? this.isSaving,
        mode: mode ?? this.mode,
        isDraggingPoint: isDraggingPoint ?? this.isDraggingPoint,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ShapeEditorNotifier extends StateNotifier<ShapeEditState?> {
  ShapeEditorNotifier() : super(null);

  void startEditing({
    required int gtfsFileId,
    required String shapeId,
    required List<LatLng> points,
    Color routeColor = const Color(0xFF00AF8C),
    String routeName = '',
  }) {
    state = ShapeEditState(
      gtfsFileId: gtfsFileId,
      shapeId: shapeId,
      points: List.unmodifiable(List<LatLng>.from(points)),
      routeColor: routeColor,
      routeName: routeName,
    );
  }

  void setMode(ShapeEditMode mode) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(mode: mode);
  }

  // ---- Undo / Redo --------------------------------------------------------

  /// Push current points onto the undo stack and clear the redo stack.
  void _pushUndo(ShapeEditState s) {
    state = s.copyWith(
      undoStack: [...s.undoStack, List<LatLng>.from(s.points)],
      redoStack: const [],
    );
  }

  void undo() {
    final s = state;
    if (s == null || !s.canUndo) return;
    final prev = s.undoStack.last;
    state = s.copyWith(
      points: List.unmodifiable(prev),
      undoStack: s.undoStack.sublist(0, s.undoStack.length - 1),
      redoStack: [List<LatLng>.from(s.points), ...s.redoStack],
    );
  }

  void redo() {
    final s = state;
    if (s == null || !s.canRedo) return;
    final next = s.redoStack.first;
    state = s.copyWith(
      points: List.unmodifiable(next),
      undoStack: [...s.undoStack, List<LatLng>.from(s.points)],
      redoStack: s.redoStack.sublist(1),
    );
  }

  // ---- Point operations ---------------------------------------------------

  /// Call before starting a drag so the whole drag is one undo step.
  void startPointDrag() {
    final s = state;
    if (s == null) return;
    _pushUndo(s);
    // Also mark dragging so map pan can be disabled
    state = state!.copyWith(isDraggingPoint: true);
  }

  /// Call when a drag ends to re-enable map pan.
  void endPointDrag() {
    final s = state;
    if (s == null) return;
    state = s.copyWith(isDraggingPoint: false);
  }

  /// Update point position (called continuously during drag, no new undo entry).
  void movePoint(int index, LatLng newPos) {
    final s = state;
    if (s == null || index < 0 || index >= s.points.length) return;
    final pts = List<LatLng>.from(s.points);
    pts[index] = newPos;
    state = s.copyWith(points: List.unmodifiable(pts));
  }

  /// Insert a new point after [afterIndex].
  void insertPoint(int afterIndex, LatLng pos) {
    final s = state;
    if (s == null) return;
    _pushUndo(s);
    final fresh = state!;
    final pts = List<LatLng>.from(fresh.points);
    pts.insert(afterIndex + 1, pos);
    state = fresh.copyWith(points: List.unmodifiable(pts));
  }

  /// Append a point at the end of the shape.
  void appendPoint(LatLng pos) {
    final s = state;
    if (s == null) return;
    _pushUndo(s);
    final fresh = state!;
    final pts = List<LatLng>.from(fresh.points)..add(pos);
    state = fresh.copyWith(points: List.unmodifiable(pts));
  }

  /// Prepend a point at the beginning of the shape.
  void prependPoint(LatLng pos) {
    final s = state;
    if (s == null) return;
    _pushUndo(s);
    final fresh = state!;
    final pts = [pos, ...fresh.points];
    state = fresh.copyWith(points: List.unmodifiable(pts));
  }

  /// Delete point at [index]. Minimum 2 points are preserved.
  void deletePoint(int index) {
    final s = state;
    if (s == null || s.points.length <= 2) return;
    _pushUndo(s);
    final fresh = state!;
    final pts = List<LatLng>.from(fresh.points);
    pts.removeAt(index);
    state = fresh.copyWith(points: List.unmodifiable(pts));
  }

  /// Simplify shape using Ramer-Douglas-Peucker algorithm.
  /// [toleranceMeters] is the maximum allowed deviation in metres.
  void simplify(double toleranceMeters) {
    final s = state;
    if (s == null || s.points.length <= 2) return;
    _pushUndo(s);
    final fresh = state!;
    final simplified = _rdp(fresh.points, toleranceMeters);
    if (simplified.length >= 2) {
      state = fresh.copyWith(points: List.unmodifiable(simplified));
    }
  }

  void cancel() {
    state = null;
  }

  Future<bool> save() async {
    final s = state;
    if (s == null) return false;
    state = s.copyWith(isSaving: true);
    try {
      await GtfsRepository.updateShapePoints(s.gtfsFileId, s.shapeId, s.points);
      state = null;
      return true;
    } catch (_) {
      state = s.copyWith(isSaving: false);
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Ramer-Douglas-Peucker simplification
// ---------------------------------------------------------------------------

List<LatLng> _rdp(List<LatLng> points, double epsilonMeters) {
  if (points.length <= 2) return points;

  double maxDist = 0;
  int maxIndex = 0;

  for (int i = 1; i < points.length - 1; i++) {
    final d =
        _perpendicularDistanceMeters(points[i], points.first, points.last);
    if (d > maxDist) {
      maxDist = d;
      maxIndex = i;
    }
  }

  if (maxDist > epsilonMeters) {
    final left = _rdp(points.sublist(0, maxIndex + 1), epsilonMeters);
    final right = _rdp(points.sublist(maxIndex), epsilonMeters);
    return [...left.sublist(0, left.length - 1), ...right];
  } else {
    return [points.first, points.last];
  }
}

double _perpendicularDistanceMeters(LatLng p, LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat = (a.latitude + b.latitude) / 2 * math.pi / 180;
  final scale = math.cos(lat);

  final ax = a.longitude * scale;
  final ay = a.latitude;
  final bx = b.longitude * scale;
  final by = b.latitude;
  final px = p.longitude * scale;
  final py = p.latitude;

  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) {
    final dlat = (py - ay) * r * math.pi / 180;
    final dlon = (px - ax) * scale * r * math.pi / 180;
    return math.sqrt(dlat * dlat + dlon * dlon);
  }
  final cross = (px - ax) * dy - (py - ay) * dx;
  return (cross.abs() / math.sqrt(len2)) * r * math.pi / 180;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final shapeEditorProvider =
    StateNotifierProvider<ShapeEditorNotifier, ShapeEditState?>(
  (_) => ShapeEditorNotifier(),
);
