import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/clip_transform.dart';
import 'package:flipedit/utils/video_coordinate_converter.dart';
import 'package:flipedit/utils/logger.dart';

enum ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

class ClipTransformOverlay extends StatefulWidget {
  final ClipModel clip;
  final Size videoSize;
  final Size screenSize;
  final Function(ClipTransform) onTransformChanged;
  final Function()? onTransformStart;
  final Function()? onTransformEnd;
  final Function()? onDeselect;

  const ClipTransformOverlay({
    Key? key,
    required this.clip,
    required this.videoSize,
    required this.screenSize,
    required this.onTransformChanged,
    this.onTransformStart,
    this.onTransformEnd,
    this.onDeselect,
  }) : super(key: key);

  @override
  State<ClipTransformOverlay> createState() => _ClipTransformOverlayState();
}

class _ClipTransformOverlayState extends State<ClipTransformOverlay> {
  late Rect clipRect;
  bool isDragging = false;
  bool isResizing = false;
  ResizeHandle? currentResizeHandle;
  Offset? dragOffset;
  Rect? initialRect;
  bool actionLocked = false;
  late double originalAspectRatio;
  bool isShiftPressed = false;
  
  // Throttling for Rust updates
  static const Duration _updateThrottleInterval = Duration(milliseconds: 16); // ~60 FPS
  DateTime _lastUpdateTime = DateTime.now();
  bool _hasPendingUpdate = false;

  @override
  void initState() {
    super.initState();
    _updateClipRect();
    _calculateOriginalAspectRatio();
    _setupKeyboardListener();
  }

  @override
  void dispose() {
    _removeKeyboardListener();
    super.dispose();
  }

