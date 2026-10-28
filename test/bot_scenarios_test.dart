import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:durak_bt/game/engine.dart';
import 'package:durak_bt/game/view_rules.dart';
import 'package:durak_bt/game/session.dart';

void main() {
  for (final level in BotLevel.values) {
    test('${level.name}: 400 complete games, legal moves and conservation', () {
      for (var seed = 0; seed < 400; seed++) {
        final g = DurakGame(random: Random(seed));
        final rng = Random(seed + 999);
        var actions = 0;
        while (!g.finished && actions++ < 5000) {
          final player = g.taking || g.covered || g.table.isEmpty
              ? g.attacker
              : g.defender;
          final move = botMove(g, player, level: level, random: rng)!;
          final before = g.revision;
          g.apply(
            player,
            move['action'] as String,
            card: move['card'] as int?,
            target: move['target'] as int?,
          );
          expect(g.revision, before + 1);
          final all = [
            ...g.deck,
            ...g.hands[0],
            ...g.hands[1],
            ...g.discarded,
            for (final p in g.table) ...[
              p.attack,
              if (p.defense != null) p.defense!,
            ],
          ];
          expect(all.length, 36, reason: '$level $seed $actions');
          expect(all.toSet().length, 36);
          for (var you = 0; you < 2; you++) {
            final v = g.view(you);
            final allowed = legalCards(v);
            for (final c in List<int>.from(v['hand'] as List)) {
              final snapshot = jsonEncode(g.view(you));
              if (g.finished) {
                expect(allowed, isEmpty);
                break;
              }
              final copy = DurakGame.fixture(
                deck: g.deck,
                hands: g.hands,
                trumpCard: g.trumpCard,
                attacker: g.attacker,
              );
              copy.limit = g.limit;
              copy.taking = g.taking;
              copy.table.addAll(
                g.table.map((p) => TablePair(p.attack, p.defense)),
              );
              final target = copy.table.indexWhere((p) => p.defense == null);
              try {
                copy.apply(
                  you,
                  you == copy.attacker ? 'attack' : 'defend',
                  card: c,
                  target: target,
                );
                expect(allowed, contains(c));
              } on RuleError {
                expect(allowed, isNot(contains(c)));
              }
              expect(jsonEncode(g.view(you)), snapshot);
            }
          }
        }
        expect(g.finished, true, reason: '$level seed=$seed steps=$actions');
      }
    });
  }
  test('hard bot preserves an expensive trump when opponent already takes', () {
    DurakGame make() => DurakGame.fixture(
      deck: [35],
      hands: [
        [0, 26, 18],
        [1, 2, 3],
      ],
      trumpCard: 18,
    );
    final normal = make()
      ..apply(0, 'attack', card: 0)
      ..apply(1, 'take');
    expect(botMove(normal, 0, level: BotLevel.normal)!['action'], 'attack');
    final hard = make()
      ..apply(0, 'attack', card: 0)
      ..apply(1, 'take');
    // The matching low trump is legal; expensive trumps are tested below.
    expect(botMove(hard, 0, level: BotLevel.hard), isNotNull);
    final g =
        DurakGame.fixture(
            deck: [35],
            hands: [
              [8, 26],
              [1, 2],
            ],
            trumpCard: 18,
          )
          ..apply(0, 'attack', card: 8)
          ..apply(1, 'take');
    expect(botMove(g, 0, level: BotLevel.hard)!['action'], 'finish');
  });
  test(
    'hard bot resolves constrained attack before spending flexible trump',
    () {
      final g =
          DurakGame.fixture(
              deck: [35],
              hands: [
                [0, 9, 2],
                [10, 27, 3],
              ],
              trumpCard: 27,
            )
            ..apply(0, 'attack', card: 0)
            ..apply(0, 'attack', card: 9);
      final move = botMove(g, 1, level: BotLevel.hard)!;
      expect(move['action'], 'defend');
      expect(move['card'], isNot(27));
    },
  );
  testWidgets('bot stops in background, resumes, and reset cancels old timer', (
    t,
  ) async {
    final s = GameSession();
    await s.startBot(seed: 42, level: BotLevel.hard);
    s.setActive(false);
    final before = jsonEncode(s.view);
    await t.pump(const Duration(seconds: 8));
    expect(jsonEncode(s.view), before);
    await s.reset();
    s.setActive(true);
    await t.pump(const Duration(seconds: 4));
    expect(s.view, isNull);
    await s.startBot(seed: 42, level: BotLevel.easy);
    expect(s.botLevel, BotLevel.easy);
    await s.reset();
    s.dispose();
  });
}
