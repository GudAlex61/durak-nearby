import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../game/engine.dart';
import 'suit_symbol.dart';

const gold = Color(0xffe9c67d);
const cream = Color(0xfffff8e9);
const muted = Color(0xff9eb9ae);
Duration motion(BuildContext c, [int ms = 360]) =>
    MediaQuery.disableAnimationsOf(c)
    ? Duration.zero
    : Duration(milliseconds: ms);

class Arrive extends StatelessWidget {
  final Widget child;
  final Offset from;
  const Arrive({
    super.key,
    required this.child,
    this.from = const Offset(0, 35),
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: motion(context),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (c, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: from * (1 - value),
        child: Transform.rotate(angle: (1 - value) * 0.08, child: child),
      ),
    ),
  );
}

class CardFace extends StatelessWidget {
  final int card;
  final bool selected, suggested;
  final double width, height;
  const CardFace({
    super.key,
    required this.card,
    this.selected = false,
    this.suggested = false,
    this.width = 62,
    this.height = 88,
  });
  @override
  Widget build(BuildContext context) {
    final color = [1, 2].contains(suitOf(card))
        ? const Color(0xffbf3e4e)
        : const Color(0xff183a32);
    Widget corner() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ranks[rankOf(card)],
          style: TextStyle(
            color: color,
            fontSize: width * 0.25,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        SuitSymbol(suit: suitOf(card), color: color, size: width * 0.16),
      ],
    );
    return AnimatedContainer(
      duration: motion(context, 180),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? gold
              : suggested
              ? const Color(0xff80bca5)
              : const Color(0xffe4dece),
          width: selected ? 3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: selected ? 12 : 4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(left: 6, top: 6, child: corner()),
          Center(
            child: SuitSymbol(
              suit: suitOf(card),
              color: color,
              size: width * 0.43,
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Transform.rotate(angle: math.pi, child: corner()),
          ),
        ],
      ),
    );
  }
}

class CardBack extends StatelessWidget {
  final double width, height;
  const CardBack({super.key, this.width = 42, this.height = 60});
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xff263d51),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xffd3bd8d)),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2)),
      ],
    ),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xff82989c)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: width * .30,
            height: width * .30,
            decoration: BoxDecoration(border: Border.all(color: gold)),
          ),
        ),
      ),
    ),
  );
}

class FeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 6; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: size.width * .80 + i * 42,
          height: size.height * .68 + i * 28,
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(FeltPainter oldDelegate) => false;
}

class DeckPile extends StatelessWidget {
  final int trumpCard, count;
  const DeckPile({super.key, required this.trumpCard, required this.count});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 110,
    height: 70,
    child: count == 0
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SuitSymbol(suit: suitOf(trumpCard), color: gold, size: 22),
              const Text(
                'Колода пуста',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ],
          )
        : Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 46,
                top: 7,
                child: Transform.rotate(
                  angle: math.pi / 2,
                  child: CardFace(card: trumpCard, width: 40, height: 58),
                ),
              ),
              if (count > 1) ...[
                for (var i = 0; i < math.min(count - 1, 4); i++)
                  Positioned(
                    left: 12 + i * 1.5,
                    top: i * 1.0,
                    child: const CardBack(width: 40, height: 58),
                  ),
              ],
            ],
          ),
  );
}
