import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:durak_bt/game/session.dart';
import 'package:durak_bt/ui/screens.dart';

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('Home and table fit ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = GameSession();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: SessionScreen(session: session),
        ),
      );
      expect(find.byKey(const Key('practice')), findsOneWidget);
      await session.startBot(seed: 42);
      await tester.pump();
      expect(find.byKey(const Key('hand')), findsOneWidget);
      expect(find.byKey(const Key('turnLabel')), findsOneWidget);
      expect(tester.takeException(), isNull);
      session.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('Help dialog and returning to menu work', (tester) async {
    final session = GameSession();
    await tester.pumpWidget(MaterialApp(home: SessionScreen(session: session)));
    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Как играть'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('practice')));
    await tester.tap(find.byKey(const Key('practice')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practice')), findsOneWidget);
    session.dispose();
  });
}
