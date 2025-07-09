import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A custom painter for drawing the timeline playhead marker (triangle + line).
class _PlayheadPainter extends CustomPainter {
  final Color color;
  double strokeWidth = 1.0;
  double triangleHeight = 10.0;
  double triangleWidth = 10.0;

  _PlayheadPainter({required this.color, this.triangleWidth = 10.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.fill;

    // --- Draw Triangle ---
    final path = Path();
    // Start at the top-center point
    path.moveTo(size.width / 2, 0);
    // Line to bottom-left of triangle base
    path.lineTo((size.width - triangleWidth) / 2, triangleHeight);
    // Line to bottom-right of triangle base
    path.lineTo((size.width + triangleWidth) / 2, triangleHeight);
    // Close the path back to the top point
    path.close();
    canvas.drawPath(path, paint);

    // --- Draw Line ---
    // Reset paint style for the line
    paint.style = PaintingStyle.stroke;
    // Draw vertical line from bottom of triangle to bottom of widget area
    canvas.drawLine(
      Offset(size.width / 2, triangleHeight),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // Repaint only if color changes (or other properties if they become dynamic)
    return oldDelegate is! _PlayheadPainter || oldDelegate.color != color;
  }
}

/// A widget representing the timeline playhead.
class TimelinePlayhead extends StatelessWidget {
  const TimelinePlayhead({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    const double playheadWidth = 10.0; // Width encompassing the triangle marker

    return SizedBox(
      // Use the width defined for the marker for proper positioning later
      width: playheadWidth,
      // Height should span the available vertical space (determined by Positioned)
      height: double.infinity,
      child: CustomPaint(
        painter: _PlayheadPainter(
          color: theme.colorScheme.accent, // Use a theme color
          triangleWidth: playheadWidth, // Match triangle width to SizedBox
        ),
      ),
    );
  }
}
