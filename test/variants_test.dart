import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:durak_bt/game/engine.dart';
import 'package:durak_bt/game/view_rules.dart';

DurakGame fixture({bool transfer = true}) => DurakGame.fixture(
  deck: [35],
  hands: [
    [0, 18, 1, 2, 3, 4],
    [9, 27, 10, 11, 12, 13],
  ],
  trumpCard: 35,
  transferable: transfer,
);
void main() {
  test('24-card deck uses 9 through ace and draws visible trump last', () {
    for (var seed = 0; seed < 100; seed++) {
      final g = DurakGame(deckSize: 24, random: Random(seed));
      final all = [...g.deck, ...g.hands[0], ...g.hands[1]];
      expect(all.length, 24);
      expect(all.toSet().length, 24);
      expect(all.every((c) => rankOf(c) >= 3), true);
      expect(g.deck.length, 12);
      expect(g.deck.first, g.trumpCard);
      expect(g.view(0)['deckSize'], 24);
    }
    expect(() => DurakGame(deckSize: 30), throwsArgumentError);
  });
  test(
    'transfer switches roles, permits return, and recalculates capacity',
    () {
      final g = fixture()..apply(0, 'attack', card: 0);
      expect(transferCards(g.view(1)), containsAll([9, 27]));
      g.apply(1, 'transfer', card: 9);
      expect(g.attacker, 1);
      expect(g.limit, 5);
      g.apply(0, 'transfer', card: 18);
      expect(g.attacker, 0);
      expect(g.limit, 5);
      g.apply(1, 'transfer', card: 27);
      expect(g.attacker, 1);
      expect(g.limit, 4);
      expect(g.table.length, 4);
      g.apply(0, 'take');
      g.apply(1, 'finish');
      expect(g.hands[0], containsAll([0, 9, 18, 27]));
      expect(g.attacker, 1);
    },
  );
  test('invalid transfers never mutate state', () {
    void rejects(DurakGame g, int player, int card) {
      final before = jsonEncode([g.view(0), g.view(1)]);
      expect(
        () => g.apply(player, 'transfer', card: card),
        throwsA(isA<RuleError>()),
      );
      expect(jsonEncode([g.view(0), g.view(1)]), before);
    }

    rejects(fixture(), 1, 9); // Empty table.
    rejects(fixture(transfer: false)..apply(0, 'attack', card: 0), 1, 9);
    rejects(fixture()..apply(0, 'attack', card: 0), 0, 18); // Attacker.
    rejects(fixture()..apply(0, 'attack', card: 0), 1, 10); // Wrong rank.
    rejects(fixture()..apply(0, 'attack', card: 0), 1, 35); // Not owned.
    rejects(
      fixture()
        ..apply(0, 'attack', card: 0)
        ..apply(1, 'take'),
      1,
      9,
    );
    rejects(
      fixture()
        ..apply(0, 'attack', card: 0)
        ..apply(1, 'defend', card: 27, target: 0),
      1,
      9,
    );
    final short = DurakGame.fixture(
      deck: [],
      hands: [
        [0, 1],
        [9, 10],
      ],
      trumpCard: 35,
      transferable: true,
    )..apply(0, 'attack', card: 0);
    expect(transferCards(short.view(1)), isEmpty);
    rejects(short, 1, 9);
  });
  for (final size in [24, 36]) {
    for (final transfer in [false, true]) {
      for (final level in BotLevel.values) {
        test(
          '$size cards / transfer=$transfer / ${level.name}: 100 complete games',
          () {
            for (var seed = 0; seed < 100; seed++) {
              final g = DurakGame(
                random: Random(seed),
                deckSize: size,
                transferable: transfer,
              );
              final random = Random(seed + 1000);
              var moves = 0;
              while (!g.finished && moves++ < 5000) {
                final p = g.table.isEmpty || g.taking || g.covered
                    ? g.attacker
                    : g.defender;
                final move = botMove(g, p, level: level, random: random)!;
                g.apply(
                  p,
                  move['action'] as String,
                  card: move['card'] as int?,
                  target: move['target'] as int?,
                );
                final all = [
                  ...g.deck,
                  ...g.hands[0],
                  ...g.hands[1],
                  ...g.discarded,
                  for (final t in g.table) ...[
                    t.attack,
                    if (t.defense != null) t.defense!,
                  ],
                ];
                expect(all.length, size);
                expect(all.toSet().length, size);
              }
              expect(g.finished, true, reason: 'seed=$seed moves=$moves');
            }
          },
        );
      }
    }
  }
  test(
    'bot decisions are independent of unseen opponent cards and deck order',
    () {
      for (final level in BotLevel.values) {
        final a = DurakGame.fixture(
          deck: [35, 34],
          hands: [
            [0, 1, 9],
            [18, 19, 20],
          ],
          trumpCard: 35,
        );
        final b = DurakGame.fixture(
          deck: [34, 35],
          hands: [
            [0, 1, 9],
            [21, 22, 23],
          ],
          trumpCard: 35,
        );
        expect(
          botMove(a, 0, level: level, random: Random(2)),
          botMove(b, 0, level: level, random: Random(2)),
        );
      }
    },
  );
}
