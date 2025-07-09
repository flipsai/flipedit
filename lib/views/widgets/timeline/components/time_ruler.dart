import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// A ruler widget that displays frame numbers and tick marks for the timeline using CustomPaint
class TimeRuler extends StatelessWidget {
  final double zoom;
  final double availableWidth;
  final bool hasTracks;

  const TimeRuler({
    super.key,
    required this.zoom,
    required this.availableWidth,
    required this.hasTracks,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeRuler &&
        other.zoom == zoom &&
        other.availableWidth == availableWidth &&
        other.hasTracks == hasTracks;
  }

  @override
  int get hashCode => Object.hash(zoom, availableWidth, hasTracks);

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final isEmpty = !hasTracks;

    // Return the entire widget based on this simple check
    return Container(
      height: 25,
      width: availableWidth,
      color: theme.colorScheme.muted,
      child:
          isEmpty
              ? _buildEmptyState(theme) // Show empty state when no tracks
              : _buildRuler(theme), // Show ruler when tracks exist
    );
  }

  /// Build the empty state message
  Widget _buildEmptyState(ShadThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.colorScheme.border.withValues(alpha: 0.1),
            theme.colorScheme.border.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.clock,
              size: 14,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(width: 8),
            Text(
              'Empty timeline - drag media to begin',
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the ruler with time markings
  Widget _buildRuler(ShadThemeData theme) {
    return CustomPaint(
      painter: TimeRulerPainter(
        zoom: zoom,
        majorTickColor: theme.colorScheme.border,
        minorTickColor: theme.colorScheme.mutedForeground,
        textColor: theme.colorScheme.mutedForeground,
        textStyle: theme.textTheme.small.copyWith(fontSize: 10),
      ),
      size: Size(availableWidth, 25),
    );
  }
}

/// CustomPainter for drawing the time ruler ticks and labels
class TimeRulerPainter extends CustomPainter {
  final double zoom;
  final Color majorTickColor;
  final Color minorTickColor;
  final Color textColor;
  final TextStyle? textStyle;

  final Paint majorTickPaint;
  final Paint minorTickPaint;
  final TextPainter textPainter;

  TimeRulerPainter({
    required this.zoom,
    required this.majorTickColor,
    required this.minorTickColor,
    required this.textColor,
    required this.textStyle,
  }) : majorTickPaint =
           Paint()
             ..color = majorTickColor
             ..strokeWidth = 1.0,
       minorTickPaint =
           Paint()
             ..color = minorTickColor
             ..strokeWidth = 1.0,
       textPainter = TextPainter(
         textAlign: TextAlign.left,
         textDirection: TextDirection.ltr,
       );

  @override
  void paint(Canvas canvas, Size size) {
    const double framePixelWidth = 5.0;
    const int fps = 30; // Assumed frames per second
    const double majorTickHeight = 10.0;
    const double minorTickHeight = 5.0;
    const double textPadding = 6.0;
    const double secondsPerMajorTick = 1.0;
    const double secondsPerMinorTick = 0.2;

    final double pixelsPerFrame = framePixelWidth * zoom;
    if (pixelsPerFrame <= 0) return;

    final double pixelsPerSecond = pixelsPerFrame * fps;
    final double majorTickSpacing = secondsPerMajorTick * pixelsPerSecond;
    final double minorTickSpacing = secondsPerMinorTick * pixelsPerSecond;

    if (minorTickSpacing <= 0) return;

    final int numMinorTicks = (size.width / minorTickSpacing).ceil();
    final double canvasHeight = size.height;

    // Pre-calculate offsets to reduce object creation
    final List<Offset> minorTickOffsets = [];
    final List<Offset> majorTickOffsets = [];
    final List<double> majorTickXPositions = [];

    for (int i = 0; i <= numMinorTicks; i++) {
      final double second = i * secondsPerMinorTick;
      final double x = second * pixelsPerSecond;

      final bool isMajorTick = (second % secondsPerMajorTick).abs() < 1e-6;
      final double tickHeight = isMajorTick ? majorTickHeight : minorTickHeight;

      final Offset startOffset = Offset(x, canvasHeight);
      final Offset endOffset = Offset(x, canvasHeight - tickHeight);

      if (isMajorTick) {
        majorTickOffsets.add(startOffset);
        majorTickOffsets.add(endOffset);
        majorTickXPositions.add(x);
      } else {
        minorTickOffsets.add(startOffset);
        minorTickOffsets.add(endOffset);
      }
    }

    // Draw all minor ticks at once
    if (minorTickOffsets.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.lines, minorTickOffsets, minorTickPaint);
    }

    // Draw all major ticks at once
    if (majorTickOffsets.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.lines, majorTickOffsets, majorTickPaint);
    }

    // Draw text labels for major ticks
    if (textStyle != null && majorTickSpacing > textPadding) {
      for (int i = 0; i < majorTickXPositions.length; i++) {
        final double x = majorTickXPositions[i];
        final double second = (x / pixelsPerSecond);
        
        String label =
            (secondsPerMinorTick < 1 && second.truncateToDouble() != second)
                ? second.toStringAsFixed(1)
                : second.toStringAsFixed(0);

        textPainter.text = TextSpan(
          text: label,
          style: textStyle?.copyWith(color: textColor),
        );
        textPainter.layout();

        if (majorTickSpacing > textPainter.width + textPadding) {
          final textX = x - textPainter.width / 2;
          final clampedTextX = math.max(0.0, textX);
          textPainter.paint(canvas, Offset(clampedTextX, 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(TimeRulerPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.majorTickColor != majorTickColor ||
        oldDelegate.minorTickColor != minorTickColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.textStyle != textStyle;
  }
}
