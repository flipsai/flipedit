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
    const int framesPerMajorTick = 30;
    const int framesPerMinorTick = 5;
    const double majorTickHeight = 10.0;
    const double minorTickHeight = 5.0;
    const double textPadding = 6.0; // Padding to prevent text collision

    final double effectiveFrameWidth = framePixelWidth * zoom;
    if (effectiveFrameWidth <= 0) return;

    final double majorTickSpacing = framesPerMajorTick * effectiveFrameWidth;
    final int numMinorTicks =
        (size.width / (effectiveFrameWidth * framesPerMinorTick)).ceil();

    for (int i = 0; i <= numMinorTicks; i++) {
      final int frameNumber = i * framesPerMinorTick;
      final double x = frameNumber * effectiveFrameWidth;
      final bool isMajorTick = frameNumber % framesPerMajorTick == 0;

      final double tickHeight = isMajorTick ? majorTickHeight : minorTickHeight;
      final Paint paintToUse = isMajorTick ? majorTickPaint : minorTickPaint;

      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - tickHeight),
        paintToUse,
      );

      if (isMajorTick && textStyle != null) {
        textPainter.text = TextSpan(
          text: frameNumber.toString(),
          style: textStyle?.copyWith(color: textColor),
        );
        textPainter.layout();

        // Only draw text if there's enough space between major ticks
        if (majorTickSpacing > textPainter.width + textPadding) {
          // Center the text horizontally above the tick line
          final textX = x - textPainter.width / 2;
          // Ensure text doesn't draw off the left edge
          final clampedTextX = math.max(0.0, textX);
          textPainter.paint(
            canvas,
            Offset(clampedTextX, 2),
          ); // Position slightly below top edge
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
