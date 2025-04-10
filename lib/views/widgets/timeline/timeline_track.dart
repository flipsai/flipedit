import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/widgets.dart' as fw; // Import with prefix

/// A track in the timeline which contains clips
class TimelineTrack extends StatelessWidget with WatchItMixin {
  final int trackIndex;
  final List<Clip> clips;

  const TimelineTrack({
    super.key,
    required this.trackIndex,
    required this.clips,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Use watch_it's data binding to observe the zoom property
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);

    return Container(
      height: 60, // Keep standard track height
      margin: const EdgeInsets.only(bottom: 4), // Spacing between tracks
      decoration: BoxDecoration(
        // Use theme color for track background
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        // Clip children to prevent overflow if needed (e.g., during drag)
        clipBehavior: fw.Clip.hardEdge, // Use prefixed Clip enum
        children: [
          // Draw the track background with frame indicators
          Positioned.fill(child: _TrackBackground(zoom: zoom)),

          // Draw clips on the track
          ...clips.map((clip) {
            // Calculate position and size based on frame data and zoom
            final leftPosition = clip.startFrame * zoom * 5.0;
            final clipWidth = clip.durationFrames * zoom * 5.0;

            // Optimization: Only build/render clips that are potentially visible
            // This would require knowing the scroll offset and viewport width
            // For now, render all clips. Consider virtualization for many clips.

            return Positioned(
              left: leftPosition,
              top: 0,
              height: 60,
              // Ensure minimum width for very short clips to be clickable
              width: clipWidth.clamp(4.0, double.infinity),
              child: TimelineClip(clip: clip, trackIndex: trackIndex),
            );
          }),
        ],
      ),
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

    if (tickDistance <= 0)
      return; // Avoid infinite loop if zoom is zero or negative

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
