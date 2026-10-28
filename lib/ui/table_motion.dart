import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cards.dart';

class MotionAnchor extends StatelessWidget {
  final String id;
  final Widget child;
  const MotionAnchor({super.key, required this.id, required this.child});
  @override
  Widget build(BuildContext context) {
    final state = context
        .dependOnInheritedWidgetOfExactType<_MotionScope>()
        ?.state;
    if (state == null) return child;
    return KeyedSubtree(
      key: state.keys.putIfAbsent(id, () => GlobalKey(debugLabel: id)),
      child: Opacity(opacity: state.hidden.contains(id) ? 0 : 1, child: child),
    );
  }
}

class TableMotion extends StatefulWidget {
  static void dragOrigin(BuildContext context, int card, Offset offset) {
    context.getInheritedWidgetOfExactType<_MotionScope>()?.state.dragOrigin(
      card,
      offset,
    );
  }

  static void returnCard(BuildContext context, int card, Offset offset) {
    context.getInheritedWidgetOfExactType<_MotionScope>()?.state.returnCard(
      card,
      offset,
    );
  }

  final Map<String, dynamic> view;
  final Widget child;
  const TableMotion({super.key, required this.view, required this.child});
  @override
  State<TableMotion> createState() => _TableMotionState();
}

class _Flight {
  final Rect from, to;
  final int? card;
  final bool flip;
  final bool faceToBack;
  final double delay;
  final String? destination;
  final String? source;
  const _Flight(
    this.from,
    this.to,
    this.card, {
    this.flip = false,
    this.faceToBack = false,
    this.delay = 0,
    this.destination,
    this.source,
  });
}

class _MotionScope extends InheritedWidget {
  final _TableMotionState state;
  final int generation;
  const _MotionScope({
    required this.state,
    required this.generation,
    required super.child,
  });
  @override
  bool updateShouldNotify(_MotionScope old) => generation != old.generation;
}

