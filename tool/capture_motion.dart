// QA renderer: actual Flutter widgets, not a recording from an iPhone.
// DURAK_QA_FONT=/path/to/font.ttf flutter test tool/capture_motion.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:durak_bt/game/session.dart';
import 'package:durak_bt/game/view_rules.dart';
import 'package:durak_bt/game/drag_rules.dart';
import 'package:durak_bt/ui/screens.dart';
import '../test/gesture_driver.dart';

void main() {
  testWidgets('render deal and attack with real Flutter animation frames', (
    t,
  ) async {
    final font = Platform.environment['DURAK_QA_FONT'];
    if (font == null) {
      throw StateError('Set DURAK_QA_FONT to a Cyrillic-capable TTF.');
    }
    final loader = FontLoader('QA');
    loader.addFont(
      Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
    );
    await loader.load();
    final iconPath = Platform.environment['DURAK_QA_ICON_FONT'];
    if (iconPath != null) {
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        Future.value(ByteData.sublistView(File(iconPath).readAsBytesSync())),
      );
      await icons.load();
    }
    t.view.physicalSize = const Size(480, 960);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = GameSession();
    for (var seed = 0; seed < 100; seed++) {
      await s.startBot(seed: seed, deckSize: 24, transferable: true);
      if (s.view!['attacker'] == 0) break;
    }
    s.setActive(false);
    final boundary = GlobalKey();
    final theme = ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'QA',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffd9b875),
        brightness: Brightness.dark,
        surface: const Color(0xff122f29),
      ),
      scaffoldBackgroundColor: const Color(0xff0a221d),
      useMaterial3: true,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: SessionScreen(session: s),
        ),
      ),
    );
    final dir = Directory(
      Platform.environment['DURAK_QA_FRAMES'] ?? '../motion-frames',
    )..createSync(recursive: true);
    var index = 0;
    Future<void> shot() async {
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${dir.path}/frame-${(index++).toString().padLeft(4, '0')}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (var i = 0; i < 24; i++) {
      await t.pump(const Duration(milliseconds: 40));
      await shot();
    }
    await t.pumpAndSettle();
    final c = legalCards(s.view!).firstWhere(
      (c) => find.byKey(Key('card-$c')).hitTestable().evaluate().isNotEmpty,
    );
    final start = t.getCenter(find.byKey(Key('card-$c'))),
        end = t.getCenter(find.byKey(const Key('attack-zone')));
    final gesture = await t.startGesture(start);
    await gesture.moveBy(const Offset(0, -24));
    await t.pump(const Duration(milliseconds: 30));
    for (var i = 0; i < 12; i++) {
      await gesture.moveTo(Offset.lerp(start, end, (i + 1) / 12)!);
      await t.pump(const Duration(milliseconds: 30));
      await shot();
    }
    await gesture.up();
    await t.pump();
    for (var i = 0; i < 24; i++) {
      await t.pump(const Duration(milliseconds: 40));
      await shot();
    }
    expect(s.view!['table'], hasLength(1));
    s.setActive(true);
    await t.pump(const Duration(milliseconds: 850));
    for (var i = 0; i < 24; i++) {
      await t.pump(const Duration(milliseconds: 40));
      await shot();
    }
    await t.pumpAndSettle();
    await drag(
      t,
      find.byKey(const Key('table-pile')),
      find.byKey(
        canFinishTable(s.view!)
            ? const Key('finish-zone')
            : const Key('take-zone'),
      ),
    );
    await t.pump();
    for (var i = 0; i < 48; i++) {
      await t.pump(const Duration(milliseconds: 40));
      await shot();
    }

    s.setActive(false);
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 40));
      await shot();
    }
    expect(t.takeException(), isNull);
    s.dispose();
    await t.pumpWidget(const SizedBox());
  });
}
