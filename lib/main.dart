import 'package:flutter/material.dart';
import 'game/session.dart';
import 'ui/screens.dart';

void main() => runApp(const DurakApp());

class DurakApp extends StatefulWidget {
  const DurakApp({super.key});
  @override
  State<DurakApp> createState() => _DurakAppState();
}

class _DurakAppState extends State<DurakApp> {
  final session = GameSession();
  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Дурак рядом',
    theme: ThemeData(
      brightness: Brightness.dark,
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
    ),
    home: SessionScreen(session: session),
  );
}
