import 'package:flutter/widgets.dart';

class TextLinesPainter extends CustomPainter {
  final Color color;

  TextLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final lineSpacing = size.height / 5;
    for (int i = 1; i < 5; i++) {
      final y = lineSpacing * i;
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