class _TableMotionState extends State<TableMotion>
    with SingleTickerProviderStateMixin {
  final keys = <String, GlobalKey>{};
  final dragOrigins = <int, Rect>{};
  Rect? localDragRect(Offset offset) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.globalToLocal(offset) & const Size(62, 94)
        : null;
  }

  void dragOrigin(int card, Offset offset) {
    final rect = localDragRect(offset);
    if (rect != null) dragOrigins[card] = rect;
  }

  void returnCard(int card, Offset offset) {
    final from = localDragRect(offset), to = positions()['hand-$card'];
    if (from != null && to != null) {
      play([_Flight(from, to, card, destination: 'hand-$card')]);
    }
  }

  final hidden = <String>{};
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  List<_Flight> flights = [];
  int generation = 0;
  @override
  void initState() {
    super.initState();
    hidden.addAll([
      for (final c in widget.view['hand'] as List) 'hand-$c',
      'opponent',
    ]);
    controller.addListener(() {
      final destinations = flights
          .map((f) => f.destination)
          .whereType<String>()
          .toSet();
      final landed = destinations
          .where(
            (id) =>
                hidden.contains(id) &&
                flights
                    .where((f) => f.destination == id)
                    .every((f) => controller.value >= f.delay + .65),
          )
          .toList();
      if (landed.isNotEmpty && mounted) {
        setState(() {
          hidden.removeAll(landed);
          generation++;
        });
      }
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          flights = [];
          hidden.clear();
          generation++;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialDeal();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Map<String, Rect> positions() {
    final base = context.findRenderObject();
    if (base is! RenderBox || !base.hasSize) return {};
    final map = <String, Rect>{};
    for (final e in keys.entries) {
      final box = e.value.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        map[e.key] =
            base.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
      }
    }
    return map;
  }

  Rect pileRect(Rect rect) =>
      Rect.fromCenter(center: rect.center, width: 40, height: 58);
  Rect opponentRect(Rect rect) =>
      Rect.fromCenter(center: rect.center, width: 35, height: 48);
  void play(List<_Flight> next) {
    if (!mounted || MediaQuery.disableAnimationsOf(context) || next.isEmpty) {
      return;
    }
    setState(() {
      flights = next;
      hidden
        ..clear()
        ..addAll(
          next.expand((f) => [f.destination, f.source]).whereType<String>(),
        );
      generation++;
    });
    controller.forward(from: 0);
  }

  void _initialDeal() {
    final p = positions(), deck = p['deck'], opponent = p['opponent'];
    if (deck == null) return;
    final next = <_Flight>[];
    final hand = List<int>.from(widget.view['hand'] as List);
    for (var i = 0; i < hand.length; i++) {
      final dest = p['hand-${hand[i]}'];
      if (dest != null) {
        next.add(
          _Flight(
            pileRect(deck),
            dest,
            hand[i],
            flip: true,
            delay: i * .035,
            destination: 'hand-${hand[i]}',
          ),
        );
      }
      if (opponent != null) {
        next.add(
          _Flight(
            pileRect(deck),
            opponentRect(opponent),
            null,
            delay: i * .035 + .016,
            destination: "opponent",
          ),
        );
      }
    }
    play(next);
  }

  @override
  void didUpdateWidget(TableMotion old) {
    super.didUpdateWidget(old);
    if (old.view['revision'] == widget.view['revision']) return;
    final before = positions();
    final previous = old.view;
    final current = widget.view;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final after = positions(), next = <_Flight>[];
      final oldHand = Set<int>.from(previous['hand'] as List),
          newHand = Set<int>.from(current['hand'] as List);
      List<int> tableCards(Map<String, dynamic> v) => [
        for (final p in v['table'] as List) ...[
          p['a'] as int,
          if (p['d'] != null) p['d'] as int,
        ],
      ];
      final oldTable = tableCards(previous), newTable = tableCards(current);
      for (final card in newTable.where((c) => !oldTable.contains(c))) {
        final from =
            dragOrigins.remove(card) ??
            before['hand-$card'] ??
            before['opponent'];
        final to = after['table-$card'];
        if (from != null && to != null) {
          next.add(
            _Flight(
              before['hand-$card'] != null ? from : opponentRect(from),
              to,
              card,
              destination: 'table-$card',
            ),
          );
        }
      }
      final collected = oldTable.isNotEmpty && newTable.isEmpty;
      if (collected) {
        final discarded =
            (current['discardCount'] as int) >
            (previous['discardCount'] as int);
        for (var i = 0; i < oldTable.length; i++) {
          final c = oldTable[i];
          final from = before['table-$c'];
          final to = discarded
              ? after['discard']
              : (newHand.contains(c) ? after['hand-$c'] : after['opponent']);
          if (from != null && to != null) {
            next.add(
              _Flight(
                from,
                discarded
                    ? pileRect(to)
                    : newHand.contains(c)
                    ? to
                    : opponentRect(to),
                c,
                faceToBack: discarded || !newHand.contains(c),
                delay: i * .018,
                source: 'table-$c',
                destination: discarded
                    ? null
                    : newHand.contains(c)
                    ? 'hand-$c'
                    : null,
              ),
            );
          }
        }
      }
      for (final c in newHand.difference(oldHand)) {
        if (collected && oldTable.contains(c)) continue;
        final from = before['deck'], to = after['hand-$c'];
        if (from != null && to != null) {
          next.add(
            _Flight(
              pileRect(from),
              to,
              c,
              flip: true,
              delay: next.length * .018,
              destination: 'hand-$c',
            ),
          );
        }
      }
      final drawn =
          (previous['deckCount'] as int) -
          (current['deckCount'] as int) -
          newHand
              .difference(oldHand)
              .where((c) => !oldTable.contains(c))
              .length;
      if (drawn > 0 && before['deck'] != null && after['opponent'] != null) {
        for (var i = 0; i < math.min(drawn, 6); i++) {
          next.add(
            _Flight(
              pileRect(before['deck']!),
              opponentRect(after['opponent']!),
              null,
              delay: i * .035,
            ),
          );
        }
      }
      play(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) && hidden.isNotEmpty) {
      hidden.clear();
    }
    return _MotionScope(
      state: this,
      generation: generation,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          AbsorbPointer(absorbing: flights.isNotEmpty, child: widget.child),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Stack(
                key: const Key('flight-layer'),
                clipBehavior: Clip.none,
                children: [for (final flight in flights) _card(flight)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(_Flight f) {
    final raw = ((controller.value - f.delay) / .65).clamp(0.0, 1.0);
    if (raw >= 1) return const SizedBox.shrink();
    final t = Curves.easeInOutCubic.transform(raw);
    final rect = Rect.lerp(
      f.from,
      f.to,
      t,
    )!.shift(Offset(0, -math.sin(t * math.pi) * 28));
    final showBack =
        f.card == null || (f.flip && raw < .5) || (f.faceToBack && raw >= .5);
    final angle = f.flip || f.faceToBack
        ? (raw < .5 ? raw * math.pi : (raw - 1) * math.pi)
        : 0.0;
    return Positioned.fromRect(
      rect: rect,
      child: ExcludeSemantics(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateY(angle)
            ..rotateZ(math.sin(t * math.pi) * .08),
          child: showBack
              ? CardBack(width: rect.width, height: rect.height)
              : CardFace(card: f.card!, width: rect.width, height: rect.height),
        ),
      ),
    );
  }
}
