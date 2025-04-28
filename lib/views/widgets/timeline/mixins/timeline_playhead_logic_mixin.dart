import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Needed for isPlayheadDragging
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'dart:math' as math;
import 'package:watch_it/watch_it.dart'; // For di

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

  // --- Initialization & Sync ---

  void initializePlayheadLogic() {
    // Sync initial frame position
    currentFramePosition = timelineNavigationViewModel.currentFrame;

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
  }

  // Keep local frame in sync with view model when changed externally
  void syncCurrentFrame() {
    // Only update if the value actually changed and physics isn't running
    if (currentFramePosition != timelineNavigationViewModel.currentFrame && 
        !playheadPhysicsController.isAnimating) {
      // Update local state and potentially trigger snap animation
       currentFramePosition = timelineNavigationViewModel.currentFrame;
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
    final double decelerationFactor = math.cos(t * math.pi / 2); // Natural deceleration
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
      // Update VM only when physics settles or during drag?
      // Updating here causes continuous VM updates during physics
      timelineNavigationViewModel.currentFrame = newFrame;
      // We need ensurePlayheadVisible from the Scroll mixin - how to call it?
      // Option 1: Assume it exists via 'this' (requires Scroll mixin applied)
      // Option 2: Pass a callback
      // Let's assume Option 1 for now:
      // ensurePlayheadVisible(newFrame); 

      setState(() {}); // Update UI
    }
  }

  // Handle snapping animation
  void handleScrubSnap() {
    if (!scrubSnapController.isAnimating || !mounted) return;

    final double t = scrubSnapController.value;
    final double easedT = Curves.easeOutCubic.transform(t);
    final int targetFrame = timelineNavigationViewModel.currentFrame; // Target is VM frame
    final int startFrame = currentFramePosition; // Start from current animated position

    // Calculate frame between start and target frames
    final int interpolatedFrame = startFrame +
        ((targetFrame - startFrame) * easedT).round();

    // Only update visually during animation
    if (interpolatedFrame != currentFramePosition) {
       currentFramePosition = interpolatedFrame;
       setState(() {}); // Update playhead visual position
    }

    // When animation completes, ensure final state matches VM
    if (t >= 1.0) {
      currentFramePosition = targetFrame;
      // No VM update needed here, as it should already be the target
       setState(() {});
    }
  }

  // --- Drag Handlers ---

  void handlePlayheadDragStart(DragStartDetails details) {
    timelineViewModel.isPlayheadDragging = true;
    playheadPhysicsController.stop(); // Stop any ongoing physics
    scrubSnapController.stop(); // Stop snapping
    _horizontalVelocity = 0.0;
    _cumulativeDragDelta = 0.0;
    _lastDragUpdateTime = DateTime.now();
    _lastMousePosition = details.globalPosition;
  }

  void handlePlayheadDragUpdate(DragUpdateDetails details, BuildContext context) {
    if (!mounted) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset origin = renderBox.localToGlobal(Offset.zero);
    final double localX = details.globalPosition.dx - origin.dx;
    final double scrollOffsetX = scrollController.hasClients ? scrollController.offset : 0.0;
    final double zoom = timelineNavigationViewModel.zoom;
    const double framePixelWidth = 5.0;
    final double pxPerFrame = framePixelWidth * zoom;

    if (pxPerFrame <= 0) return; // Avoid division by zero

    final double pointerRelX = (localX + scrollOffsetX - trackLabelWidth).clamp(0.0, double.infinity);
    final int maxAllowedFrame = timelineNavigationViewModel.totalFrames > 0
        ? timelineNavigationViewModel.totalFrames - 1
        : 0;
    final int newFrame = (pointerRelX / pxPerFrame).round().clamp(0, maxAllowedFrame);

    if (newFrame != currentFramePosition) {
        currentFramePosition = newFrame; // Update local position immediately
        timelineNavigationViewModel.currentFrame = newFrame; // Update VM
        // Snap controller might fight this? Ensure snap is stopped.
        scrubSnapController.stop();
         setState(() {}); // Update UI
    }

    // --- Velocity Calculation ---
    final now = DateTime.now();
    if (_lastDragUpdateTime != null && _lastMousePosition != null) {
      final double deltaX = details.globalPosition.dx - _lastMousePosition!.dx;
      final Duration timeDiff = now.difference(_lastDragUpdateTime!);
      if (timeDiff.inMilliseconds > 5) { // Avoid calculating velocity too frequently
         _cumulativeDragDelta += deltaX;
         _horizontalVelocity = _cumulativeDragDelta / (timeDiff.inMilliseconds / 1000.0);
         // Apply some smoothing or decay to velocity? Maybe later.
         _cumulativeDragDelta = 0; // Reset cumulative delta after calculation
      }
      // Update last position and time for next calculation even if not used this frame
        _lastMousePosition = details.globalPosition;
        _lastDragUpdateTime = now;
    } else {
      // Initialize on first update after start
      _lastMousePosition = details.globalPosition;
      _lastDragUpdateTime = now;
    }


    // --- Auto-Scroll (Needs access to ensurePlayheadVisible or similar) ---
    // Auto-scroll logic seems better placed in the scroll mixin triggered during drag
    // Let's remove the direct scroll manipulation from here
    // Consider adding a callback like 'onDragNearEdge(double direction)'
    // Or call ensurePlayheadVisible directly if available
    // ensurePlayheadVisible(newFrame); // Potentially call scroll logic here
    
    // Simplified auto-scroll check (can be refined in scroll mixin)
    const double edgeMargin = 60.0;
    final double distanceFromLeft = localX - trackLabelWidth;
    final double distanceFromRight = viewportWidth - localX;

    if (distanceFromLeft < edgeMargin) {
      // Need to trigger scroll left
      // Call ensurePlayheadVisible or a dedicated auto-scroll method
    } else if (distanceFromRight < edgeMargin) {
       // Need to trigger scroll right
      // Call ensurePlayheadVisible or a dedicated auto-scroll method
    }
  }

  void handlePlayheadDragEnd(DragEndDetails details) {
     timelineViewModel.isPlayheadDragging = false;
    // Use calculated velocity for physics
    // Apply physics-based momentum if significant velocity
     final double effectiveVelocity = details.velocity.pixelsPerSecond.dx / (viewportWidth > 0 ? viewportWidth : 1.0);
    _horizontalVelocity = effectiveVelocity * 0.5; // Adjust sensitivity factor as needed

    if (_horizontalVelocity.abs() > 1.0 && mounted) { // Threshold adjusted
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
  }
} 