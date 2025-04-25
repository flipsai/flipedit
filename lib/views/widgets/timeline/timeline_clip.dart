import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/resize_clip_command.dart';
import 'package:flipedit/viewmodels/commands/move_clip_command.dart';
import 'package:flipedit/viewmodels/commands/remove_clip_command.dart';
import 'package:watch_it/watch_it.dart';
import 'painters/video_frames_painter.dart';
import 'package:flipedit/services/timeline_clip_resize_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flutter/foundation.dart'; // For kTouchSlop

/// A clip in the timeline track
class TimelineClip extends StatefulWidget with WatchItStatefulWidgetMixin {
  final ClipModel clip;
  final int trackId;
  // isDragging prop kept for external compatibility / testing, but internal state is preferred
  final bool isDragging;

  const TimelineClip({
    super.key,
    required this.clip,
    required this.trackId,
    this.isDragging = false, // Add back with default value
  });

  @override
  State<TimelineClip> createState() => _TimelineClipState();
}

class _TimelineClipState extends State<TimelineClip> {
  // State for dragging/moving the entire clip
  bool _isMoving = false;
  double _moveDragStartX = 0.0;
  int _originalMoveStartFrame = 0;
  int _currentMoveFrame = 0; // Tracks visual position during move drag

  // State for resizing preview
  String? _resizingDirection; // 'left', 'right', or null
  double _resizeAccumulatedDrag = 0.0; // Raw pixel delta during resize drag
  int? _previewStartFrame; // Store original start frame during resize
  int? _previewEndFrame; // Store original end frame during resize

  // Service for resize logic
  final TimelineClipResizeService _resizeService = TimelineClipResizeService();

  // Controller for the context menu flyout
  final FlyoutController _contextMenuController = FlyoutController();

  // Define base colors for clip types
  static const Map<ClipType, Color> _clipTypeColors = {
    ClipType.video: Color(0xFF264F78), ClipType.audio: Color(0xFF498205),
    ClipType.image: Color(0xFF8764B8), ClipType.text: Color(0xFFC29008),
    ClipType.effect: Color(0xFFC50F1F),
  };

