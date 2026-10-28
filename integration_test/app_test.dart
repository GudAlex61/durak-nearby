import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:durak_bt/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Offline game: launch, hand, attack or defense, exit', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('practice')));
    await tester.tap(find.byKey(const Key('practice')));
    await tester.pumpAndSettle(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('hand')), findsOneWidget);
    expect(find.byKey(const Key('playCard')), findsNothing);
    expect(find.byKey(const Key('attack-zone')), findsOneWidget);
    // Native smoke verifies that gesture targets are present; comprehensive
    // gesture interactions and full games run in experience_test.dart.
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practice')), findsOneWidget);
  });
}
