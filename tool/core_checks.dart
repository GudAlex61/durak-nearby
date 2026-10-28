// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:async';
import 'dart:math';
import '../lib/game/engine.dart';
import '../lib/network/framing.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> main() async {
  var actions = 0;
  for (var seed = 0; seed < 1000; seed++) {
    final g = DurakGame(random: Random(seed));
    check(g.deck.first == g.trumpCard, 'Trump must be drawn last');
    var steps = 0;
    while (!g.finished && steps++ < 5000) {
      final p = g.table.isEmpty || g.taking || g.covered
          ? g.attacker
          : g.defender;
      final move = botMove(g, p)!;
      g.apply(
        p,
        move['action'] as String,
        card: move['card'] as int?,
        target: move['target'] as int?,
      );
      final cards = [
        ...g.deck,
        ...g.hands[0],
        ...g.hands[1],
        ...g.discarded,
        for (final t in g.table) ...[
          t.attack,
          if (t.defense != null) t.defense!,
        ],
      ];
      check(
        cards.length == 36 && cards.toSet().length == 36,
        'Conservation seed=$seed step=$steps',
      );
      actions++;
    }
    check(g.finished, 'Game stalled: $seed');
    final client = g.view(1);
    check(
      !client.containsKey('deck') && !client.containsKey('hands'),
      'Hidden cards exposed',
    );
  }
  print(
    'PASS: 1000 full games, $actions legal actions, 36-card conservation and private projections.',
  );
  for (final loss in ['none', 'data', 'ack']) {
    late ReliableChannel a, b;
    var dropped = false;
    var received = 0;
    final original = {'type': 'state', 'text': 'Дурак рядом ♥' * 100};
    a = ReliableChannel(
      ackTimeout: const Duration(milliseconds: 10),
      write: (f) async {
        check(f.length <= 20, 'ATT payload overflow');
        if (loss == 'data' && f[0] == 0xd0 && f[4] == 2 && !dropped) {
          dropped = true;
          return;
        }
        await b.receive(f);
      },
      onMessage: (_) {},
    );
    b = ReliableChannel(
      write: (f) async {
        if (loss == 'ack' && !dropped) {
          dropped = true;
          return;
        }
        await a.receive(f);
      },
      onMessage: (m) {
        check(m['text'] == original['text'], 'UTF8 corrupted');
        received++;
      },
    );
    await a.send(original);
    check(received == 1, 'Message duplicated or lost: $loss');
    a.close();
    b.close();
    print('PASS: UTF-8 fragmentation, exactly-once delivery, loss=$loss.');
  }
}
