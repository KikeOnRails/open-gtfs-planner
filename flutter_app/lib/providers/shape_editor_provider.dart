import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/database/gtfs_repository.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class ShapeEditState {
  final int gtfsFileId;
  final String shapeId;
  final List<LatLng> points;
  final List<List<LatLng>> undoStack;
  final Color routeColor;
  final String routeName;
  final bool isSaving;

  const ShapeEditState({
    required this.gtfsFileId,
    required this.shapeId,
    required this.points,
    this.undoStack = const [],
    this.routeColor = const Color(0xFF00AF8C),
    this.routeName = '',
    this.isSaving = false,
  });

  bool get canUndo => undoStack.isNotEmpty;

  ShapeEditState copyWith({
    List<LatLng>? points,
    List<List<LatLng>>? undoStack,
    bool? isSaving,
  }) =>
      ShapeEditState(
        gtfsFileId: gtfsFileId,
        shapeId: shapeId,
        points: points ?? this.points,
        undoStack: undoStack ?? this.undoStack,
        routeColor: routeColor,
        routeName: routeName,
        isSaving: isSaving ?? this.isSaving,
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

  /// Call before starting a drag so the whole drag is one undo step.
  void startPointDrag() {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      undoStack: [...s.undoStack, List<LatLng>.from(s.points)],
    );
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
    final pts = List<LatLng>.from(s.points);
    pts.insert(afterIndex + 1, pos);
    state = s.copyWith(
      points: List.unmodifiable(pts),
      undoStack: [...s.undoStack, List<LatLng>.from(s.points)],
    );
  }

  /// Delete point at [index]. Minimum 2 points are preserved.
  void deletePoint(int index) {
    final s = state;
    if (s == null || s.points.length <= 2) return;
    final pts = List<LatLng>.from(s.points);
    pts.removeAt(index);
    state = s.copyWith(
      points: List.unmodifiable(pts),
      undoStack: [...s.undoStack, List<LatLng>.from(s.points)],
    );
  }

  void undo() {
    final s = state;
    if (s == null || !s.canUndo) return;
    final prev = s.undoStack.last;
    state = s.copyWith(
      points: List.unmodifiable(prev),
      undoStack: s.undoStack.sublist(0, s.undoStack.length - 1),
    );
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
// Provider
// ---------------------------------------------------------------------------

final shapeEditorProvider =
    StateNotifierProvider<ShapeEditorNotifier, ShapeEditState?>(
  (_) => ShapeEditorNotifier(),
);
