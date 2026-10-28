import 'package:flutter/material.dart';
import '../game/engine.dart';

/// Card suits are drawn as paths, so their appearance does not depend on the
/// device's fallback fonts. The Unicode label is kept for accessibility.
class SuitSymbol extends StatelessWidget {
  final int suit;
  final double size;
  final Color color;
  const SuitSymbol({
    super.key,
    required this.suit,
    this.size = 29,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: suits[suit],
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SuitPainter(suit, color)),
    ),
  );
}

class _SuitPainter extends CustomPainter {
  final int suit;
  final Color color;
  const _SuitPainter(this.suit, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final paint = Paint()..color = color;
    switch (suit) {
      case 0: // Clubs
        final stem = Path()
          ..moveTo(0.43, 0.55)
          ..lineTo(0.57, 0.55)
          ..cubicTo(0.56, 0.73, 0.61, 0.85, 0.72, 0.96)
          ..lineTo(0.28, 0.96)
          ..cubicTo(0.39, 0.85, 0.44, 0.73, 0.43, 0.55)
          ..close();
        canvas.drawPath(stem, paint);
        for (final center in [
          const Offset(0.5, 0.25),
          const Offset(0.25, 0.53),
          const Offset(0.75, 0.53),
        ]) {
          canvas.drawCircle(center, 0.235, paint);
        }
        canvas.drawCircle(const Offset(0.5, 0.5), 0.18, paint);
        break;
      case 1: // Diamonds
        canvas.drawPath(
          Path()
            ..moveTo(0.5, 0.02)
            ..lineTo(0.94, 0.5)
            ..lineTo(0.5, 0.98)
            ..lineTo(0.06, 0.5)
            ..close(),
          paint,
        );
        break;
      case 2: // Hearts
        canvas.drawPath(
          Path()
            ..moveTo(0.5, 0.94)
            ..cubicTo(0.36, 0.78, 0.03, 0.5, 0.03, 0.28)
            ..cubicTo(0.03, -0.02, 0.34, -0.03, 0.5, 0.22)
            ..cubicTo(0.66, -0.03, 0.97, -0.02, 0.97, 0.28)
            ..cubicTo(0.97, 0.5, 0.64, 0.78, 0.5, 0.94)
            ..close(),
          paint,
        );
        break;
      case 3: // Spades
        canvas.drawPath(
          Path()
            ..moveTo(0.43, 0.57)
            ..lineTo(0.57, 0.57)
            ..cubicTo(0.56, 0.75, 0.61, 0.86, 0.72, 0.98)
            ..lineTo(0.28, 0.98)
            ..cubicTo(0.39, 0.86, 0.44, 0.75, 0.43, 0.57)
            ..close(),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(0.5, 0.02)
            ..cubicTo(0.36, 0.19, 0.04, 0.4, 0.04, 0.61)
            ..cubicTo(0.04, 0.86, 0.34, 0.91, 0.5, 0.66)
            ..cubicTo(0.66, 0.91, 0.96, 0.86, 0.96, 0.61)
            ..cubicTo(0.96, 0.4, 0.64, 0.19, 0.5, 0.02)
            ..close(),
          paint,
        );
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SuitPainter oldDelegate) =>
      oldDelegate.suit != suit || oldDelegate.color != color;
}
