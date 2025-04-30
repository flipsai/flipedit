import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart'; // Import Timeline to access State
import 'dart:math' as math;

// Mixin to handle scroll-related logic for the Timeline widget
mixin TimelineScrollLogicMixin on State<Timeline> {
  // These variables are expected to be defined in the State class using this mixin
  // Updated to public getters
  ScrollController get scrollController;
  double get viewportWidth;
  double get trackLabelWidth;
  TimelineNavigationViewModel get timelineNavigationViewModel;

  // --- Scroll Handling ---

  void handleScrollRequest(int frame) {
    // Use 'mounted' directly as we are 'on State<Timeline>'
    if (!mounted || viewportWidth <= 0 || !scrollController.hasClients) {
      logWarning(
        'TimelineScrollLogicMixin',
        'Scroll requested for frame $frame but widget/controller not ready.',
      );
      return;
    }

    const double framePixelWidth = 5.0; // Assuming constant, could be passed if dynamic
    final double scrollableViewportWidth = viewportWidth - trackLabelWidth;
    if (scrollableViewportWidth <= 0) return;

    // Calculate target offset using view model method (dependency assumed)
    // We need TimelineViewModel here, let's assume it's accessible via 'widget' or another getter
    // final unclampedTargetOffset = di<TimelineViewModel>().calculateScrollOffsetForFrame(
    //   frame,
    //   timelineNavigationViewModel.zoom,
    // );
    // Temporarily calculate directly if VM method isn't easily available here
    final double zoom = timelineNavigationViewModel.zoom;
    final double unclampedTargetOffset = frame * zoom * framePixelWidth;


    final double maxOffset = scrollController.position.maxScrollExtent;
    final double targetOffset = unclampedTargetOffset.clamp(0.0, maxOffset);

    logInfo(
      'TimelineScrollLogicMixin',
      'Executing scroll to frame $frame (target: $targetOffset)',
    );
    scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }

  void ensurePlayheadVisible(int frame) {
    if (!scrollController.hasClients || viewportWidth <= 0) return;

    const double framePxWidth = 5.0; // Assuming constant
    final double zoom = timelineNavigationViewModel.zoom;
    final double playheadPosition = frame * zoom * framePxWidth;

    // Calculate visible range
    final double scrollOffset = scrollController.offset;
    final double visibleStart = scrollOffset; // Adjusted: Offset is the start
    final double visibleEnd = scrollOffset + viewportWidth - trackLabelWidth; // Adjusted: Viewport relative to scrollable area


    // Calculate absolute playhead position within the scrollable content (excluding label)
    final double absolutePlayheadPosition = playheadPosition;

    // Check if playhead is out of view relative to the scrollable area
    const double scrollMargin = 60.0; // Margin before triggering scroll
    final double playheadLeftEdgeInView = absolutePlayheadPosition - scrollOffset;
    final double playheadRightEdgeInView = absolutePlayheadPosition - scrollOffset;


    if (playheadLeftEdgeInView < scrollMargin) {
       // Playhead near left edge, scroll left
      final double targetOffset = math.max(
        0.0,
        absolutePlayheadPosition - scrollMargin * 1.5, // Scroll a bit past the margin
      );
      if ((targetOffset - scrollOffset).abs() > 5.0) { // Avoid tiny adjustments
        scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (playheadRightEdgeInView > (viewportWidth - trackLabelWidth - scrollMargin)) {
      // Playhead near right edge, scroll right
       final double targetOffset = (absolutePlayheadPosition - (viewportWidth - trackLabelWidth) + scrollMargin * 1.5)
          .clamp(0.0, scrollController.position.maxScrollExtent);

       if ((targetOffset - scrollOffset).abs() > 5.0) { // Avoid tiny adjustments
         scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
       }
    }
  }
} 