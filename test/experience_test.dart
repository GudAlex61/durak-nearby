import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gesture_driver.dart';
import 'package:durak_bt/game/session.dart';
import 'package:durak_bt/game/engine.dart';
import 'package:durak_bt/game/view_rules.dart';
import 'package:durak_bt/ui/screens.dart';
import 'package:durak_bt/ui/table_motion.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(393, 852),
    const Size(844, 390),
  ]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('layout $size on $platform, large text and reduced motion', (
        t,
      ) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final s = GameSession();
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: SessionScreen(session: s),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await s.startBot(seed: 42, deckSize: 24, transferable: true);
        s.setActive(false);
        await t.pumpAndSettle();
        expect(find.byType(TableMotion), findsOneWidget);
        expect(t.takeException(), isNull);
        s.dispose();
        await t.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('menu applies 24 cards, transfer mode and difficulty', (t) async {
    final s = GameSession();
    await t.pumpWidget(MaterialApp(home: SessionScreen(session: s)));
    await t.ensureVisible(find.byKey(const Key('gameSettings')));
    await t.tap(find.byKey(const Key('gameSettings')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('24'));
    await t.tap(find.text('24'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('variant')));
    await t.tap(find.byKey(const Key('variant')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Сложный'));
    await t.tap(find.text('Сложный'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('practice')));
    await t.tap(find.byKey(const Key('practice')));
    await t.pump();
    s.setActive(false);
    await t.pumpAndSettle();
    expect(s.view!['deckSize'], 24);
    expect(s.view!['transferable'], true);
    expect(s.botLevel, BotLevel.hard);
    expect(t.takeException(), isNull);
    s.dispose();
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('system back confirms exit and cancel preserves exact state', (
    t,
  ) async {
    final s = GameSession();
    await s.startBot(seed: 42);
    s.setActive(false);
    await t.pumpWidget(MaterialApp(home: SessionScreen(session: s)));
    await t.pumpAndSettle();
    final old = jsonEncode(s.view);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Выйти из партии?'), findsOneWidget);
    await t.tap(find.text('Остаться'));
    await t.pumpAndSettle();
    expect(jsonEncode(s.view), old);
    s.dispose();
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('dealing flights complete and do not duplicate semantics', (
    t,
  ) async {
    final s = GameSession();
    await s.startBot(seed: 42);
    s.setActive(false);
    await t.pumpWidget(MaterialApp(home: SessionScreen(session: s)));
    await t.pump();
    final layer = find.byKey(const Key('flight-layer'));
    expect(t.widget<Stack>(layer).children, isNotEmpty);
    await t.pump(const Duration(milliseconds: 300));
    expect(t.widget<Stack>(layer).children, isNotEmpty);
    await t.pumpAndSettle();
    expect(t.widget<Stack>(layer).children, isEmpty);
    expect(t.takeException(), isNull);
    s.dispose();
    await t.pumpWidget(const SizedBox());
  });
  for (final size in [24, 36]) {
    for (final transfer in [false, true]) {
      testWidgets(
        'complete game through gestures: $size transfer=$transfer',
        (t) async {
          t.view.physicalSize = const Size(480, 980);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final s = GameSession();
          await s.startBot(
            seed: 42,
            deckSize: size,
            transferable: transfer,
            level: BotLevel.hard,
          );
          await t.pumpWidget(MaterialApp(home: SessionScreen(session: s)));
          await t.pumpAndSettle();
          var steps = 0;
          var stuck = 0;
          while (s.view!['finished'] != true && steps++ < 1200) {
            final v = s.view!;
            final attacking = v['you'] == v['attacker'];
            final table = (v['table'] as List).cast<Map>();
            final allowed = legalCards(v);
            final transfers = transferCards(v);
            if (attacking &&
                table.isNotEmpty &&
                (v['taking'] == true || table.every((p) => p['d'] != null))) {
              await drag(
                t,
                find.byKey(const Key('table-pile')),
                find.byKey(const Key('finish-zone')),
              );
            } else if (transfers.isNotEmpty) {
              final c = transfers.first;
              await t.drag(
                find.byKey(const Key('hand')),
                const Offset(3000, 0),
              );
              await t.pumpAndSettle();
              await t.scrollUntilVisible(
                find.byKey(Key('card-$c')),
                100,
                scrollable: find.descendant(
                  of: find.byKey(const Key('hand')),
                  matching: find.byType(Scrollable),
                ),
              );
              await t.pumpAndSettle();
              await drag(
                t,
                find.byKey(Key('card-$c')),
                find.byKey(const Key('transfer-zone')),
              );
            } else if (allowed.isNotEmpty) {
              final c = allowed.first;
              await t.drag(
                find.byKey(const Key('hand')),
                const Offset(3000, 0),
              );
              await t.pumpAndSettle();
              await t.scrollUntilVisible(
                find.byKey(Key('card-$c')),
                100,
                scrollable: find.descendant(
                  of: find.byKey(const Key('hand')),
                  matching: find.byType(Scrollable),
                ),
              );
              await t.pumpAndSettle();
              final current = s.view!;
              final defending = current['you'] != current['attacker'];
              final index = (current['table'] as List).indexWhere(
                (p) => p['d'] == null,
              );
              await drag(
                t,
                find.byKey(Key('card-$c')),
                find.byKey(
                  defending
                      ? Key('defense-zone-$index')
                      : const Key('attack-zone'),
                ),
              );
            } else if (!attacking && v['taking'] != true && table.isNotEmpty) {
              await drag(
                t,
                find.byKey(const Key('table-pile')),
                find.byKey(const Key('take-zone')),
              );
            }
            await t.pumpAndSettle(const Duration(milliseconds: 100));
            await t.pump(const Duration(seconds: 2));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            if (s.view!['revision'] == v['revision']) {
              stuck++;
            } else {
              stuck = 0;
            }
            expect(
              stuck,
              lessThan(4),
              reason: 'Stalled ${jsonEncode(s.view)} error=${s.error}',
            );
          }
          expect(s.view!['finished'], true, reason: 'UI steps=$steps');
          expect(find.byKey(const Key('newGame')), findsOneWidget);
          expect(s.played, 1);
          await t.tap(find.byKey(const Key('newGame')));
          await t.pump();
          s.setActive(false);
          await t.pumpAndSettle();
          expect(s.view!['deckSize'], size);
          expect(s.view!['transferable'], transfer);
          expect(s.played, 1);
          s.dispose();
          await t.pumpWidget(const SizedBox());
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}
