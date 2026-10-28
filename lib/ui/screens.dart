import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game/engine.dart';
import '../game/session.dart';
import 'cards.dart';
import 'gesture_table.dart';
export 'cards.dart' show CardFace;

class SessionScreen extends StatefulWidget {
  final GameSession session;
  const SessionScreen({super.key, required this.session});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver {
  final code = TextEditingController();
  BotLevel level = BotLevel.normal;
  int deckSize = 36;
  bool transferable = false;
  bool _leaving = false;
  GameSession get s => widget.session;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      s.setActive(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    code.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving || s.mode == 'home') return;
    _leaving = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выйти из партии?'),
        content: const Text('Текущая партия будет закрыта на этом телефоне.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    _leaving = false;
    if (leave == true && mounted) {
      await s.reset();
    }
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Как играть'),
      content: const SingleChildScrollView(
        child: Text(
          '24 или 36 карт, по 6 каждому.\n\nПеретащите карту из руки на свободное место стола для атаки или подкидывания.\n\nДля защиты положите старшую карту той же масти или козырь прямо поверх небитой карты. Для перевода положите карту того же достоинства в подсвеченное место РЯДОМ с атакой. Перевод возможен только до первой защиты и при достаточной руке соперника.\n\nЧтобы взять, перетащите стопку со стола вниз в свою руку. Соперник может подкинуть и затем завершает розыгрыш.\n\nЧтобы завершить розыгрыш, перетащите стол вверх к сопернику: после защиты это бита, после «беру» — передача карт. Сначала добирает атакующий.\n\nПрокрутка руки — влево/вправо. Перемещение карты — начните тянуть вверх. Недопустимая карта вернётся в руку.\n\nБот работает без Bluetooth. Для игры вдвоём создайте стол на одном телефоне, найдите его на другом и введите код. Держите оба приложения открытыми.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) => PopScope(
      canPop: s.mode == 'home',
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          centerTitle: true,
          title: const Text(
            'ДУРАК РЯДОМ',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            ),
          ),
          leading: s.mode == 'home'
              ? null
              : IconButton(
                  key: const Key('back'),
                  tooltip: 'Выйти из партии',
                  onPressed: _leave,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
          actions: [
            IconButton(
              tooltip: 'Правила',
              onPressed: _help,
              icon: const Icon(Icons.help_outline_rounded),
            ),
          ],
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xff122f2b), Color(0xff081e1a)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                if (s.error != null)
                  MaterialBanner(
                    content: Text(s.error!),
                    actions: [
                      TextButton(
                        onPressed: s.dismissError,
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
                if (s.busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: s.view == null ? _lobby() : _game(s.view!)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _lobby() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.mode == 'home') ...[
              SizedBox(
                height: 96,
                child: Center(
                  child: SizedBox(
                    width: 200,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Transform.translate(
                            offset: Offset((i - 1) * 47.0, i == 1 ? 0 : 12),
                            child: Transform.rotate(
                              angle: (i - 1) * .22,
                              child: CardFace(
                                card: [8, 26, 35][i],
                                width: 73,
                                height: 108,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Хорошая компания.\nДаже без сети.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Сыграйте с ботом или другом рядом',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xff1c3b33),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: gold.withValues(alpha: .2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ВАШ СОПЕРНИК',
                      style: TextStyle(
                        color: gold,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<BotLevel>(
                      showSelectedIcon: false,
                      segments: [
                        for (final l in BotLevel.values)
                          ButtonSegment(
                            value: l,
                            label: Text(
                              l.label,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                      selected: {level},
                      onSelectionChanged: (v) =>
                          setState(() => level = v.first),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      level.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('practice'),
                      onPressed: () => s.startBot(
                        seed: const bool.fromEnvironment('TEST_MODE')
                            ? 42
                            : null,
                        level: level,
                        deckSize: deckSize,
                        transferable: transferable,
                      ),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: const Text('Играть с ботом'),
                    ),
                    ExpansionTile(
                      key: const Key('gameSettings'),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: const Text(
                        'Настройки партии',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '$deckSize карт · ${transferable ? 'Переводной' : 'Подкидной'}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      children: [
                        Column(
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Колода',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                                const Spacer(),
                                SegmentedButton<int>(
                                  key: const Key('deckSize'),
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(value: 24, label: Text('24')),
                                    ButtonSegment(value: 36, label: Text('36')),
                                  ],
                                  selected: {deckSize},
                                  onSelectionChanged: (v) =>
                                      setState(() => deckSize = v.first),
                                ),
                              ],
                            ),
                            SwitchListTile.adaptive(
                              key: const Key('variant'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Переводной',
                                style: TextStyle(fontSize: 14),
                              ),
                              subtitle: const Text(
                                'Можно передать атаку сопернику',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                              value: transferable,
                              onChanged: (v) =>
                                  setState(() => transferable = v),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('host'),
                      onPressed: () => s.host(
                        deckSize: deckSize,
                        transferable: transferable,
                      ),
                      icon: const Icon(Icons.bluetooth_rounded, size: 18),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Создать стол',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('join'),
                      onPressed: s.scan,
                      icon: const Icon(Icons.radar_rounded, size: 18),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Найти стол рядом',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                s.played == 0
                    ? '36 карт · Подкидной · Без интернета'
                    : 'За эту сессию: ${s.wins} побед · ${s.losses} поражений · ${s.draws} ничьих',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ] else ...[
              const Icon(Icons.bluetooth_rounded, size: 56, color: gold),
              const SizedBox(height: 20),
              Text(
                s.isHost ? 'Ваш стол открыт' : 'Найдём ваш стол',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(s.status, style: const TextStyle(color: muted)),
              const SizedBox(height: 24),
              if (s.isHost) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xff1c3b33),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'КОД СТОЛА',
                        style: TextStyle(color: muted, letterSpacing: 3),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        s.roomCode,
                        style: const TextStyle(
                          color: gold,
                          fontSize: 42,
                          letterSpacing: 5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'На втором телефоне нажмите «Найти стол рядом» и введите этот код.',
                ),
              ] else ...[
                TextField(
                  key: const Key('roomCode'),
                  controller: code,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Код с телефона ведущего',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (s.tables.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Пока никого. Убедитесь, что ведущий создал стол и оба приложения открыты.',
                    ),
                  ),
                for (final table in s.tables)
                  Card(
                    child: ListTile(
                      title: Text(table.name),
                      subtitle: const Text('Bluetooth Low Energy'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: s.busy ? null : () => s.join(table, code.text),
                    ),
                  ),
                TextButton(
                  onPressed: s.busy ? null : s.scan,
                  child: const Text('Повторить поиск'),
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );

  Widget _game(Map<String, dynamic> v) =>
      GestureTable(key: ValueKey(s.gameId), session: s);
}
