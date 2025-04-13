import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/widgets.dart' as fw;
import 'dart:developer' as developer;

class TimelineTrack extends StatefulWidget with WatchItStatefulWidgetMixin {
  final int trackId;
  final List<ClipModel> clips;

  const TimelineTrack({
    super.key,
    required this.trackId,
    required this.clips,
  });

  @override
  State<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends State<TimelineTrack> {
  final hoverPositionNotifier = ValueNotifier<Offset?>(null);
  final GlobalKey trackKey = GlobalKey(); // Key for DragTarget
  late TimelineViewModel timelineViewModel;

  @override
  void initState() {
    super.initState();
    timelineViewModel = di<TimelineViewModel>();
  }

  @override
  void dispose() {
    hoverPositionNotifier.dispose(); // Dispose the notifier here
    super.dispose();
  }

  /// Get the scroll position from ancestors
  double getScrollPosition(BuildContext context) {
    ScrollPosition? scrollPosition;
    try {
      scrollPosition = Scrollable.of(context).position;
      if (scrollPosition.axis != Axis.horizontal) {
        scrollPosition = null;
      }
    } catch (e) {
      scrollPosition = null;
    }
    return scrollPosition?.pixels ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Call watchValue here in the State's build method
    final double zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);

    return DragTarget<ClipModel>(
      key: trackKey,
      onAcceptWithDetails: (details) {
        final draggedClip = details.data;

        final RenderBox? renderBox = trackKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null) return;

        final localPosition = renderBox.globalToLocal(details.offset);
        double posX = localPosition.dx.clamp(0.0, renderBox.size.width);
        final scrollPosition = getScrollPosition(context);

        developer.log('Accepting drop at: local=$posX, scroll=$scrollPosition, zoom=$zoom');

        timelineViewModel.addClipAtPosition(
          clipData: draggedClip,
          trackId: widget.trackId,
          startTimeInSourceMs: draggedClip.startTimeInSourceMs,
          endTimeInSourceMs: draggedClip.endTimeInSourceMs,
          localPositionX: posX,
          scrollOffsetX: scrollPosition,
        );

        hoverPositionNotifier.value = null; // Reset hover
      },
      onWillAcceptWithDetails: (details) {
        final RenderBox? renderBox = trackKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final localPosition = renderBox.globalToLocal(details.offset);
          hoverPositionNotifier.value = localPosition;
        }
        return true; // Accept the drag
      },
      onMove: (details) {
        final RenderBox? renderBox = trackKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final localPosition = renderBox.globalToLocal(details.offset);
          if (localPosition.dx >= 0 && localPosition.dx <= renderBox.size.width) {
            hoverPositionNotifier.value = localPosition;
          } else {
             // Optionally clear if moved outside bounds during move
             // hoverPositionNotifier.value = null; 
          }
        }
      },
      onLeave: (_) {
        hoverPositionNotifier.value = null; // Clear hover on leave
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: 60,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty
                ? theme.accentColor.lightest.withOpacity(0.3)
                : theme.resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            clipBehavior: fw.Clip.hardEdge,
            children: [
              Positioned.fill(child: _TrackBackground(zoom: zoom)),
              ...widget.clips.map((clip) { // Use widget.clips
                final leftPosition = clip.startFrame * zoom * 5.0;
                final clipWidth = clip.durationFrames * zoom * 5.0;
                return Positioned(
                  left: leftPosition,
                  top: 0,
                  height: 60,
                  width: clipWidth.clamp(4.0, double.infinity),
                  child: TimelineClip(
                    clip: clip,
                    trackId: widget.trackId,
                  ),
                );
              }),
              _DragPreview(
                hoverPositionNotifier: hoverPositionNotifier,
                candidateData: candidateData,
                zoom: zoom,
              ),
            ],
          ),
        );
      },
    );
  }
}

// _DragPreview remains StatelessWidget using WatchItMixin
class _DragPreview extends StatelessWidget with WatchItMixin {
  final ValueNotifier<Offset?> hoverPositionNotifier;
  final List<ClipModel?> candidateData;
  final double zoom;

  const _DragPreview({ 
    required this.hoverPositionNotifier,
    required this.candidateData,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Watch the notifier to trigger rebuilds when its value changes
    watch(hoverPositionNotifier);
    // Get the actual value *after* watching
    final Offset? hoverPositionValue = hoverPositionNotifier.value;

    if (hoverPositionValue == null || candidateData.isEmpty) {
      return const SizedBox.shrink();
    }

    final draggedClip = candidateData.first;
    if (draggedClip == null) return const SizedBox.shrink();

    // Access .dx on the Offset value
    final previewRawX = hoverPositionValue.dx; 
    final frameAtCursor = (previewRawX / (5.0 * zoom)).floor();
    final nonNegativeFrame = frameAtCursor < 0 ? 0 : frameAtCursor;
    final previewLeftPosition = nonNegativeFrame * zoom * 5.0;
    final previewWidth = draggedClip.durationFrames * zoom * 5.0;

    return Stack(
      clipBehavior: fw.Clip.none, // Allow indicator text to overflow slightly
      children: [
        // Vertical line indicator
        Positioned(
          left: previewLeftPosition,
          top: 0,
          bottom: 0,
          width: 1,
          child: Container(color: theme.accentColor.lighter),
        ),
        // Clip preview rectangle
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
        // Frame indicator text
        Positioned(
          // Position slightly offset from the preview rectangle
          left: previewLeftPosition + previewWidth + 5,
          top: 5, 
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'Frame: $nonNegativeFrame', 
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// _TrackBackground and _TrackBackgroundPainter remain the same
class _TrackBackground extends StatelessWidget {
  final double zoom;

  const _TrackBackground({required this.zoom});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return CustomPaint(
      painter: _TrackBackgroundPainter(
        zoom: zoom,
        color: theme.resources.controlStrokeColorDefault,
      ),
    );
  }
}

class _TrackBackgroundPainter extends CustomPainter {
  final double zoom;
  final Color color;

  const _TrackBackgroundPainter({required this.zoom, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color =
              color
          ..strokeWidth = 0.5;

    const double frameWidth = 5.0;
    const int framesPerTick = 30;
    final tickDistance = framesPerTick * zoom * frameWidth;

    if (tickDistance <= 0) {
      return;
    }

    for (double x = 0; x < size.width; x += tickDistance) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackBackgroundPainter oldDelegate) {
    return oldDelegate.zoom != zoom || oldDelegate.color != color;
  }
}
