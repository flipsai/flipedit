import 'package:flutter/widgets.dart';
import 'dart:math' as math;

class EffectPatternPainter extends CustomPainter {
  final Color color;
  final int seed;

  EffectPatternPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final random = math.Random(seed);
    final path = Path();
    path.moveTo(0, size.height / 2);
    double step = size.width / 10;
    double amplitude = size.height / 3;
    double x = 0;
    while (x < size.width) {
      double y = size.height / 2 + (random.nextDouble() * 2 - 1) * amplitude;
      path.lineTo(x, y);
      x += step;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate is EffectPatternPainter && oldDelegate.seed != seed;
}
