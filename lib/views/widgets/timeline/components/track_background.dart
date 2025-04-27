import 'package:fluent_ui/fluent_ui.dart';
import '../painters/track_background_painter.dart'; // Import the painter

// Renamed from _TrackBackground
class TrackBackground extends StatelessWidget {
  final double zoom;

  const TrackBackground({super.key, required this.zoom}); // Added super.key

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final lineColor = theme.resources.controlStrokeColorDefault;
    final faintLineColor = theme.resources.subtleFillColorTertiary;
    final textColor = theme.typography.caption?.color ?? Colors.grey;

    return RepaintBoundary(
      child: CustomPaint(
        painter: TrackBackgroundPainter(
          zoom: zoom,
          lineColor: lineColor,
          faintLineColor: faintLineColor,
          textColor: textColor,
        ),
        child: Container(), // CustomPaint needs a child
      ),
    );
  }
}