  @override
  void didUpdateWidget(ClipTransformOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip != widget.clip || 
        oldWidget.videoSize != widget.videoSize ||
        oldWidget.screenSize != widget.screenSize) {
      _updateClipRect();
      _calculateOriginalAspectRatio();
    }
  }

  void _updateClipRect() {
    clipRect = VideoCoordinateConverter.videoToScreen(
      widget.clip,
      widget.videoSize,
      widget.screenSize,
    );
  }

  void _calculateOriginalAspectRatio() {
    // Use the actual video dimensions, not the current clip preview size
    originalAspectRatio = widget.videoSize.width / widget.videoSize.height;
  }

  void _setupKeyboardListener() {
    RawKeyboard.instance.addListener(_onKeyEvent);
  }

  void _removeKeyboardListener() {
    RawKeyboard.instance.removeListener(_onKeyEvent);
  }

  void _onKeyEvent(RawKeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.shiftLeft || 
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      setState(() {
        isShiftPressed = event is RawKeyDownEvent;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        size: widget.screenSize,
        painter: TransformBoxPainter(
          clipRect: clipRect,
          isSelected: true,
          showHandles: true,
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    final localPosition = details.localPosition;
    initialRect = clipRect;
    
    widget.onTransformStart?.call();
    
    // Check if we're on a resize handle
    final resizeHandle = _getResizeHandle(localPosition);
    if (resizeHandle != null) {
      setState(() {
        isResizing = true;
        currentResizeHandle = resizeHandle;
        isDragging = false;
        actionLocked = true;
      });
      logDebug('Started resizing with handle: $resizeHandle', 'ClipTransformOverlay');
    } else if (clipRect.contains(localPosition)) {
      setState(() {
        isDragging = true;
        isResizing = false;
        dragOffset = localPosition - clipRect.topLeft;
        actionLocked = true;
      });
      logDebug('Started dragging clip', 'ClipTransformOverlay');
    } else {
      // Clicked outside the rectangle - deselect
      widget.onDeselect?.call();
      logDebug('Clicked outside rectangle, deselecting clip', 'ClipTransformOverlay');
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!actionLocked) return;
    
    // Throttle updates to improve performance
    if (isDragging && dragOffset != null) {
      _updatePosition(details.localPosition - dragOffset!);
    } else if (isResizing && currentResizeHandle != null && initialRect != null) {
      _updateSize(details.localPosition, currentResizeHandle!, initialRect!);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      isDragging = false;
      isResizing = false;
      currentResizeHandle = null;
      dragOffset = null;
      initialRect = null;
      actionLocked = false;
    });
    
    // Send final position to Rust immediately on end
    _notifyTransformChanged();
    
    widget.onTransformEnd?.call();
    logDebug('Ended transform operation', 'ClipTransformOverlay');
  }

  void _updatePosition(Offset newPosition) {
    // Clamp position to keep rectangle within bounds without resizing
    final clampedX = newPosition.dx.clamp(
      0.0, 
      widget.screenSize.width - clipRect.width
    );
    final clampedY = newPosition.dy.clamp(
      0.0, 
      widget.screenSize.height - clipRect.height
    );
    
    final newRect = Rect.fromLTWH(
      clampedX,
      clampedY,
      clipRect.width,
      clipRect.height,
    );
    
    // Only update if position actually changed
    if (newRect != clipRect) {
      clipRect = newRect;
      // Defer state update and coordinate conversion to reduce lag
      _deferredNotifyTransformChanged();
    }
  }

  void _updateSize(Offset currentPosition, ResizeHandle handle, Rect initialRect) {
    Rect newRect = initialRect;
    
    switch (handle) {
      case ResizeHandle.topLeft:
        newRect = Rect.fromLTRB(
          currentPosition.dx,
          currentPosition.dy,
          initialRect.right,
          initialRect.bottom,
        );
        break;
      case ResizeHandle.topRight:
        newRect = Rect.fromLTRB(
          initialRect.left,
          currentPosition.dy,
          currentPosition.dx,
          initialRect.bottom,
        );
        break;
      case ResizeHandle.bottomLeft:
        newRect = Rect.fromLTRB(
          currentPosition.dx,
          initialRect.top,
          initialRect.right,
          currentPosition.dy,
        );
        break;
      case ResizeHandle.bottomRight:
        newRect = Rect.fromLTRB(
          initialRect.left,
          initialRect.top,
          currentPosition.dx,
          currentPosition.dy,
        );
        break;
      case ResizeHandle.top:
        newRect = Rect.fromLTRB(
          initialRect.left,
          currentPosition.dy,
          initialRect.right,
          initialRect.bottom,
        );
        break;
      case ResizeHandle.bottom:
        newRect = Rect.fromLTRB(
          initialRect.left,
          initialRect.top,
          initialRect.right,
          currentPosition.dy,
        );
        break;
      case ResizeHandle.left:
        newRect = Rect.fromLTRB(
          currentPosition.dx,
          initialRect.top,
          initialRect.right,
          initialRect.bottom,
        );
        break;
      case ResizeHandle.right:
        newRect = Rect.fromLTRB(
          initialRect.left,
          initialRect.top,
          currentPosition.dx,
          initialRect.bottom,
        );
        break;
    }
    
    // Apply aspect ratio constraint unless shift is pressed
    if (!isShiftPressed) {
      newRect = _constrainToAspectRatio(newRect, handle, initialRect);
    }
    
    // Ensure minimum size
    const minSize = 20.0;
    if (newRect.width < minSize || newRect.height < minSize) {
      return;
    }
    
    final clampedRect = VideoCoordinateConverter.clampToBounds(newRect, widget.screenSize);
    
    // Only update if rect actually changed
    if (clampedRect != clipRect) {
      clipRect = clampedRect;
      // Defer state update and coordinate conversion to reduce lag
      _deferredNotifyTransformChanged();
    }
  }

  Rect _constrainToAspectRatio(Rect rect, ResizeHandle handle, Rect initialRect) {
    double targetWidth = rect.width;
    double targetHeight = rect.height;
    
    // Calculate constrained dimensions based on aspect ratio
    double constrainedWidth = targetHeight * originalAspectRatio;
    double constrainedHeight = targetWidth / originalAspectRatio;
    
    // Choose the constraint that results in a smaller change
    bool useWidthConstraint = (constrainedWidth - targetWidth).abs() < (constrainedHeight - targetHeight).abs();
    
    if (useWidthConstraint) {
      targetWidth = constrainedWidth;
    } else {
      targetHeight = constrainedHeight;
    }
    
    // Adjust the rectangle based on the resize handle
    switch (handle) {
      case ResizeHandle.topLeft:
        return Rect.fromLTRB(
          rect.right - targetWidth,
          rect.bottom - targetHeight,
          rect.right,
          rect.bottom,
        );
      case ResizeHandle.topRight:
        return Rect.fromLTRB(
          rect.left,
          rect.bottom - targetHeight,
          rect.left + targetWidth,
          rect.bottom,
        );
      case ResizeHandle.bottomLeft:
        return Rect.fromLTRB(
          rect.right - targetWidth,
          rect.top,
          rect.right,
          rect.top + targetHeight,
        );
      case ResizeHandle.bottomRight:
        return Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.left + targetWidth,
          rect.top + targetHeight,
        );
      case ResizeHandle.top:
        return Rect.fromLTRB(
          rect.center.dx - targetWidth / 2,
          rect.bottom - targetHeight,
          rect.center.dx + targetWidth / 2,
          rect.bottom,
        );
      case ResizeHandle.bottom:
        return Rect.fromLTRB(
          rect.center.dx - targetWidth / 2,
          rect.top,
          rect.center.dx + targetWidth / 2,
          rect.top + targetHeight,
        );
      case ResizeHandle.left:
        return Rect.fromLTRB(
          rect.right - targetWidth,
          rect.center.dy - targetHeight / 2,
          rect.right,
          rect.center.dy + targetHeight / 2,
        );
      case ResizeHandle.right:
        return Rect.fromLTRB(
          rect.left,
          rect.center.dy - targetHeight / 2,
          rect.left + targetWidth,
          rect.center.dy + targetHeight / 2,
        );
    }
  }

  void _notifyTransformChanged() {
    final videoTransform = VideoCoordinateConverter.screenToVideo(
      clipRect,
      widget.videoSize,
      widget.screenSize,
    );
    widget.onTransformChanged(videoTransform);
  }
  
  // Throttled update to reduce Rust calls during drag operations
  void _deferredNotifyTransformChanged() {
    // Update the UI immediately for visual feedback
    if (mounted) {
      setState(() {});
    }
    
    // Throttle Rust updates to avoid lag
    final now = DateTime.now();
    if (now.difference(_lastUpdateTime) >= _updateThrottleInterval) {
      _lastUpdateTime = now;
      _hasPendingUpdate = false;
      
      // Immediate update for first call or after throttle interval
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notifyTransformChanged();
        }
      });
    } else if (!_hasPendingUpdate) {
      _hasPendingUpdate = true;
      
      // Schedule delayed update
      Future.delayed(_updateThrottleInterval - now.difference(_lastUpdateTime), () {
        if (mounted && _hasPendingUpdate) {
          _lastUpdateTime = DateTime.now();
          _hasPendingUpdate = false;
          _notifyTransformChanged();
        }
      });
    }
  }

  ResizeHandle? _getResizeHandle(Offset position) {
    const handleSize = 12.0;
    
    // Corner handles
    if (_isNearPoint(position, clipRect.topLeft, handleSize)) {
      return ResizeHandle.topLeft;
    }
    if (_isNearPoint(position, clipRect.topRight, handleSize)) {
      return ResizeHandle.topRight;
    }
    if (_isNearPoint(position, clipRect.bottomLeft, handleSize)) {
      return ResizeHandle.bottomLeft;
    }
    if (_isNearPoint(position, clipRect.bottomRight, handleSize)) {
      return ResizeHandle.bottomRight;
    }
    
    // Edge handles
    if (_isNearPoint(position, Offset(clipRect.center.dx, clipRect.top), handleSize)) {
      return ResizeHandle.top;
    }
    if (_isNearPoint(position, Offset(clipRect.center.dx, clipRect.bottom), handleSize)) {
      return ResizeHandle.bottom;
    }
    if (_isNearPoint(position, Offset(clipRect.left, clipRect.center.dy), handleSize)) {
      return ResizeHandle.left;
    }
    if (_isNearPoint(position, Offset(clipRect.right, clipRect.center.dy), handleSize)) {
      return ResizeHandle.right;
    }
    
    return null;
  }

  bool _isNearPoint(Offset position, Offset target, double threshold) {
    return (position - target).distance <= threshold;
  }
}

