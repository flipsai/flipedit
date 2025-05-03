import 'package:fluent_ui/fluent_ui.dart';
import 'dart:developer' as developer;
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Needed for isPlayheadDragging
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'dart:math' as math;

// Callback type definition
typedef EnsureVisibleCallback = void Function(int frame);

// Mixin to handle playhead logic including physics, snapping, and dragging
mixin TimelinePlayheadLogicMixin on State<Timeline> implements TickerProvider {
  // --- State and Controllers (Expected in the main State class) ---
  // Updated to public getters
  AnimationController get playheadPhysicsController;
  AnimationController get scrubSnapController;
  TimelineNavigationViewModel get timelineNavigationViewModel;
  TimelineViewModel get timelineViewModel; // For isPlayheadDragging
  ScrollController get scrollController;
  double get trackLabelWidth;
  double get viewportWidth;

  // --- Local State for Playhead Logic (Managed by Mixin) ---
  // Made public: Direct frame position controller - needs careful sync with VM
  int currentFramePosition = 0;
  late final ValueNotifier<int> visualFramePositionNotifier;
  // Track the mouse position for physics-based interactions
  Offset? _lastMousePosition;
  // Current horizontal velocity for momentum scrolling
  double _horizontalVelocity = 0.0;
  // Track mouse drag delta for momentum
  double _cumulativeDragDelta = 0.0;
  // Last update time for velocity calculations
  DateTime? _lastDragUpdateTime;
  // Current auto-scroll direction and speed (moved to interaction? No, tied to drag)
  // double _autoScrollSpeed = 0.0;
  // Callback for scrolling
  late EnsureVisibleCallback _ensurePlayheadVisibleCallback;

  // --- Initialization & Sync ---

  void initializePlayheadLogic({
    required EnsureVisibleCallback ensurePlayheadVisible,
  }) {
    _ensurePlayheadVisibleCallback = ensurePlayheadVisible;
    // Sync initial frame position
    currentFramePosition = timelineNavigationViewModel.currentFrame;
    visualFramePositionNotifier = ValueNotifier<int>(
      currentFramePosition,
    );

    // Add listeners (controllers are created in the main State's initState)
    playheadPhysicsController.addListener(handlePlayheadPhysics);
    scrubSnapController.addListener(handleScrubSnap);
    timelineNavigationViewModel.currentFrameNotifier.addListener(
      syncCurrentFrame,
    );
  }

  void disposePlayheadLogic() {
    // Remove listeners (controllers disposed in main State's dispose)
    timelineNavigationViewModel.currentFrameNotifier.removeListener(
      syncCurrentFrame,
    );
    // Note: AnimationController listeners are automatically removed on dispose
    visualFramePositionNotifier.dispose(); // Dispose the notifier
  }

  // Keep local frame in sync with view model when changed externally
  void syncCurrentFrame() {
    // Only update if the value actually changed and physics isn't running
    if (currentFramePosition != timelineNavigationViewModel.currentFrame &&
        !playheadPhysicsController.isAnimating) {
      // Update local state and potentially trigger snap animation
      currentFramePosition = timelineNavigationViewModel.currentFrame;
      visualFramePositionNotifier.value =
          currentFramePosition; // Sync notifier too
      // Consider if a snap animation is needed here or if direct update is fine
      // If snapping is desired:
      // scrubSnapController.forward(from: 0.0);
      if (mounted) {
        setState(() {}); // Update UI if needed
      }
    }
  }

  // --- Physics Handlers ---

  // Physics simulation for momentum scrolling of playhead
  void handlePlayheadPhysics() {
    if (!playheadPhysicsController.isAnimating || !mounted) return;

    final double t = playheadPhysicsController.value;
    final double decelerationFactor = math.cos(
      t * math.pi / 2,
    ); // Natural deceleration
    final double frameDelta = _horizontalVelocity * decelerationFactor * 0.2;

    if (frameDelta.abs() < 0.01) {
      playheadPhysicsController.stop();
      _horizontalVelocity = 0.0; // Reset velocity
      return;
    }

    final int newFrame = (currentFramePosition + frameDelta.round()).clamp(
      0,
      timelineNavigationViewModel.totalFrames > 0
          ? timelineNavigationViewModel.totalFrames - 1
          : 0,
    );

    if (newFrame != currentFramePosition) {
      currentFramePosition = newFrame;
      visualFramePositionNotifier.value = newFrame; // Update visual notifier
      timelineNavigationViewModel.currentFrame = newFrame;

      setState(() {}); // Update UI
    }
  }

  // Handle snapping animation
  void handleScrubSnap() {
    if (!scrubSnapController.isAnimating || !mounted) return;

    final double t = scrubSnapController.value;
    final double easedT = Curves.easeOutCubic.transform(t);
    final int targetFrame = timelineNavigationViewModel.currentFrame;
    final int startFrame = currentFramePosition;

    // Calculate frame between start and target frames
    final int interpolatedFrame =
        startFrame + ((targetFrame - startFrame) * easedT).round();

    // Only update visually during animation
    if (interpolatedFrame != currentFramePosition) {
      currentFramePosition = interpolatedFrame;
      visualFramePositionNotifier.value = interpolatedFrame;
      setState(
        () {},
      );
    }

    // When animation completes, ensure final state matches VM
    if (t >= 1.0) {
      currentFramePosition = targetFrame;
      visualFramePositionNotifier.value = targetFrame;
      setState(() {});
    }
  }

  // --- Drag Handlers ---

  void handlePlayheadDragStart(DragStartDetails details) {
    // Make sure playback is stopped when user starts dragging the playhead
    if (timelineNavigationViewModel.isPlaying) {
      timelineNavigationViewModel.stopPlayback();
    }
    
    timelineViewModel.isPlayheadDragging = true;
    playheadPhysicsController.stop();
    scrubSnapController.stop();
    _horizontalVelocity = 0.0;
    _cumulativeDragDelta = 0.0;
    _lastDragUpdateTime = DateTime.now();
    _lastMousePosition = details.globalPosition;
  }

  void handlePlayheadDragUpdate(DragUpdateDetails details) {
    if (!mounted) return;

    final RenderBox? timelineRenderBox =
        this.context.findRenderObject() as RenderBox?;
    // Also check if scrollController has clients, needed for scrollOffsetX
    final bool hasScrollClients = scrollController.hasClients;
    if (timelineRenderBox == null || !scrollController.hasClients) return;

    // Convert global pointer position to local coordinates relative to the Timeline widget
    final Offset timelineLocalPosition = timelineRenderBox.globalToLocal(
      details.globalPosition,
    );
    final double scrollOffsetX = scrollController.offset;
    final double zoom = timelineNavigationViewModel.zoom;
    const double framePixelWidth = 5.0;
    final double pxPerFrame = framePixelWidth * zoom;

    if (pxPerFrame <= 0) return; // Avoid division by zero

    // Calculate pointer position relative to the start of the frame content area (after labels, considering scroll)
    final double pointerRelX = (timelineLocalPosition.dx -
            trackLabelWidth +
            scrollOffsetX)
        .clamp(0.0, double.infinity);
    
    // Get the exact frame position without rounding first for more precise calculations
    final double exactFramePosition = pointerRelX / pxPerFrame;
    
    // Only then round to get the final frame number
    final int maxAllowedFrame =
        timelineNavigationViewModel.totalFrames > 0
            ? timelineNavigationViewModel.totalFrames - 1
            : 0;
    final int newFrame = exactFramePosition.round().clamp(
      0,
      maxAllowedFrame,
    );

    if (newFrame != currentFramePosition) {
      // For debugging potential frame synchronization issues
      if ((newFrame - currentFramePosition).abs() > 2) {
        developer.log(
          'Significant frame jump: $currentFramePosition → $newFrame '
          '(pointer: ${exactFramePosition.toStringAsFixed(2)})', 
          name: 'Timeline.playhead'
        );
      }
      
      currentFramePosition = newFrame;
      visualFramePositionNotifier.value = newFrame;
      timelineNavigationViewModel.currentFrame = newFrame;
      scrubSnapController.stop();
      _ensurePlayheadVisibleCallback(newFrame);
    }

    // --- Velocity Calculation ---
    final now = DateTime.now();
    if (_lastDragUpdateTime != null && _lastMousePosition != null) {
      final double deltaX = details.globalPosition.dx - _lastMousePosition!.dx;
      final Duration timeDiff = now.difference(_lastDragUpdateTime!);
      if (timeDiff.inMilliseconds > 5) {
        // Avoid calculating velocity too frequently
        _cumulativeDragDelta += deltaX;
        _horizontalVelocity =
            _cumulativeDragDelta / (timeDiff.inMilliseconds / 1000.0);
        // Apply some smoothing or decay to velocity? Maybe later.
        _cumulativeDragDelta = 0;
      }
      // Update last position and time for next calculation even if not used this frame
      _lastMousePosition = details.globalPosition;
      _lastDragUpdateTime = now;
    } else {
      // Initialize on first update after start
      _lastMousePosition = details.globalPosition;
      _lastDragUpdateTime = now;
    }
  }

  void handlePlayheadDragEnd(DragEndDetails details) {
    timelineViewModel.isPlayheadDragging = false;
    // Use calculated velocity for physics
    // Apply physics-based momentum if significant velocity
    final double effectiveVelocity =
        details.velocity.pixelsPerSecond.dx /
        (viewportWidth > 0 ? viewportWidth : 1.0);
    _horizontalVelocity =
        effectiveVelocity * 0.5; // Adjust sensitivity factor as needed

    if (_horizontalVelocity.abs() > 1.0 && mounted) {
      // Threshold adjusted
      playheadPhysicsController.forward(from: 0.0);
    }

    // Reset state
    _lastMousePosition = null;
    _lastDragUpdateTime = null;
    _cumulativeDragDelta = 0.0;
  }

  void handlePlayheadDragCancel() {
    if (!mounted) return;
    timelineViewModel.isPlayheadDragging = false;
    _horizontalVelocity = 0.0;
    _lastMousePosition = null;
    _lastDragUpdateTime = null;
    _cumulativeDragDelta = 0.0;
    // Reset position to VM state? Or leave as is?
    currentFramePosition = timelineNavigationViewModel.currentFrame;
    setState(() {});
    visualFramePositionNotifier.value =
        currentFramePosition; // Reset visual notifier too
  }
}