  // Helper to get appropriate contrast color
  Color _getContrastColor(Color backgroundColor) {
    final luminance = (0.299 * backgroundColor.r + 0.587 * backgroundColor.g + 0.114 * backgroundColor.b) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  void initState() {
    super.initState();
    _currentMoveFrame = widget.clip.startFrame;
  }

  @override
  void dispose() {
    _contextMenuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final editorVm = di<EditorViewModel>();
    final timelineVm = di<TimelineViewModel>();

    final selectedClipId = watchValue((EditorViewModel vm) => vm.selectedClipIdNotifier);
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final isSelected = selectedClipId == widget.clip.databaseId?.toString();

    // --- Calculate Visuals based on state (Move or Resize Preview) ---
    double dragOffset = 0.0;
    double previewWidthDelta = 0.0;
    int currentDisplayStartFrame = widget.clip.startFrame;
    int currentDisplayEndFrame = widget.clip.endFrame;
    final double pixelsPerFrame = (zoom > 0 ? 5.0 * zoom : 5.0); // Base pixels * zoom, safe default

    if (_isMoving) {
      dragOffset = (_currentMoveFrame - widget.clip.startFrame) * pixelsPerFrame;
    } else if (_resizingDirection != null && _previewStartFrame != null && _previewEndFrame != null) {
       // Calculate PREVIEW changes for RESIZE drag
      int frameDelta = (pixelsPerFrame > 0 ? (_resizeAccumulatedDrag / pixelsPerFrame) : 0).round();
      int minFrameDuration = 1;

      if (_resizingDirection == 'left') {
         int previewBoundary = (_previewStartFrame! + frameDelta).clamp(0, _previewEndFrame! - minFrameDuration);
         // Calculate delta relative to the original frame for width/offset adjustments
         int actualFrameDelta = previewBoundary - _previewStartFrame!;
         previewWidthDelta = actualFrameDelta * pixelsPerFrame;
         dragOffset = previewWidthDelta; // Offset the whole clip visually
         currentDisplayStartFrame = previewBoundary;
         currentDisplayEndFrame = _previewEndFrame!; // End frame doesn't change visually during left resize preview
      } else { // direction == 'right'
         // Calculate preview boundary, clamped
         int previewBoundary = (_previewEndFrame! + frameDelta).clamp(_previewStartFrame! + minFrameDuration, _previewStartFrame! + 1000000); // Use large upper bound
         // Calculate delta relative to original end frame
         int actualFrameDelta = previewBoundary - _previewEndFrame!;
         previewWidthDelta = actualFrameDelta * pixelsPerFrame;
         dragOffset = 0; // No offset for right resize preview
         currentDisplayStartFrame = _previewStartFrame!; // Start frame doesn't change visually
         currentDisplayEndFrame = previewBoundary;
      }
    }

    // Calculate base width and apply preview delta, ensuring minimum width
    final double clipBaseWidth = (widget.clip.durationFrames * pixelsPerFrame);
    final double finalVisualWidth = (clipBaseWidth + previewWidthDelta).clamp(pixelsPerFrame, double.infinity); // Min width 1 frame visually


    // --- UI Constants ---
    final baseClipColor = _clipTypeColors[widget.clip.type] ?? Colors.grey;
    final clipColor = baseClipColor;
    final contrastColor = _getContrastColor(clipColor);
    final selectionBorderColor = theme.accentColor.normal;
    final durationInSec = widget.clip.durationMs / 1000.0;
    final formattedDuration = durationInSec.toStringAsFixed(1);
    const double fixedClipHeight = 65.0;
    const double borderRadiusValue = 10.0;
    const double borderWidth = 2.5;
    const double shadowBlur = 12.0;


    return Transform.translate(
      offset: Offset(dragOffset, 0),
      child: SizedBox( // Control visual width for resize preview
        width: finalVisualWidth,
        child: FlyoutTarget(
          controller: _contextMenuController,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.start,
            trackpadScrollCausesScale: false,
             supportedDevices: const {
               PointerDeviceKind.touch, PointerDeviceKind.mouse,
               PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus,
             },
            onTap: () {
              editorVm.selectedClipId = widget.clip.databaseId?.toString();
            },
            // --- Drag Handling for MOVEMENT ---
            onHorizontalDragStart: (details) {
              if (_resizingDirection != null) return; // Ignore if resizing
              _moveDragStartX = details.localPosition.dx;
              _originalMoveStartFrame = widget.clip.startFrame;
              _currentMoveFrame = _originalMoveStartFrame; // Reset visual frame
              editorVm.selectedClipId = widget.clip.databaseId?.toString();
              if (_isMoving) { setState(() { _isMoving = false; }); } // Reset state if needed
            },
            onHorizontalDragUpdate: (details) {
              if (_resizingDirection != null) return; // Ignore if resizing
              final currentDragX = details.localPosition.dx;
              final dragDistance = (currentDragX - _moveDragStartX).abs();

              if (_isMoving || dragDistance > kTouchSlop) {
                if (!_isMoving) { setState(() { _isMoving = true; }); }

                if (pixelsPerFrame <= 0) return; // Safety check
                final dragDeltaInPixels = currentDragX - _moveDragStartX;
                final dragDeltaInFrames = (dragDeltaInPixels / pixelsPerFrame).round();
                final newStartFrame = _originalMoveStartFrame + dragDeltaInFrames;
                final clampedStartFrame = newStartFrame.clamp(0, 1000000000); // Clamp move

                if (_currentMoveFrame != clampedStartFrame) {
                  setState(() { _currentMoveFrame = clampedStartFrame; });
                }
              }
            },
            onHorizontalDragEnd: (details) {
              if (_resizingDirection != null) return; // Ignore if resizing
              if (_isMoving && _originalMoveStartFrame != _currentMoveFrame) {
                if (widget.clip.databaseId != null) {
                  final newStartTimeMs = ClipModel.framesToMs(_currentMoveFrame);
                  final cmd = MoveClipCommand(
                    vm: timelineVm,
                    clipId: widget.clip.databaseId!,
                    newTrackId: widget.clip.trackId,
                    newStartTimeOnTrackMs: newStartTimeMs,
                  );
                  timelineVm.runCommand(cmd); // Use runCommand
                }
              }
              setState(() { _isMoving = false; }); // Always reset move state
            },
            // --- Context Menu ---
            onSecondaryTapUp: (details) {
              editorVm.selectedClipId = widget.clip.databaseId?.toString();
              _contextMenuController.showFlyout(
                barrierDismissible: true,
                dismissWithEsc: true,
                position: details.globalPosition,
                builder: (context) => _buildContextMenu(context),
              );
            },
            // --- Clip Visual Container ---
            child: Container( // Using simple Container, AnimatedContainer might conflict with SizedBox width animation
              // height: fixedClipHeight, // Let parent dictate height
              padding: const EdgeInsets.all(borderWidth),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadiusValue),
                border: Border.all(
                  color: isSelected && _resizingDirection == null ? selectionBorderColor : clipColor.withAlpha(70),
                  width: isSelected && _resizingDirection == null ? borderWidth : 1.0,
                ),
                 boxShadow: [ // Consistent shadow application
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: shadowBlur,
                    offset: const Offset(0, 3),
                  ),
                  if (isSelected && _resizingDirection == null) // Only show selection glow if not resizing
                    BoxShadow(
                      color: selectionBorderColor.withOpacity(0.25),
                      blurRadius: shadowBlur * 1.2,
                      spreadRadius: 1.5,
                    ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [clipColor.withAlpha(210), clipColor.withAlpha(160)],
                ),
              ),
              // --- Clip Content Stack (Handles, Content, Overlay) ---
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Main content visualization (clipped by SizedBox width)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(borderRadiusValue - 2),
                    child: _buildClipContent(clipColor, contrastColor, theme),
                  ),
                  // Left resize handle
                  Positioned(
                    left: 0, top: 0, bottom: 0, width: 8,
                    child: _ResizeClipEdgeHandle(
                      direction: 'left', clip: widget.clip,
                      pixelsPerFrame: pixelsPerFrame, // Pass calculated value
                      onDragStart: () => _handleResizeStart('left'),
                      onDragUpdate: (delta) => _handleResizeUpdate(delta),
                      onDragEnd: (finalDelta) => _handleResizeEnd('left', finalDelta),
                    ),
                  ),
                  // Right resize handle
                  Positioned(
                    right: 0, top: 0, bottom: 0, width: 8,
                    child: _ResizeClipEdgeHandle(
                      direction: 'right', clip: widget.clip,
                      pixelsPerFrame: pixelsPerFrame, // Pass calculated value
                      onDragStart: () => _handleResizeStart('right'),
                      onDragUpdate: (delta) => _handleResizeUpdate(delta),
                      onDragEnd: (finalDelta) => _handleResizeEnd('right', finalDelta),
                    ),
                  ),
                  // Info overlay at bottom
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      height: 16,
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.09),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(borderRadiusValue - 1),
                          bottomRight: Radius.circular(borderRadiusValue - 1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text( // Duration
                            '${formattedDuration}s',
                            style: theme.typography.caption?.copyWith(
                              color: contrastColor.withAlpha(220), fontSize: 9, fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text( // Position / Preview
                            _resizingDirection != null
                                ? '${ClipModel.framesToMs(currentDisplayStartFrame)}ms - ${ClipModel.framesToMs(currentDisplayEndFrame)}ms' // Show time range during resize
                                : _getTimePosition(), // Show normal start time otherwise
                            style: theme.typography.caption?.copyWith(
                              color: contrastColor.withAlpha(220), fontSize: 9, fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Methods (Inside State) ---

  String _getTimePosition() {
    final startMs = widget.clip.startTimeOnTrackMs;
    final startSec = startMs / 1000.0;
    return '${startSec.toStringAsFixed(1)}s';
  }

  Widget _buildClipContent(Color clipColor, Color contrastColor, FluentThemeData theme) {
    final contentColor = contrastColor.withAlpha(200);
    final contentBackgroundColor = clipColor.withAlpha(170);
    final fileName = widget.clip.sourcePath.split('/').last;
    final fileNameNoExt = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
    const double fixedClipHeight = 65.0;

    // Simplified rendering logic for brevity - keep only one case for example
    switch (widget.clip.type) {
      case ClipType.video:
      default: // Fallback for other types
        return SizedBox(
          height: fixedClipHeight,
          child: Stack(
            children: [
              Container(
                height: fixedClipHeight,
                decoration: BoxDecoration(
                  color: contentBackgroundColor,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [clipColor.withAlpha(170), clipColor.withAlpha(140)],
                  ),
                ),
              ),
              CustomPaint(painter: VideoFramesPainter(color: contentColor.withAlpha(30)), child: const SizedBox.expand()),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.video, size: 16, color: contentColor),
                    if (widget.clip.durationFrames > 20)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(fileNameNoExt, style: theme.typography.caption?.copyWith(color: contentColor, fontSize: 8), overflow: TextOverflow.ellipsis, maxLines: 1)),
                  ],
                ),
              ),
            ],
          ),
        );
       // Add cases for other clip types here...
    }
  }

  Widget _buildContextMenu(BuildContext context) {
    final timelineVm = di<TimelineViewModel>();
    return MenuFlyout(
      items: [
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.delete),
          text: const Text('Remove Clip'),
          onPressed: () {
            Flyout.of(context).close();
            if (widget.clip.databaseId != null) {
              timelineVm.runCommand(RemoveClipCommand(vm: timelineVm, clipId: widget.clip.databaseId!));
            } else {
              logger.logError('[TimelineClip] Attempted to remove clip without databaseId', 'UI');
            }
          },
        ),
        // Add other menu items if needed
      ],
    );
  }

  // --- Resize Handle Callbacks (Inside State) ---
  void _handleResizeStart(String direction) {
    if (_isMoving) return;
    final result = _resizeService.handleResizeStart(
      isMoving: _isMoving,
      direction: direction,
      startFrame: widget.clip.startFrame,
      endFrame: widget.clip.endFrame,
    );
    setState(() {
      _resizingDirection = result['resizingDirection'];
      _resizeAccumulatedDrag = result['resizeAccumulatedDrag'];
      _previewStartFrame = result['previewStartFrame'];
      _previewEndFrame = result['previewEndFrame'];
    });
  }

  void _handleResizeUpdate(double accumulatedPixelDelta) {
    if (_resizingDirection == null) return;
    final newDrag = _resizeService.handleResizeUpdate(
      resizingDirection: _resizingDirection,
      accumulatedPixelDelta: accumulatedPixelDelta,
    );
    setState(() {
      _resizeAccumulatedDrag = newDrag;
    });
  }

  void _handleResizeEnd(String direction, double finalPixelDelta) async {
    await _resizeService.handleResizeEnd(
      resizingDirection: _resizingDirection,
      previewStartFrame: _previewStartFrame,
      previewEndFrame: _previewEndFrame,
      direction: direction,
      finalPixelDelta: finalPixelDelta,
      timelineVm: di<TimelineViewModel>(),
      clip: widget.clip,
      zoom: di<TimelineViewModel>().zoomNotifier.value,
      runCommand: (cmd) => di<TimelineViewModel>().runCommand(cmd),
    );
    setState(() {
      _resizingDirection = null;
      _resizeAccumulatedDrag = 0.0;
      _previewStartFrame = null;
      _previewEndFrame = null;
    });
  }
