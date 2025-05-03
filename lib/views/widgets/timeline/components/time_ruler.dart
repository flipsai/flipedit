import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;
// Import for ClipModel
import '../../../../services/project_database_service.dart';
// Import for Track
import '../../../../utils/logger.dart' as logger;

/// A ruler widget that displays frame numbers and tick marks for the timeline using CustomPaint
class TimeRuler extends StatelessWidget {
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

    // Get access to the database service directly
    final databaseService = di<ProjectDatabaseService>();

    // Simple direct check for tracks - this happens on every build
    final hasTracks = databaseService.tracksNotifier.value.isNotEmpty;
    final isEmpty = !hasTracks;

    // Log the current state
    logger.logInfo(
      'TimeRuler',
      'Building TimeRuler - hasTracks: $hasTracks, isEmpty: $isEmpty',
    );

    // Return the entire widget based on this simple check
    return Container(
      height: 25,
      width: availableWidth,
      color: theme.resources.subtleFillColorSecondary,
      child:
          isEmpty
              ? _buildEmptyState(theme) // Show empty state when no tracks
              : _buildRuler(theme), // Show ruler when tracks exist
    );
  }

  /// Build the empty state message
  Widget _buildEmptyState(FluentThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.resources.controlStrokeColorDefault.withOpacity(0.1),
            theme.resources.controlStrokeColorDefault.withOpacity(0.05),
          ],
        ),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.clock,
              size: 14,
              color: theme.resources.textFillColorDisabled,
            ),
            const SizedBox(width: 8),
            Text(
              'Empty timeline - drag media to begin',
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorDisabled,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the ruler with time markings
  Widget _buildRuler(FluentThemeData theme) {
    return CustomPaint(
      painter: TimeRulerPainter(
        zoom: zoom,
        majorTickColor: theme.resources.controlStrokeColorDefault,
        minorTickColor: theme.resources.textFillColorSecondary,
        textColor: theme.resources.textFillColorSecondary,
        textStyle: theme.typography.caption?.copyWith(fontSize: 10),
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

    for (int i = 0; i <= numMinorTicks; i++) {
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
