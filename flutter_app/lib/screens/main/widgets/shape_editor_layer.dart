import 'package:flutter/gestures.dart';
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
    final mode = editState.mode;
    final isDeleteMode = mode == ShapeEditMode.delete;

    // Only show midpoint handles in normal mode and when not too many points
    final showMidpoints = mode == ShapeEditMode.normal && points.length < 200;

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
          key: ValueKey('mid_${points.length}_$i'),
          point: mid,
          width: 18,
          height: 18,
          child: _MidpointHandle(
            key: ValueKey('mh_${points.length}_$i'),
            insertAfterIndex: insertAfter,
            position: mid,
          ),
        ));
      }
    }

    // --- Main drag handles ---
    final handleMarkers = <Marker>[];
    for (int i = 0; i < points.length; i++) {
      final isFirst = i == 0;
      final isLast = i == points.length - 1;
      handleMarkers.add(Marker(
        key: ValueKey('handle_${points.length}_$i'),
        point: points[i],
        width: (isFirst || isLast) ? 28 : 24,
        height: (isFirst || isLast) ? 28 : 24,
        child: _DragHandle(
          key: ValueKey('dh_${points.length}_$i'),
          pointIndex: i,
          currentPos: points[i],
          color: color,
          camera: camera,
          isFirst: isFirst,
          isLast: isLast,
          isDeleteMode: isDeleteMode,
        ),
      ));
    }

    // Cursor for append/prepend modes
    final showModeCursor =
        mode == ShapeEditMode.append || mode == ShapeEditMode.prepend;

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
          color: isDeleteMode ? Colors.red[300]! : Colors.orange,
          strokeWidth: 3.5,
        ),
      ]),
      // Midpoint handles (below main to not block drag handles)
      if (midMarkers.isNotEmpty) MarkerLayer(markers: midMarkers),
      // Main drag handles
      MarkerLayer(markers: handleMarkers),
      // Mode overlay hint (append/prepend)
      if (showModeCursor)
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: mode == ShapeEditMode.append
                      ? Colors.green.withOpacity(0.35)
                      : Colors.blue.withOpacity(0.35),
                  width: 2.5,
                ),
              ),
            ),
          ),
        ),
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
  final bool isFirst;
  final bool isLast;
  final bool isDeleteMode;

  const _DragHandle({
    super.key,
    required this.pointIndex,
    required this.currentPos,
    required this.color,
    required this.camera,
    this.isFirst = false,
    this.isLast = false,
    this.isDeleteMode = false,
  });

  @override
  ConsumerState<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends ConsumerState<_DragHandle> {
  bool _isDragging = false;
  bool _isHovered = false;

  // Absolute position tracking — avoids delta-drift and gesture-arena conflicts
  Offset? _pointerDownGlobal;
  LatLng? _dragStartLatLng;

  Color get _borderColor {
    if (widget.isDeleteMode) return Colors.red;
    if (widget.isFirst) return Colors.green[400]!;
    if (widget.isLast) return Colors.red[400]!;
    if (_isDragging) return Colors.orange;
    return widget.color;
  }

  Color get _fillColor {
    if (widget.isDeleteMode && _isHovered) return Colors.red[100]!;
    if (widget.isFirst) return const Color(0xFFE8F5E9);
    if (widget.isLast) return const Color(0xFFFFEBEE);
    return Colors.white;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.isDeleteMode) return;
    // Only react to primary (left) button
    if (event.buttons != kPrimaryButton) return;
    _pointerDownGlobal = event.position;
    _dragStartLatLng = widget.currentPos;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (widget.isDeleteMode) return;
    if (_pointerDownGlobal == null || _dragStartLatLng == null) return;

    final delta = event.position - _pointerDownGlobal!;
    // Only start drag tracking after moving at least 3 px to avoid accidental drags
    if (!_isDragging && delta.distance < 3) return;

    if (!_isDragging) {
      setState(() => _isDragging = true);
      ref.read(shapeEditorProvider.notifier).startPointDrag();
    }

    // Use the camera to convert: start screen pos + total offset → new LatLng
    final camera = MapCamera.of(context);
    final startScreen = camera.latLngToScreenPoint(_dragStartLatLng!);
    final newScreen = math.Point<double>(
      startScreen.x + delta.dx,
      startScreen.y + delta.dy,
    );
    ref
        .read(shapeEditorProvider.notifier)
        .movePoint(widget.pointIndex, camera.pointToLatLng(newScreen));
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDragging) {
      ref.read(shapeEditorProvider.notifier).endPointDrag();
    }
    setState(() => _isDragging = false);
    _pointerDownGlobal = null;
    _dragStartLatLng = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_isDragging) {
      ref.read(shapeEditorProvider.notifier).endPointDrag();
    }
    setState(() => _isDragging = false);
    _pointerDownGlobal = null;
    _dragStartLatLng = null;
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = (widget.isFirst || widget.isLast) ? 26.0 : 22.0;
    final size = _isDragging ? baseSize + 8 : baseSize;
    return MouseRegion(
      cursor: widget.isDeleteMode
          ? SystemMouseCursors.forbidden
          : (_isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab),
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Tap for delete mode
          onTap: widget.isDeleteMode
              ? () => ref
                  .read(shapeEditorProvider.notifier)
                  .deletePoint(widget.pointIndex)
              : null,
          // Right-click to delete in normal mode
          onSecondaryTap: () => ref
              .read(shapeEditorProvider.notifier)
              .deletePoint(widget.pointIndex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _fillColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: _borderColor,
                width: _isDragging ? 3 : (widget.isFirst || widget.isLast) ? 2.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isDragging
                      ? Colors.orange.withOpacity(0.7)
                      : (widget.isFirst
                          ? Colors.green.withOpacity(0.4)
                          : widget.isLast
                              ? Colors.red.withOpacity(0.4)
                              : Colors.black.withOpacity(0.3)),
                  blurRadius: _isDragging ? 14 : (widget.isFirst || widget.isLast) ? 6 : 4,
                  spreadRadius: _isDragging ? 3 : 0,
                ),
              ],
            ),
            child: Center(
              child: _isDragging
                  ? const Icon(Icons.open_with, size: 12, color: Colors.orange)
                  : widget.isDeleteMode
                      ? Icon(Icons.close, size: 10, color: Colors.red[400])
                      : widget.isFirst
                          ? Icon(Icons.arrow_forward, size: 10, color: Colors.green[600])
                          : widget.isLast
                              ? Icon(Icons.stop, size: 10, color: Colors.red[400])
                              : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Midpoint handle (tap or drag to insert new point)
// ---------------------------------------------------------------------------

class _MidpointHandle extends ConsumerStatefulWidget {
  final int insertAfterIndex;
  final LatLng position;

  const _MidpointHandle({
    super.key,
    required this.insertAfterIndex,
    required this.position,
  });

  @override
  ConsumerState<_MidpointHandle> createState() => _MidpointHandleState();
}

class _MidpointHandleState extends ConsumerState<_MidpointHandle> {
  bool _isDragging = false;
  int? _insertedIndex;

  Offset? _pointerDownGlobal;
  LatLng? _insertedStartLatLng;

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    _pointerDownGlobal = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownGlobal == null) return;
    final delta = event.position - _pointerDownGlobal!;

    if (!_isDragging && delta.distance < 4) return;

    if (!_isDragging) {
      // Insert the point, then start dragging it
      setState(() => _isDragging = true);
      ref
          .read(shapeEditorProvider.notifier)
          .insertPoint(widget.insertAfterIndex, widget.position);
      _insertedIndex = widget.insertAfterIndex + 1;
      _insertedStartLatLng = widget.position;
      ref.read(shapeEditorProvider.notifier).startPointDrag();
    }

    if (_insertedIndex == null || _insertedStartLatLng == null) return;
    final camera = MapCamera.of(context);
    final startScreen = camera.latLngToScreenPoint(_insertedStartLatLng!);
    final newScreen = math.Point<double>(
      startScreen.x + delta.dx,
      startScreen.y + delta.dy,
    );
    ref
        .read(shapeEditorProvider.notifier)
        .movePoint(_insertedIndex!, camera.pointToLatLng(newScreen));
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDragging) {
      ref.read(shapeEditorProvider.notifier).endPointDrag();
    }
    setState(() {
      _isDragging = false;
      _insertedIndex = null;
      _insertedStartLatLng = null;
    });
    _pointerDownGlobal = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_isDragging) {
      ref.read(shapeEditorProvider.notifier).endPointDrag();
    }
    setState(() {
      _isDragging = false;
      _insertedIndex = null;
      _insertedStartLatLng = null;
    });
    _pointerDownGlobal = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.cell,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            ref
                .read(shapeEditorProvider.notifier)
                .insertPoint(widget.insertAfterIndex, widget.position);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: _isDragging ? 22 : 16,
            height: _isDragging ? 22 : 16,
            decoration: BoxDecoration(
              color: _isDragging
                  ? Colors.orange.withOpacity(0.9)
                  : Colors.white.withOpacity(0.75),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.orange.withOpacity(0.85),
                width: _isDragging ? 2.5 : 1.5,
              ),
              boxShadow: _isDragging
                  ? [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: Icon(
              _isDragging ? Icons.open_with : Icons.add,
              size: _isDragging ? 12 : 10,
              color: _isDragging ? Colors.white : Colors.orange,
            ),
          ),
        ),
      ),
    );
  }
}
