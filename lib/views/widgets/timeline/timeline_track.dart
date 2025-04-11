import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/widgets.dart' as fw; // Import with prefix
import 'dart:developer' as developer;

/// A track in the timeline which contains clips
class TimelineTrack extends StatefulWidget {
  final int trackIndex;
  final List<ClipModel> clips;

  const TimelineTrack({
    super.key,
    required this.trackIndex,
    required this.clips,
  });

  @override
  State<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends State<TimelineTrack> {
  // Track the last hover position for better preview
  final ValueNotifier<Offset?> hoverPositionNotifier = ValueNotifier<Offset?>(
    null,
  );
  final GlobalKey _trackKey = GlobalKey();
  late TimelineViewModel timelineViewModel;
  double zoom = 1.0;

  @override
  void initState() {
    super.initState();
    timelineViewModel = di<TimelineViewModel>();
    // Initial zoom value
    zoom = timelineViewModel.zoom;

    // Listen for zoom changes
    timelineViewModel.zoomNotifier.addListener(_onZoomChanged);
  }

  void _onZoomChanged() {
    setState(() {
      zoom = timelineViewModel.zoom;
    });
  }

  @override
  void dispose() {
    timelineViewModel.zoomNotifier.removeListener(_onZoomChanged);
    hoverPositionNotifier.dispose();
    super.dispose();
  }

  /// Get the scroll position from ancestors
  double getScrollPosition(BuildContext context) {
    // Try to find the SingleChildScrollView ancestor for horizontal position
    ScrollPosition? scrollPosition;
    try {
      // First try to find a horizontal scroll
      scrollPosition = Scrollable.of(context).position;
      if (scrollPosition.axis != Axis.horizontal) {
        scrollPosition = null;
      }
    } catch (e) {
      // Couldn't find scrollable, that's okay
      scrollPosition = null;
    }

    return scrollPosition?.pixels ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return DragTarget<ClipModel>(
      key: _trackKey,
      onAcceptWithDetails: (details) {
        // Get the dragged clip
        final draggedClip = details.data;

        // Check if draggedClip is not null before proceeding
        if (draggedClip == null) {
           developer.log('Error: Dragged data is null');
           return;
        }

        // Convert global position to local position with highest precision
        final RenderBox renderBox =
            _trackKey.currentContext!.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.offset);

        // Ensure the position is within the track bounds
        double posX = localPosition.dx;
        if (posX < 0) posX = 0;
        if (posX > renderBox.size.width) posX = renderBox.size.width;

        // Get scroll position of the timeline
        final scrollPosition = getScrollPosition(context);

        // Debug info
        developer.log(
          'Accepting drop at: local=$posX, scroll=$scrollPosition, zoom=$zoom',
        );

        // Calculate the frame position at the drop point
        // Formula: localX / (frameWidthInPixels)
        final exactFrame = posX / (5.0 * zoom);
        final targetFrame = exactFrame.floor();

        developer.log(
          'Placing clip at frame: $targetFrame (exact: $exactFrame)',
        );

        // Call the new ViewModel method to handle duration fetching
        timelineViewModel.addClipAtPosition(
          clipData: draggedClip,
          trackId: widget.trackIndex + 1,
          startTimeInSourceMs: draggedClip.startTimeInSourceMs,
          endTimeInSourceMs: draggedClip.endTimeInSourceMs,
          localPositionX: posX,
          scrollOffsetX: scrollPosition,
        );

        // Reset the hover position
        hoverPositionNotifier.value = null;
      },
      onWillAcceptWithDetails: (details) {
        // Only accept clip objects
        final RenderBox? renderBox =
            _trackKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          // Make sure to directly use the global position for most accurate conversion
          final localPosition = renderBox.globalToLocal(details.offset);

          // Completely reset any previous state
          hoverPositionNotifier.value = null;

          // Set the new position after a brief delay to ensure clean state
          Future.microtask(() {
            if (mounted) {
              hoverPositionNotifier.value = localPosition;
            }
          });
        }

        return true;
      },
      onMove: (details) {
        // Convert global position to local position for preview
        final RenderBox? renderBox =
            _trackKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          // Always calculate position directly from global coordinates for consistency
          final localPosition = renderBox.globalToLocal(details.offset);

          // Ensure the position is within the track bounds
          if (localPosition.dx >= 0 &&
              localPosition.dx <= renderBox.size.width) {
            hoverPositionNotifier.value = localPosition;
          }
        }
      },
      onLeave: (_) {
        // Completely reset state when leaving the track
        hoverPositionNotifier.value = null;
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: 60, // Keep standard track height
          margin: const EdgeInsets.only(bottom: 4), // Spacing between tracks
          decoration: BoxDecoration(
            // Highlight the track when a clip is being dragged over it
            color:
                candidateData.isNotEmpty
                    ? theme.accentColor.lightest.withOpacity(0.3)
                    : theme.resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            // Clip children to prevent overflow if needed (e.g., during drag)
            clipBehavior: fw.Clip.hardEdge, // Use prefixed Clip enum
            children: [
              // Draw the track background with frame indicators
              Positioned.fill(child: _TrackBackground(zoom: zoom)),

              // Draw clips on the track
              ...widget.clips.map((clip) {
                // Calculate position and size based on frame data and zoom
                final leftPosition = clip.startFrame * zoom * 5.0;
                final clipWidth = clip.durationFrames * zoom * 5.0;

                return Positioned(
                  left: leftPosition,
                  top: 0,
                  height: 60,
                  // Ensure minimum width for very short clips to be clickable
                  width: clipWidth.clamp(4.0, double.infinity),
                  child: TimelineClip(
                    clip: clip,
                    trackIndex: widget.trackIndex,
                  ),
                );
              }),

              // Preview drag position using hover position value notifier
              ValueListenableBuilder<Offset?>(
                valueListenable: hoverPositionNotifier,
                builder: (context, hoverPosition, _) {
                  if (hoverPosition == null || candidateData.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final draggedClip = candidateData.first;
                  if (draggedClip == null) return const SizedBox.shrink();

                  // For preview, use the cursor X position directly
                  final previewRawX = hoverPosition.dx;

                  // Calculate frame for accurate positioning
                  final frameAtCursor = (previewRawX / (5.0 * zoom)).floor();

                  // Position the preview exactly at the frame boundary for consistent visual feedback
                  // This is important so that preview and final position match exactly
                  final previewLeftPosition = frameAtCursor * zoom * 5.0;
                  final previewWidth = draggedClip.durationFrames * zoom * 5.0;

                  return Stack(
                    children: [
                      // Vertical line indicator at the drop frame
                      Positioned(
                        left: previewLeftPosition,
                        top: 0,
                        bottom: 0,
                        width: 1,
                        child: Container(color: theme.accentColor.lighter),
                      ),
                      // The clip preview
                      Positioned(
                        left: previewLeftPosition,
                        top: 0,
                        height: 60,
                        width: previewWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.accentColor.normal.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: theme.accentColor.normal,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              draggedClip.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),

                      // Debug overlay with cursor position info
                      Positioned(
                        left: previewLeftPosition + previewWidth + 5,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          color: Colors.black.withOpacity(0.7),
                          child: Text(
                            'Frame: $frameAtCursor',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackBackground extends StatelessWidget {
  final double zoom;

  const _TrackBackground({required this.zoom});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return CustomPaint(
      // Pass theme color to painter
      painter: _TrackBackgroundPainter(
        zoom: zoom,
        color: theme.resources.controlStrokeColorDefault,
      ),
    );
  }
}

class _TrackBackgroundPainter extends CustomPainter {
  final double zoom;
  final Color color; // Color for the grid lines

  const _TrackBackgroundPainter({required this.zoom, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color =
              color // Use the passed color
          ..strokeWidth = 0.5; // Make lines thinner

    const double frameWidth = 5.0;
    const int framesPerTick = 30; // Draw line every 30 frames (e.g., 1 second)
    final tickDistance = framesPerTick * zoom * frameWidth;

    if (tickDistance <= 0) {
      return; // Avoid infinite loop if zoom is zero or negative
    }

    // Draw vertical frame markers
    for (double x = 0; x < size.width; x += tickDistance) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackBackgroundPainter oldDelegate) {
    // Repaint if zoom or color changes
    return oldDelegate.zoom != zoom || oldDelegate.color != color;
  }
}
