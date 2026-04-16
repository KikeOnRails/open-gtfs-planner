import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

import '../../../providers/shape_editor_provider.dart';

// ---------------------------------------------------------------------------
// Main layer widget — place as last child of FlutterMap
// ---------------------------------------------------------------------------

class ShapeEditorLayer extends ConsumerWidget {
  const ShapeEditorLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editState = ref.watch(shapeEditorProvider);
    if (editState == null) return const SizedBox.shrink();

    final points = editState.points;
    final color = editState.routeColor;
    final camera = MapCamera.of(context);

    // Only show midpoint handles when there aren't too many points
    final showMidpoints = points.length < 150;

    // --- Midpoint markers (insert new points) ---
    final midMarkers = <Marker>[];
    if (showMidpoints) {
      for (int i = 0; i < points.length - 1; i++) {
        final mid = LatLng(
          (points[i].latitude + points[i + 1].latitude) / 2,
          (points[i].longitude + points[i + 1].longitude) / 2,
        );
        final insertAfter = i;
        midMarkers.add(Marker(
          point: mid,
          width: 16,
          height: 16,
          child: _MidpointHandle(
            insertAfterIndex: insertAfter,
            position: mid,
          ),
        ));
      }
    }

    // --- Main drag handles ---
    final handleMarkers = <Marker>[];
    for (int i = 0; i < points.length; i++) {
      handleMarkers.add(Marker(
        point: points[i],
        width: 24,
        height: 24,
        child: _DragHandle(
          pointIndex: i,
          currentPos: points[i],
          color: color,
          camera: camera,
        ),
      ));
    }

    return Stack(children: [
      // Editing polyline (orange overlay on top of original)
      PolylineLayer(polylines: [
        Polyline(
          points: points,
          color: Colors.black.withOpacity(0.4),
          strokeWidth: 6,
        ),
        Polyline(
          points: points,
          color: Colors.orange,
          strokeWidth: 3.5,
        ),
      ]),
      // Midpoint handles (below main to not block drag handles)
      if (midMarkers.isNotEmpty) MarkerLayer(markers: midMarkers),
      // Main drag handles
      MarkerLayer(markers: handleMarkers),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Draggable point handle
// ---------------------------------------------------------------------------

class _DragHandle extends ConsumerStatefulWidget {
  final int pointIndex;
  final LatLng currentPos;
  final Color color;
  final MapCamera camera;

  const _DragHandle({
    required this.pointIndex,
    required this.currentPos,
    required this.color,
    required this.camera,
  });

  @override
  ConsumerState<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends ConsumerState<_DragHandle> {
  bool _isDragging = false;
  bool _longPressActive = false;

  @override
  Widget build(BuildContext context) {
    final size = _isDragging ? 28.0 : 22.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        setState(() => _isDragging = true);
        ref.read(shapeEditorProvider.notifier).startPointDrag();
      },
      onPanUpdate: (details) {
        // Convert screen delta to new LatLng using current camera
        final camera = MapCamera.of(context);
        final currentScreen =
            camera.latLngToScreenPoint(widget.currentPos);
        final newScreen = math.Point<double>(
          currentScreen.x + details.delta.dx,
          currentScreen.y + details.delta.dy,
        );
        final newLatLng = camera.pointToLatLng(newScreen);
        ref
            .read(shapeEditorProvider.notifier)
            .movePoint(widget.pointIndex, newLatLng);
      },
      onPanEnd: (_) => setState(() => _isDragging = false),
      onPanCancel: () => setState(() => _isDragging = false),
      onLongPressStart: (_) => setState(() => _longPressActive = true),
      onLongPressEnd: (_) {
        setState(() => _longPressActive = false);
        ref
            .read(shapeEditorProvider.notifier)
            .deletePoint(widget.pointIndex);
      },
      onSecondaryTap: () {
        ref
            .read(shapeEditorProvider.notifier)
            .deletePoint(widget.pointIndex);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _longPressActive
              ? Colors.red[100]
              : (_isDragging ? Colors.white : Colors.white),
          shape: BoxShape.circle,
          border: Border.all(
            color: _longPressActive
                ? Colors.red
                : (_isDragging ? Colors.orange : widget.color),
            width: _isDragging ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _isDragging
                  ? Colors.orange.withOpacity(0.6)
                  : Colors.black.withOpacity(0.35),
              blurRadius: _isDragging ? 10 : 4,
              spreadRadius: _isDragging ? 2 : 0,
            ),
          ],
        ),
        child: _isDragging
            ? const Icon(Icons.open_with, size: 12, color: Colors.orange)
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Midpoint handle (tap to insert new point)
// ---------------------------------------------------------------------------

class _MidpointHandle extends ConsumerWidget {
  final int insertAfterIndex;
  final LatLng position;

  const _MidpointHandle({
    required this.insertAfterIndex,
    required this.position,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ref
            .read(shapeEditorProvider.notifier)
            .insertPoint(insertAfterIndex, position);
      },
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.orange.withOpacity(0.8),
            width: 1.5,
          ),
        ),
        child: const Icon(Icons.add, size: 10, color: Colors.orange),
      ),
    );
  }
}
