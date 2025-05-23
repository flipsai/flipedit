import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/move_clip_command.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/timeline_clip_resize_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/timeline_logic_service.dart';
import 'package:flipedit/services/clip_update_service.dart';

// Import extracted components
import 'resize_clip_handle.dart';
import 'clip_content_renderer.dart';
import 'clip_context_menu.dart';

/// A clip in the timeline track
class TimelineClip extends StatefulWidget with WatchItStatefulWidgetMixin {
  final ClipModel clip;
  final int trackId;
  // isDragging prop kept for external compatibility / testing, but internal state is preferred
  final bool isDragging;
  // Callbacks for resize preview handled by parent (TimelineTrack)
  final Function(int previewStartFrame, int previewEndFrame)? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  const TimelineClip({
    super.key,
    required this.clip,
    required this.trackId,
    this.isDragging = false, // Add back with default value
    this.onResizeUpdate,
    this.onResizeEnd,
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
  bool _awaitingMoveConfirmation =
      false; // Flag to keep visual position after move until VM updates

  // State for resizing preview
  String? _resizingDirection; // 'left', 'right', or null
  double _resizeAccumulatedDrag = 0.0; // Raw pixel delta during resize drag
  int? _previewStartFrame; // Store original start frame during resize
  int? _previewEndFrame; // Store original end frame during resize

  bool _isResizing = false; // Tracks active resize gesture

  // Service for resize logic
  final TimelineClipResizeService _resizeService = TimelineClipResizeService();

  // Controller for the context menu flyout
  final FlyoutController _contextMenuController = FlyoutController();

  // Define base colors for clip types
  static const Map<ClipType, Color> _clipTypeColors = {
    ClipType.video: Color(0xFF264F78),
    ClipType.audio: Color(0xFF498205),
    ClipType.image: Color(0xFF8764B8),
    ClipType.text: Color(0xFFC29008),
    ClipType.effect: Color(0xFFC50F1F),
  };

  // Helper to get appropriate contrast color
  Color _getContrastColor(Color backgroundColor) {
    final luminance =
        (0.299 * backgroundColor.r +
            0.587 * backgroundColor.g +
            0.114 * backgroundColor.b) /
        255;
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
  void didUpdateWidget(TimelineClip oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool needsUiUpdate = false;

    // Scenario 1: Critical change during active interaction (e.g., clip replaced underfoot)
    // This is a hard reset of interaction state.
    if ((_isMoving || _isResizing) &&
        (widget.clip.databaseId != oldWidget.clip.databaseId ||
            widget.clip.trackId != oldWidget.clip.trackId)) {
      // Post-frame callback to avoid setState during build/layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isMoving = false;
            _isResizing = false;
            _resizingDirection = null;
            _awaitingMoveConfirmation = false;
            _currentMoveFrame =
                widget.clip.startFrame; // Sync with new clip's actual start
          });
        }
      });
      return; // State has been reset, further checks are not needed for this update cycle.
    }

    // Scenario 2: Handling the aftermath of a move operation (_awaitingMoveConfirmation is true)
    if (_awaitingMoveConfirmation) {
      // Case 2a: The ViewModel has updated the clip to the expected new position.
      if (widget.clip.startFrame == _currentMoveFrame) {
        _awaitingMoveConfirmation = false;
        needsUiUpdate =
            true; // UI needs to reflect that we're no longer "awaiting."
      }
      // Case 2b: The ViewModel updated the clip, but to a *different* position
      // (e.g., an undo occurred, or another external change superseded the move).
      else {
        // widget.clip.startFrame != _currentMoveFrame
        _awaitingMoveConfirmation =
            false; // The awaited move is no longer relevant/valid.
        _currentMoveFrame =
            widget
                .clip
                .startFrame; // Crucial: Sync internal state to actual model state.
        needsUiUpdate =
            true; // UI needs to reflect the new _currentMoveFrame and no longer awaiting.
      }
    }
    // Scenario 3: No active interaction or pending confirmation.
    // Synchronize _currentMoveFrame if widget.clip.startFrame has changed externally.
    // This covers general external updates, including undo when not in the middle of a move sequence.
    else if (!_isMoving && !_isResizing) {
      // Ensure not actively moving/resizing
      if (_currentMoveFrame != widget.clip.startFrame) {
        _currentMoveFrame = widget.clip.startFrame;
        needsUiUpdate = true; // UI needs to reflect the new _currentMoveFrame.
      }
    }

    // If any state change occurred that requires a UI update, schedule a setState.
    if (needsUiUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final editorVm = di<EditorViewModel>();
    final timelineVm = di<TimelineViewModel>();
    final timelineNavVm =
        di<TimelineNavigationViewModel>(); // Inject Navigation VM

    final selectedClipId = watchValue(
      (TimelineViewModel vm) => vm.selectedClipIdNotifier,
    ); // Selection still from TimelineVM
    final zoom = watchValue(
      (TimelineNavigationViewModel vm) => vm.zoomNotifier,
    ); // Zoom from Navigation VM
    final isSelected = selectedClipId == widget.clip.databaseId;

    // --- Calculate Visuals based on state (Move or Resize Preview) ---
    double dragOffset = 0.0;
    double previewWidthDelta = 0.0;
    int currentDisplayStartFrame = widget.clip.startFrame;
    int currentDisplayEndFrame = widget.clip.endFrame;
    final double pixelsPerFrame =
        (zoom > 0 ? 5.0 * zoom : 5.0); // Base pixels * zoom, safe default

    // Calculate visual offset: Use _currentMoveFrame if moving OR awaiting confirmation
    if (_isMoving || _awaitingMoveConfirmation) {
      // Base offset calculation on the difference between the visually dragged frame
      // and the *current* frame data from the ViewModel.
      // This prevents large jumps if the ViewModel updates mid-drag (less likely but possible).
      dragOffset =
          (_currentMoveFrame - widget.clip.startFrame) * pixelsPerFrame;
    }

    // Calculate resize preview delta (only if resizing, not moving or awaiting move confirmation)
    if (_isResizing &&
        !_isMoving &&
        !_awaitingMoveConfirmation &&
        _resizingDirection != null &&
        _previewStartFrame != null &&
        _previewEndFrame != null) {
      // --- Calculate Resize Preview Clamped by Source Duration ---

      int rawFrameDelta =
          (pixelsPerFrame > 0 ? (_resizeAccumulatedDrag / pixelsPerFrame) : 0)
              .round();
      int trackDeltaMs = ClipModel.framesToMs(rawFrameDelta);
      int minTrackFrameDuration = 1;
      int minSourceMsDuration = 1; // Minimum allowed source duration in ms

      // Original source times
      final originalSourceStartMs = widget.clip.startTimeInSourceMs;
      final originalSourceEndMs = widget.clip.endTimeInSourceMs;
      final sourceDurationMs = widget.clip.sourceDurationMs;

      int
      allowedTrackFrameDelta; // The frame delta allowed after considering source limits

      if (_resizingDirection == 'left') {
        // Calculate target source start based on track drag
        int targetSourceStartMs = originalSourceStartMs + trackDeltaMs;
        // Clamp target source start: [0, originalSourceEnd - minDuration]
        int clampedSourceStartMs = targetSourceStartMs.clamp(
          0,
          originalSourceEndMs - minSourceMsDuration,
        );
        // Calculate the allowed source delta
        int allowedSourceDeltaMs = clampedSourceStartMs - originalSourceStartMs;
        // Convert allowed source delta back to allowed track delta
        allowedTrackFrameDelta = ClipModel.msToFrames(allowedSourceDeltaMs);

        // Calculate final track preview boundary using the allowed delta
        int previewBoundary = (_previewStartFrame! + allowedTrackFrameDelta)
        // Also clamp by opposite track edge and 0
        .clamp(0, _previewEndFrame! - minTrackFrameDuration);

        // Use the difference from the original frame for visual width/offset
        int actualFrameDelta = previewBoundary - _previewStartFrame!;
        previewWidthDelta = actualFrameDelta * pixelsPerFrame;
        dragOffset = 0; // Keep dragOffset at 0 for left resize preview
        currentDisplayStartFrame = previewBoundary;
        currentDisplayEndFrame = _previewEndFrame!;
      } else {
        // direction == 'right'
        // Calculate target source end based on track drag
        int targetSourceEndMs = originalSourceEndMs + trackDeltaMs;
        // Clamp target source end: [originalSourceStart + minDuration, sourceDurationMs]
        int clampedSourceEndMs = targetSourceEndMs.clamp(
          originalSourceStartMs + minSourceMsDuration,
          sourceDurationMs,
        );
        // Calculate the allowed source delta
        int allowedSourceDeltaMs = clampedSourceEndMs - originalSourceEndMs;
        // Convert allowed source delta back to allowed track delta
        allowedTrackFrameDelta = ClipModel.msToFrames(allowedSourceDeltaMs);

        // Calculate final track preview boundary using the allowed delta
        int previewBoundary = (_previewEndFrame! + allowedTrackFrameDelta)
        // Also clamp by opposite track edge, using Navigation VM for total frames
        .clamp(
          _previewStartFrame! + minTrackFrameDuration,
          timelineNavVm.totalFramesNotifier.value,
        ); // Use Navigation VM

        // Use the difference from the original frame for visual width
        int actualFrameDelta = previewBoundary - _previewEndFrame!;
        previewWidthDelta = actualFrameDelta * pixelsPerFrame;
        dragOffset = 0;
        currentDisplayStartFrame = _previewStartFrame!;
        currentDisplayEndFrame = previewBoundary;
      }
    }

    // Calculate base width and apply preview delta, ensuring minimum width
    final double clipBaseWidth = (widget.clip.durationFrames * pixelsPerFrame);
    final double finalVisualWidth = (clipBaseWidth + previewWidthDelta).clamp(
      pixelsPerFrame,
      double.infinity,
    ); // Min width 1 frame visually

    // --- UI Constants ---
    final baseClipColor = _clipTypeColors[widget.clip.type] ?? Colors.grey;
    final clipColor = baseClipColor;
    final contrastColor = _getContrastColor(clipColor);
    final selectionBorderColor = theme.accentColor.normal;
    final durationInSec =
        widget.clip.durationOnTrackMs / 1000.0; // Use durationOnTrackMs
    final formattedDuration = durationInSec.toStringAsFixed(1);
    const double fixedClipHeight = 65.0;
    const double borderRadiusValue = 10.0;
    const double borderWidth = 2.5;
    const double shadowBlur = 12.0;

    return Transform.translate(
      offset: Offset(dragOffset, 0),
      child: SizedBox(
        // Control visual width for resize preview
        width: finalVisualWidth,
        child: FlyoutTarget(
          controller: _contextMenuController,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.start,
            trackpadScrollCausesScale: false,
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
            onTap: () {
              timelineVm.selectedClipId = widget.clip.databaseId;
              editorVm.selectedClipId = widget.clip.databaseId?.toString();
            },
            // --- Drag Handling for MOVEMENT ---
            onHorizontalDragStart: _handleMoveStart,
            onHorizontalDragUpdate: _handleMoveUpdate,
            onHorizontalDragEnd: _handleMoveEnd,
            // --- Context Menu ---
            onSecondaryTapUp: (details) {
              editorVm.selectedClipId = widget.clip.databaseId?.toString();
              _contextMenuController.showFlyout(
                barrierDismissible: true,
                dismissWithEsc: true,
                position: details.globalPosition,
                builder: (context) => ClipContextMenu(clip: widget.clip),
              );
            },
            // --- Clip Visual Container ---
            child: Container(
              // Using simple Container, AnimatedContainer might conflict with SizedBox width animation
              // height: fixedClipHeight, // Let parent dictate height
              padding: const EdgeInsets.all(borderWidth),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadiusValue),
                border: Border.all(
                  color:
                      isSelected && _resizingDirection == null
                          ? selectionBorderColor
                          : clipColor.withAlpha(70),
                  width:
                      isSelected && _resizingDirection == null
                          ? borderWidth
                          : 1.0,
                ),
                boxShadow: [
                  // Consistent shadow application
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: shadowBlur,
                    offset: const Offset(0, 3),
                  ),
                  if (isSelected &&
                      _resizingDirection ==
                          null) // Only show selection glow if not resizing
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
                    child: ClipContentRenderer(
                      clip: widget.clip,
                      clipColor: clipColor,
                      contrastColor: contrastColor,
                      theme: theme,
                    ),
                  ),
                  // Left resize handle
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 8,
                    child: ResizeClipHandle(
                      direction: 'left',
                      clip: widget.clip,
                      pixelsPerFrame: pixelsPerFrame,
                      onDragStart: () => _handleResizeStart('left'),
                      onDragUpdate: (delta) => _handleResizeUpdate(delta),
                      onDragEnd:
                          (finalDelta) => _handleResizeEnd('left', finalDelta),
                    ),
                  ),
                  // Right resize handle
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 8,
                    child: ResizeClipHandle(
                      direction: 'right',
                      clip: widget.clip,
                      pixelsPerFrame: pixelsPerFrame,
                      onDragStart: () => _handleResizeStart('right'),
                      onDragUpdate: (delta) => _handleResizeUpdate(delta),
                      onDragEnd:
                          (finalDelta) => _handleResizeEnd('right', finalDelta),
                    ),
                  ),
                  // Info overlay at bottom
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
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

  // Move handlers
  void _handleMoveStart(DragStartDetails details) {
    if (_resizingDirection != null) return;
    _moveDragStartX = details.localPosition.dx;
    _originalMoveStartFrame = widget.clip.startFrame;
    _currentMoveFrame = _originalMoveStartFrame;

    di<TimelineViewModel>().selectedClipId = widget.clip.databaseId;
    di<EditorViewModel>().selectedClipId = widget.clip.databaseId?.toString();
    if (_isMoving) {
      setState(() {
        _isMoving = false;
      });
    }
  }

  void _handleMoveUpdate(DragUpdateDetails details) {
    if (_resizingDirection != null) return;
    final zoom = di<TimelineNavigationViewModel>().zoomNotifier.value;
    final pixelsPerFrame = (zoom > 0 ? 5.0 * zoom : 5.0);

    final currentDragX = details.localPosition.dx;
    final dragDeltaInPixels = currentDragX - _moveDragStartX;
    final dragDeltaInFrames = (dragDeltaInPixels / pixelsPerFrame).round();

    if (!_isMoving && dragDeltaInFrames != 0) {
      setState(() {
        _isMoving = true;
      });
    }
    if (_isMoving) {
      if (pixelsPerFrame <= 0) return;
      final newStartFrame = _originalMoveStartFrame + dragDeltaInFrames;
      final clampedStartFrame = newStartFrame.clamp(0, 1000000000);

      if (_currentMoveFrame != clampedStartFrame) {
        setState(() {
          _currentMoveFrame = clampedStartFrame;
        });
      }
    }
  }

  void _handleMoveEnd(DragEndDetails details) {
    if (_resizingDirection != null) return;
    if (_isMoving && _originalMoveStartFrame != _currentMoveFrame) {
      if (widget.clip.databaseId != null) {
        final newStartTimeMs = ClipModel.framesToMs(_currentMoveFrame);
        final cmd = MoveClipCommand(
          clipId: widget.clip.databaseId!,
          newTrackId: widget.clip.trackId,
          newStartTimeOnTrackMs: newStartTimeMs,
          projectDatabaseService: di<ProjectDatabaseService>(),
          timelineLogicService: di<TimelineLogicService>(),
          timelineNavViewModel: di<TimelineNavigationViewModel>(),
          clipsNotifier: di<TimelineViewModel>().clipsNotifier,
        );
        di<TimelineViewModel>().runCommand(cmd);
        _awaitingMoveConfirmation = true;
      }
    }
    setState(() {
      _isMoving = false;
    });
  }

  // Resize handlers
  void _handleResizeStart(String direction) {
    if (_isMoving || _awaitingMoveConfirmation) return;
    final result = _resizeService.handleResizeStart(
      isMoving: _isMoving,
      direction: direction,
      startFrame: widget.clip.startFrame,
      endFrame: widget.clip.endFrame,
    );
    if (result.containsKey('resizingDirection')) {
      setState(() {
        _isResizing = true;
        _resizingDirection = result['resizingDirection'];
        _resizeAccumulatedDrag = result['resizeAccumulatedDrag'];
        _previewStartFrame = result['previewStartFrame'];
        _previewEndFrame = result['previewEndFrame'];
      });
    }
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

    if (widget.onResizeUpdate != null &&
        _previewStartFrame != null &&
        _previewEndFrame != null) {
      final zoom = di<TimelineNavigationViewModel>().zoomNotifier.value;
      final pixelsPerFrame = (zoom > 0 ? 5.0 * zoom : 5.0);
      int rawFrameDelta =
          (pixelsPerFrame > 0 ? (_resizeAccumulatedDrag / pixelsPerFrame) : 0)
              .round();
      int trackDeltaMs = ClipModel.framesToMs(rawFrameDelta);
      int minTrackFrameDuration = 1;
      int minSourceMsDuration = 1;
      final originalSourceStartMs = widget.clip.startTimeInSourceMs;
      final originalSourceEndMs = widget.clip.endTimeInSourceMs;
      final sourceDurationMs = widget.clip.sourceDurationMs;
      int previewStart = _previewStartFrame!;
      int previewEnd = _previewEndFrame!;

      if (_resizingDirection == 'left') {
        int targetSourceStartMs = originalSourceStartMs + trackDeltaMs;
        int clampedSourceStartMs = targetSourceStartMs.clamp(
          0,
          originalSourceEndMs - minSourceMsDuration,
        );
        int allowedSourceDeltaMs = clampedSourceStartMs - originalSourceStartMs;
        int allowedTrackFrameDelta = ClipModel.msToFrames(allowedSourceDeltaMs);
        previewStart = (_previewStartFrame! + allowedTrackFrameDelta).clamp(
          0,
          _previewEndFrame! - minTrackFrameDuration,
        );
      } else {
        int targetSourceEndMs = originalSourceEndMs + trackDeltaMs;
        int clampedSourceEndMs = targetSourceEndMs.clamp(
          originalSourceStartMs + minSourceMsDuration,
          sourceDurationMs,
        );
        int allowedSourceDeltaMs = clampedSourceEndMs - originalSourceEndMs;
        int allowedTrackFrameDelta = ClipModel.msToFrames(allowedSourceDeltaMs);
        previewEnd = (_previewEndFrame! + allowedTrackFrameDelta).clamp(
          _previewStartFrame! + minTrackFrameDuration,
          di<TimelineNavigationViewModel>().totalFramesNotifier.value,
        );
      }
      widget.onResizeUpdate!(previewStart, previewEnd);
    }
  }

  void _handleResizeEnd(String direction, double finalPixelDelta) async {
    widget.onResizeEnd?.call();

    // Retrieve services via di
    final projectDatabaseService = di<ProjectDatabaseService>();
    final timelineLogicService = di<TimelineLogicService>();
    final navigationViewModel = di<TimelineNavigationViewModel>();

    await _resizeService.handleResizeEnd(
      resizingDirection: _resizingDirection,
      previewStartFrame: _previewStartFrame,
      previewEndFrame: _previewEndFrame,
      direction: direction,
      finalPixelDelta: finalPixelDelta,
      clipsNotifier: di<TimelineViewModel>().clipsNotifier,
      clip: widget.clip,
      zoom: di<TimelineNavigationViewModel>().zoomNotifier.value,
      runCommand: (cmd) => di<TimelineViewModel>().runCommand(cmd),
      // Pass the required services
      projectDatabaseService: projectDatabaseService,
      timelineLogicService: timelineLogicService,
      navigationViewModel: navigationViewModel,
    );

    setState(() {
      _isResizing = false;
      _resizingDirection = null;
      _resizeAccumulatedDrag = 0.0;
      _previewStartFrame = null;
      _previewEndFrame = null;
    });
  }

  // Add a new method to handle the move commit using our new service:
  void _commitMoveWithService(BuildContext context) {
    if (!_awaitingMoveConfirmation) return;

    final clipUpdateService = di<ClipUpdateService>();
    final startTimeOnTrackMs = ClipModel.framesToMs(_currentMoveFrame);

    // Use the new service to create and execute the command
    clipUpdateService.moveClip(
      clip: widget.clip,
      newTrackId: widget.clip.trackId, // Same track for simple move
      newStartTimeOnTrackMs: startTimeOnTrackMs,
    );

    // Reset state
    setState(() {
      _isMoving = false;
      // _currentMoveFrame = null;
      _awaitingMoveConfirmation = false;
    });
  }

  // Then modify the existing _commitMove method to use our new service:
  void _commitMove(BuildContext context) {
    _commitMoveWithService(context);
    // Remove the old implementation or keep it as fallback
  }
}
