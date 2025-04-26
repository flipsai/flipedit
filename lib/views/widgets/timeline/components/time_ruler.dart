import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;

/// A ruler widget that displays frame numbers and tick marks for the timeline using CustomPaint
class TimeRuler extends StatelessWidget with WatchItMixin {
  final double zoom;
  final double availableWidth;

  const TimeRuler({
    super.key,
    required this.zoom,
    required this.availableWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      height: 25,
      width: availableWidth, // Painter draws within this width
      color: theme.resources.subtleFillColorSecondary,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TimeRulerPainter(
            zoom: zoom,
            majorTickColor: theme.resources.controlStrokeColorDefault,
            minorTickColor:
                theme
                    .resources
                    .textFillColorSecondary, // Color for the small ticks
            textColor: theme.resources.textFillColorSecondary,
            textStyle: theme.typography.caption?.copyWith(fontSize: 10),
          ),
          size: Size(availableWidth, 25),
        ),
      ),
    );
  }
}

/// CustomPainter for drawing the TimeRuler ticks and labels
class _TimeRulerPainter extends CustomPainter {
  final double zoom;
  final Color majorTickColor;
  final Color minorTickColor;
  final Color textColor;
  final TextStyle? textStyle;

  final Paint majorTickPaint;
  final Paint minorTickPaint;
  final TextPainter textPainter;

  _TimeRulerPainter({
    required this.zoom,
    required this.majorTickColor,
    required this.minorTickColor,
    required this.textColor,
    required this.textStyle,
  }) : majorTickPaint = Paint(),
       minorTickPaint = Paint(),
       textPainter = TextPainter(
         textAlign: TextAlign.left,
         textDirection: TextDirection.ltr,
       ) {
    majorTickPaint.color = majorTickColor;
    majorTickPaint.strokeWidth = 1.0;
    minorTickPaint.color = minorTickColor;
    minorTickPaint.strokeWidth = 1.0; // Both lines are 1px wide
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double framePixelWidth = 5.0;
    const int fps = 30; // Assumed frames per second; adjust as needed or pass as parameter
    const double majorTickHeight = 10.0;
    const double minorTickHeight = 5.0;
    const double textPadding = 6.0; // Padding to prevent text collision
    const double secondsPerMajorTick = 1.0; // Show label at each integer second
    const double secondsPerMinorTick = 0.2; // A minor tick every 0.2 sec = every 6 frames (for FPS=30)

    final double pixelsPerFrame = framePixelWidth * zoom;
    if (pixelsPerFrame <= 0) return;

    final double pixelsPerSecond = pixelsPerFrame * fps;
    final double majorTickSpacing = secondsPerMajorTick * pixelsPerSecond;
    final double minorTickSpacing = secondsPerMinorTick * pixelsPerSecond;
    final int numMinorTicks = (size.width / minorTickSpacing).ceil();

    for (int i = 0; i <= numMinorTicks; i++) {
      // Calculate the 'second' value and corresponding x-position
      final double second = i * secondsPerMinorTick;
      final double x = second * pixelsPerSecond;

      final bool isMajorTick = (second % secondsPerMajorTick).abs() < 1e-6;

      final double tickHeight = isMajorTick ? majorTickHeight : minorTickHeight;
      final Paint paintToUse = isMajorTick ? majorTickPaint : minorTickPaint;

      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - tickHeight),
        paintToUse,
      );

      if (isMajorTick && textStyle != null) {
        // Show to 1 decimal only if ticks are <1px apart, else integer
        String label = (secondsPerMinorTick < 1)
            ? second.toStringAsFixed(second.truncateToDouble() == second ? 0 : 1)
            : second.toStringAsFixed(0);

        textPainter.text = TextSpan(
          text: label,
          style: textStyle?.copyWith(color: textColor),
        );
        textPainter.layout();

        if (majorTickSpacing > textPainter.width + textPadding) {
          final textX = x - textPainter.width / 2;
          final clampedTextX = math.max(0.0, textX);
          textPainter.paint(
            canvas,
            Offset(clampedTextX, 2),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.majorTickColor != majorTickColor ||
        oldDelegate.minorTickColor != minorTickColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.textStyle != textStyle;
  }
}
