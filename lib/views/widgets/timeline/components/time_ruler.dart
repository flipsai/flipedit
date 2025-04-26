import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;
import '../../../../viewmodels/timeline_viewmodel.dart';
import '../../../../di/service_locator.dart'; // Ensure DI is imported

/// A ruler widget that displays frame numbers and tick marks for the timeline using CustomPaint
class TimeRuler extends StatelessWidget with WatchItMixin { // Added WatchItMixin back
  final double zoom;
  final double availableWidth;

  const TimeRuler({
    super.key,
    required this.zoom,
    required this.availableWidth,
  });

  @override
  Widget build(BuildContext context) {
    // Access ViewModel via DI and watch the entire ViewModel using WatchItMixin
    final vm = watch(di<TimelineViewModel>()); // Explicitly watch the instance from DI
    final isEmpty = vm.clips.isEmpty; // Access clips directly on the watched instance
    final theme = FluentTheme.of(context);

    // Return the main container structure
    return Container(
      height: 25,
      width: availableWidth,
      // Use subtleFillColorSecondary for the base background
      color: theme.resources.subtleFillColorSecondary,
      child: Stack( // Stack allows overlaying the empty state message
        children: [
          // The painter draws the ruler ticks and labels
          RepaintBoundary( // Optimize repainting
            child: CustomPaint(
              painter: _TimeRulerPainter(
                zoom: zoom,
                majorTickColor: theme.resources.controlStrokeColorDefault,
                minorTickColor: theme.resources.textFillColorSecondary,
                textColor: theme.resources.textFillColorSecondary,
                textStyle: theme.typography.caption?.copyWith(fontSize: 10),
                isEmpty: isEmpty, // Pass the empty state flag
              ),
              // Ensure the painter covers the available size
              size: Size(availableWidth, 25),
            ),
          ),
          // Conditionally display the empty state message overlay
          if (isEmpty)
            Positioned.fill(
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.clock, size: 14, color: theme.resources.textFillColorDisabled),
                    SizedBox(width: 8),
                    Text('Empty timeline - drag media to begin',
                        style: theme.typography.caption?.copyWith(
                          color: theme.resources.textFillColorDisabled,
                          fontSize: 12
                        )),
                  ],
                ),
              ),
            ),
        ],
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
  final bool isEmpty; // Added flag for empty state

  // Paints for drawing ticks
  final Paint majorTickPaint;
  final Paint minorTickPaint;
  // TextPainter for drawing labels
  final TextPainter textPainter;

  // Constructor initializes paints and requires the isEmpty flag
  _TimeRulerPainter({
    required this.zoom,
    required this.majorTickColor,
    required this.minorTickColor,
    required this.textColor,
    required this.textStyle,
    required this.isEmpty, // Require isEmpty
  }) : majorTickPaint = Paint()..color = majorTickColor..strokeWidth = 1.0,
       minorTickPaint = Paint()..color = minorTickColor..strokeWidth = 1.0,
       textPainter = TextPainter(
         textAlign: TextAlign.left,
         textDirection: TextDirection.ltr,
       ); // Removed extra semicolon causing errors

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background gradient only if the timeline is empty
    if (isEmpty) {
      final gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          majorTickColor.withOpacity(0.1), // Use theme colors for gradient
          majorTickColor.withOpacity(0.05),
        ],
      );
      // Draw the gradient rectangle covering the painter's area
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
      // Don't draw ticks or labels if empty
      return;
    }

    // --- Existing tick and label drawing logic ---
    const double framePixelWidth = 5.0;
    const int fps = 30; // Assumed frames per second
    const double majorTickHeight = 10.0;
    const double minorTickHeight = 5.0;
    const double textPadding = 6.0;
    const double secondsPerMajorTick = 1.0;
    const double secondsPerMinorTick = 0.2;

    final double pixelsPerFrame = framePixelWidth * zoom;
    if (pixelsPerFrame <= 0) return; // Avoid division by zero or negative values

    final double pixelsPerSecond = pixelsPerFrame * fps;
    final double majorTickSpacing = secondsPerMajorTick * pixelsPerSecond;
    final double minorTickSpacing = secondsPerMinorTick * pixelsPerSecond;

    // Avoid division by zero if spacing is too small
    if (minorTickSpacing <= 0) return;

    final int numMinorTicks = (size.width / minorTickSpacing).ceil();

    // Loop to draw ticks and labels
    for (int i = 0; i <= numMinorTicks; i++) {
      final double second = i * secondsPerMinorTick;
      final double x = second * pixelsPerSecond;

      // Determine if it's a major tick (close to an integer second)
      final bool isMajorTick = (second % secondsPerMajorTick).abs() < 1e-6;

      final double tickHeight = isMajorTick ? majorTickHeight : minorTickHeight;
      final Paint paintToUse = isMajorTick ? majorTickPaint : minorTickPaint;

      // Draw the tick line
      canvas.drawLine(
        Offset(x, size.height), // Start at bottom
        Offset(x, size.height - tickHeight), // End slightly above
        paintToUse,
      );

      // Draw label for major ticks if space allows
      if (isMajorTick && textStyle != null) {
        // Format label (integer or one decimal place)
        String label = (secondsPerMinorTick < 1 && second.truncateToDouble() != second)
            ? second.toStringAsFixed(1)
            : second.toStringAsFixed(0);

        textPainter.text = TextSpan(
          text: label,
          style: textStyle?.copyWith(color: textColor),
        );
        textPainter.layout();

        // Only draw label if there's enough space between major ticks
        if (majorTickSpacing > textPainter.width + textPadding) {
          final textX = x - textPainter.width / 2; // Center label
          final clampedTextX = math.max(0.0, textX); // Keep within bounds
          textPainter.paint(canvas, Offset(clampedTextX, 2)); // Position near top
        }
      }
    }
  }

  // Decide if repaint is needed based on changed properties
  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.majorTickColor != majorTickColor ||
        oldDelegate.minorTickColor != minorTickColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.isEmpty != isEmpty; // Check isEmpty flag too
  }
}
