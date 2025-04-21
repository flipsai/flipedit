import 'package:flutter/widgets.dart';

class TrackBackgroundPainter extends CustomPainter {
  final double zoom;
  final Color lineColor;
  final Color faintLineColor;
  final Color textColor;

  final Paint linePaint;
  final Paint faintLinePaint;

  TrackBackgroundPainter({
    required this.zoom,
    required this.lineColor,
    required this.faintLineColor,
    required this.textColor,
  })  : linePaint = Paint()..strokeWidth = 1.0,
        faintLinePaint = Paint()..strokeWidth = 0.5 {
    linePaint.color = lineColor;
    faintLinePaint.color = faintLineColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double framePixelWidth = 5.0;
    const int framesPerMajorTick = 30;
    const int framesPerMinorTick = 5;
    final double effectiveFrameWidth = framePixelWidth * zoom;
    if (effectiveFrameWidth <= 0) return;
    final int totalMinorTicks =
        (size.width / (effectiveFrameWidth * framesPerMinorTick)).ceil() + 1;
    for (int i = 0; i < totalMinorTicks; i++) {
      final int frameNumber = i * framesPerMinorTick;
      final double x = frameNumber * effectiveFrameWidth;
      final bool isMajorTick = frameNumber % framesPerMajorTick == 0;
      final paintToUse = isMajorTick ? linePaint : faintLinePaint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintToUse);
    }
  }

  @override
  bool shouldRepaint(covariant TrackBackgroundPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.faintLineColor != faintLineColor ||
        oldDelegate.textColor != textColor;
  }
}
