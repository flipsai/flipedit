import 'package:flutter/material.dart';
import '../painters/track_background_painter.dart'; // Import the painter

// Renamed from _TrackBackground
class TrackBackground extends StatelessWidget {
  final double zoom;

  const TrackBackground({super.key, required this.zoom}); // Added super.key

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.dividerColor;
    final faintLineColor = theme.disabledColor.withAlpha(50);
    final textColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

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