// END OF _TimelineClipState
}


// --- Separate Widget for the Resize Handle (File Scope) ---

class _ResizeClipEdgeHandle extends StatefulWidget {
  final String direction;
  final ClipModel clip;
  final double pixelsPerFrame; // Receive pre-calculated value based on zoom
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate; // Pass accumulated *pixel* delta
  final ValueChanged<double> onDragEnd;    // Pass final accumulated *pixel* delta

  const _ResizeClipEdgeHandle({
    required this.direction,
    required this.clip,
    required this.pixelsPerFrame, // Make required
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    Key? key, // Add Key
  }) : assert(direction == 'left' || direction == 'right'), super(key: key);

  @override
  State<_ResizeClipEdgeHandle> createState() => _ResizeClipEdgeHandleState();
}

class _ResizeClipEdgeHandleState extends State<_ResizeClipEdgeHandle> {
  double _accumulatedPixelDelta = 0.0; // Only need to track pixel delta

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bool isLeft = widget.direction == 'left';
    final Color handleColor = theme.accentColor.light.withOpacity(0.5); // Use consistent color

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          _accumulatedPixelDelta = 0; // Reset delta on new drag
          widget.onDragStart(); // Notify parent: drag started
        },
        onHorizontalDragUpdate: (details) {
          // Accumulate raw pixel delta
           _accumulatedPixelDelta += details.primaryDelta ?? 0;
           widget.onDragUpdate(_accumulatedPixelDelta); // Notify parent with current delta
           // No setState needed here unless the handle itself changes appearance during drag
        },
        onHorizontalDragEnd: (details) {
          // Final notification to parent with the total accumulated delta
          widget.onDragEnd(_accumulatedPixelDelta);
          // Reset internal state for next drag
          _accumulatedPixelDelta = 0;
        },
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            color: handleColor,
            borderRadius: BorderRadius.only(
              topLeft: isLeft ? const Radius.circular(3) : Radius.zero,
              bottomLeft: isLeft ? const Radius.circular(3) : Radius.zero,
              topRight: !isLeft ? const Radius.circular(3) : Radius.zero,
              bottomRight: !isLeft ? const Radius.circular(3) : Radius.zero,
            ),
             border: Border( // Subtle border for visual separation
              left: isLeft ? BorderSide.none : BorderSide(color: Colors.black.withOpacity(0.2), width: 0.5),
              right: !isLeft ? BorderSide.none : BorderSide(color: Colors.black.withOpacity(0.2), width: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
