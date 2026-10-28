import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:durak_bt/game/engine.dart';
import 'package:durak_bt/game/session.dart';
import 'package:durak_bt/game/drag_rules.dart';
import 'package:durak_bt/ui/screens.dart';
import 'gesture_driver.dart';

DurakGame game({int attacker = 1, bool transfer = true}) => DurakGame.fixture(
  deck: [35],
  hands: [
    [9, 1, 2, 3],
    [0, 10, 11, 12],
  ],
  trumpCard: 35,
  attacker: attacker,
  transferable: transfer,
);
Future<GameSession> show(WidgetTester t, DurakGame g) async {
  t.view.physicalSize = const Size(480, 980);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final s = GameSession.forGame(g);
  addTearDown(s.dispose);
  await t.pumpWidget(MaterialApp(home: SessionScreen(session: s)));
  await t.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('take button commits once and disables while waiting', (t) async {
    final g = game()..apply(1, 'attack', card: 0);
    await show(t, g);
    final button = find.byKey(const Key('takeButton'));
    expect(button, findsOneWidget);
    final revision = g.revision;
    await t.tap(button);
    await t.pumpAndSettle();
    expect(g.view(0)['taking'], isTrue);
    expect(g.revision, revision + 1);
    expect(t.widget<FilledButton>(button).onPressed, isNull);
  });
  testWidgets('take button is hidden for attacker and empty table', (t) async {
    final g = game(attacker: 0);
    final s = await show(t, g);
    expect(find.byKey(const Key('takeButton')), findsNothing);
    s.action('attack', card: 9);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('takeButton')), findsNothing);
  });
  test(
    'drop resolver rejects old revision, wrong zone, bad target and finished game',
    () {
      final g = game()..apply(1, 'attack', card: 0);
      final v = g.view(0);
      expect(
        resolveDrop(v, CardDrag(9, g.revision), CardDropZone.transfer)!.action,
        'transfer',
      );
      expect(
        resolveDrop(
          v,
          CardDrag(9, g.revision),
          CardDropZone.defense,
          target: 0,
        ),
        isNull,
      );
      expect(
        resolveDrop(v, CardDrag(9, g.revision - 1), CardDropZone.transfer),
        isNull,
      );
      expect(
        resolveDrop(v, CardDrag(9, g.revision), CardDropZone.attack),
        isNull,
      );
      expect(
        resolveDrop(
          v,
          CardDrag(1, g.revision),
          CardDropZone.defense,
          target: 99,
        ),
        isNull,
      );
      g.finished = true;
      expect(
        resolveDrop(
          g.view(0),
          CardDrag(1, g.revision),
          CardDropZone.defense,
          target: 0,
        ),
        isNull,
      );
    },
  );
  test('same-rank trump defends on top and transfers only beside', () {
    final g = DurakGame.fixture(
      deck: [35],
      hands: [
        [27, 1, 2],
        [0, 10, 11, 12],
      ],
      trumpCard: 27,
      attacker: 1,
      transferable: true,
    )..apply(1, 'attack', card: 0);
    final payload = CardDrag(27, g.revision), view = g.view(0);
    expect(
      resolveDrop(view, payload, CardDropZone.defense, target: 0)!.action,
      'defend',
    );
    expect(
      resolveDrop(view, payload, CardDropZone.transfer)!.action,
      'transfer',
    );
  });
  testWidgets('placing beside transfers, placing same card on attack rejects', (
    t,
  ) async {
    final g = game()..apply(1, 'attack', card: 0);
    await show(t, g);
    final before = jsonEncode(g.view(0));
    await drag(
      t,
      find.byKey(const Key('card-9')),
      find.byKey(const Key('defense-zone-0')),
    );
    expect(jsonEncode(g.view(0)), before);
    await drag(
      t,
      find.byKey(const Key('card-9')),
      find.byKey(const Key('transfer-zone')),
    );
    expect(g.attacker, 0);
    expect(g.table.length, 2);
    expect(g.hands[0], isNot(contains(9)));
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'dropping over a particular attack defends and removes transfer slot',
    (t) async {
      final g = game()..apply(1, 'attack', card: 0);
      await show(t, g);
      await drag(
        t,
        find.byKey(const Key('card-1')),
        find.byKey(const Key('defense-zone-0')),
      );
      expect(g.table[0].defense, 1);
      expect(find.byKey(const Key('transfer-zone')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'dragging table down takes; dragging up finishes only when allowed',
    (t) async {
      final g = game()..apply(1, 'attack', card: 0);
      await show(t, g);
      final before = g.revision;
      await drag(
        t,
        find.byKey(const Key('table-pile')),
        find.byKey(const Key('finish-zone')),
      );
      expect(g.revision, before);
      await drag(
        t,
        find.byKey(const Key('table-pile')),
        find.byKey(const Key('take-zone')),
      );
      expect(g.taking, true);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('finished defense can be swept up; no gameplay buttons', (
    t,
  ) async {
    final g = game(attacker: 0)
      ..apply(0, 'attack', card: 9)
      ..apply(1, 'defend', card: 10, target: 0);
    await show(t, g);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    await drag(
      t,
      find.byKey(const Key('table-pile')),
      find.byKey(const Key('finish-zone')),
    );
    expect(g.table, isEmpty);
    expect(g.discarded, containsAll([9, 10]));
    expect(t.takeException(), isNull);
  });
  testWidgets('multirow table can be dragged from the gap between rows', (
    t,
  ) async {
    final g =
        DurakGame.fixture(
            deck: [35],
            hands: [
              [13, 17, 34, 16, 4, 6],
              [3, 21, 30, 22, 31, 7],
            ],
            trumpCard: 15,
            attacker: 1,
          )
          ..apply(1, 'attack', card: 3)
          ..apply(0, 'defend', card: 13, target: 0)
          ..apply(1, 'attack', card: 21)
          ..apply(0, 'defend', card: 17, target: 1)
          ..apply(1, 'attack', card: 30)
          ..apply(0, 'defend', card: 34, target: 2)
          ..apply(1, 'attack', card: 22)
          ..apply(0, 'defend', card: 16, target: 3)
          ..apply(1, 'attack', card: 31);
    await show(t, g);
    await drag(
      t,
      find.byKey(const Key('table-pile')),
      find.byKey(const Key('take-zone')),
    );
    expect(g.taking, true);
    expect(t.takeException(), isNull);
  });
}