class TransformBoxPainter extends CustomPainter {
  final Rect clipRect;
  final bool isSelected;
  final bool showHandles;
  
  // Cache Paint objects to avoid recreating them
  static final Paint _borderPaint = Paint()
    ..color = Colors.blue
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;
    
  static final Paint _handlePaint = Paint()
    ..color = Colors.blue
    ..style = PaintingStyle.fill;
    
  static final Paint _handleBorderPaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;
    
  static final Paint _textBgPaint = Paint()
    ..color = Colors.black54;

  TransformBoxPainter({
    required this.clipRect,
    required this.isSelected,
    required this.showHandles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isSelected) return;

    // Draw the transform box border
    canvas.drawRect(clipRect, _borderPaint);

    if (showHandles) {
      const handleSize = 8.0;
      
      // Corner handles
      final corners = [
        clipRect.topLeft,
        clipRect.topRight,
        clipRect.bottomLeft,
        clipRect.bottomRight,
      ];
      
      for (final corner in corners) {
        canvas.drawCircle(corner, handleSize / 2, _handlePaint);
        canvas.drawCircle(corner, handleSize / 2, _handleBorderPaint);
      }
      
      // Edge handles
      final edges = [
        Offset(clipRect.center.dx, clipRect.top),    // top
        Offset(clipRect.center.dx, clipRect.bottom), // bottom
        Offset(clipRect.left, clipRect.center.dy),   // left
        Offset(clipRect.right, clipRect.center.dy),  // right
      ];
      
      for (final edge in edges) {
        final handleRect = Rect.fromCenter(
          center: edge,
          width: handleSize,
          height: handleSize,
        );
        canvas.drawRect(handleRect, _handlePaint);
        canvas.drawRect(handleRect, _handleBorderPaint);
      }
    }

    // Draw clip info text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${clipRect.width.toInt()}×${clipRect.height.toInt()}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    final textOffset = Offset(
      clipRect.left,
      clipRect.top - textPainter.height - 4,
    );
    
    // Draw text background
    canvas.drawRect(
      Rect.fromLTWH(
        textOffset.dx - 2,
        textOffset.dy - 2,
        textPainter.width + 4,
        textPainter.height + 4,
      ),
      _textBgPaint,
    );
    
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant TransformBoxPainter oldDelegate) {
    return clipRect != oldDelegate.clipRect ||
           isSelected != oldDelegate.isSelected ||
           showHandles != oldDelegate.showHandles;
  }
}