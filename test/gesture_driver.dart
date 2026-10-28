import 'package:flutter_test/flutter_test.dart';

Future<void> drag(WidgetTester t, Finder from, Finder to) async {
  await t.ensureVisible(from);
  await t.pumpAndSettle();
  final start = t.getCenter(from), end = t.getCenter(to);
  final gesture = await t.startGesture(start);
  await gesture.moveBy(const Offset(0, -24));
  await t.pump(const Duration(milliseconds: 30));
  await gesture.moveTo(end);
  await t.pump(const Duration(milliseconds: 80));
  await gesture.up();
  await t.pumpAndSettle();
}
