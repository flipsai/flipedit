import 'package:flutter/widgets.dart';
import 'dart:math' as math;

class AudioWaveformPainter extends CustomPainter {
  final Color color;
  final int seed;

  AudioWaveformPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
    final path = Path();
    final random = math.Random(seed);
    final waveHeight = size.height * 0.6;
    final middleY = size.height / 2;
    path.moveTo(0, middleY);
    const step = 3.0;
    for (double x = step; x < size.width; x += step) {
      final y = middleY + (random.nextDouble() * 2 - 1) * (waveHeight / 2);
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}
