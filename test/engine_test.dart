import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:durak_bt/game/engine.dart';

void main() {
  test('36 unique cards, six per player, visible trump is drawn last', () {
    final g = DurakGame(random: Random(42));
    expect(g.deck.length, 24);
    expect(g.hands.map((h) => h.length), [6, 6]);
    expect({...g.deck, ...g.hands[0], ...g.hands[1]}.length, 36);
    expect(g.deck.first, g.trumpCard);
    final trumps = [
      for (var p = 0; p < 2; p++)
        for (final c in g.hands[p])
          if (suitOf(c) == g.trump) (rankOf(c), p),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (trumps.isNotEmpty) expect(g.attacker, trumps.first.$2);
  });
  test('beating requires a higher same suit or a trump against non-trump', () {
    expect(beats(1, 0, 3), true);
    expect(beats(0, 1, 3), false);
    expect(beats(9, 0, 3), false);
    expect(beats(27, 8, 3), true);
    expect(beats(8, 27, 3), false);
  });
  test('invalid action leaves game unchanged', () {
    final g = DurakGame(random: Random(7));
    final old = g.revision;
    expect(
      () => g.apply(g.defender, 'attack', card: g.hands[g.defender].first),
      throwsA(isA<RuleError>()),
    );
    expect(g.revision, old);
    expect(g.table, isEmpty);
  });
  test('throw-in uses all ranks on table including defense ranks', () {
    final g = DurakGame.fixture(
      deck: [35],
      hands: [
        [0, 10, 3],
        [1, 11, 30],
      ],
      trumpCard: 35,
    );
    g.apply(0, 'attack', card: 0);
    g.apply(1, 'defend', card: 1, target: 0);
    g.apply(0, 'attack', card: 10); // rank 7 from defense
    expect(g.table.length, 2);
    expect(() => g.apply(0, 'attack', card: 3), throwsA(isA<RuleError>()));
  });
  test('defender takes all cards, attacker draws first and attacks again', () {
    final g = DurakGame.fixture(
      deck: [35, 34, 33],
      hands: [
        [0, 9],
        [1, 10],
      ],
      trumpCard: 35,
    );
    g.apply(0, 'attack', card: 0);
    g.apply(1, 'take');
    g.apply(0, 'attack', card: 9);
    expect(
      () => g.apply(1, 'defend', card: 1, target: 0),
      throwsA(isA<RuleError>()),
    );
    g.apply(0, 'finish');
    expect(g.attacker, 0);
    expect(g.hands[0], [33, 34, 35]);
    expect(g.hands[1], containsAll([0, 9, 1, 10]));
    expect(g.table, isEmpty);
  });
  test('successful defense changes attacker and discards beaten cards', () {
    final g = DurakGame.fixture(
      deck: [35],
      hands: [
        [0, 2],
        [1, 3],
      ],
      trumpCard: 35,
    );
    g.apply(0, 'attack', card: 0);
    expect(() => g.apply(0, 'finish'), throwsA(isA<RuleError>()));
    g.apply(1, 'defend', card: 1, target: 0);
    g.apply(0, 'finish');
    expect(g.attacker, 1);
    expect(g.discarded, [0, 1]);
    expect(g.hands[0], contains(35));
  });
  test('throw-in limit is defender starting hand, maximum six', () {
    final g = DurakGame.fixture(
      deck: [],
      hands: [
        [0, 9, 18],
        [1],
      ],
      trumpCard: 35,
    );
    g.apply(0, 'attack', card: 0);
    g.apply(1, 'take');
    expect(() => g.apply(0, 'attack', card: 9), throwsA(isA<RuleError>()));
  });
  test('simultaneous last cards after successful defense are a draw', () {
    final g = DurakGame.fixture(
      deck: [],
      hands: [
        [0],
        [1],
      ],
      trumpCard: 35,
    );
    g.apply(0, 'attack', card: 0);
    g.apply(1, 'defend', card: 1, target: 0);
    g.apply(0, 'finish');
    expect(g.finished, true);
    expect(g.loser, null);
  });
  test('loser is the player with remaining cards, after round resolves', () {
    final g = DurakGame.fixture(
      deck: [],
      hands: [
        [0],
        [1],
      ],
      trumpCard: 35,
    );
    g.apply(0, 'attack', card: 0);
    g.apply(1, 'take');
    expect(g.finished, false);
    g.apply(0, 'finish');
    expect(g.finished, true);
    expect(g.loser, 1);
  });
  test('client projection does not expose deck order or opponent hand', () {
    final g = DurakGame(random: Random(42));
    final v = g.view(1);
    expect(v.containsKey('deck'), false);
    expect(v.containsKey('hands'), false);
    expect(v['hand'], g.hands[1]);
    (v['hand'] as List).clear();
    expect(g.hands[1].length, 6);
  });
  test('1000 seeded full games preserve all 36 cards after every action', () {
    for (var seed = 0; seed < 1000; seed++) {
      final g = DurakGame(random: Random(seed));
      var steps = 0;
      while (!g.finished && steps++ < 5000) {
        final p = g.taking || g.covered || g.table.isEmpty
            ? g.attacker
            : g.defender;
        final move = botMove(g, p)!;
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
          for (final pair in g.table) ...[
            pair.attack,
            if (pair.defense != null) pair.defense!,
          ],
        ];
        expect(all.length, 36, reason: 'seed=$seed step=$steps');
        expect(all.toSet().length, 36);
      }
      expect(g.finished, true, reason: 'seed=$seed');
    }
  });
}
