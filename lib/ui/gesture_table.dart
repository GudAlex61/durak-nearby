import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import '../game/engine.dart';
import '../game/session.dart';
import '../game/drag_rules.dart';
import '../game/view_rules.dart';
import 'cards.dart';
import 'table_motion.dart';

class GestureTable extends StatefulWidget {
  final GameSession session;
  const GestureTable({super.key, required this.session});
  @override
  State<GestureTable> createState() => _GestureTableState();
}

class _GestureTableState extends State<GestureTable> {
  GameSession get s => widget.session;
  Map<String, dynamic> get v => s.view!;
  int? draggingCard, selectedCard;
  bool draggingTable = false;
  String? rejection;
  bool get ready => s.canPlay && v['finished'] != true;
  bool get attacking => v['you'] == v['attacker'];

  CardMove? move(CardDrag d, CardDropZone zone, int? target) =>
      ready ? resolveDrop(v, d, zone, target: target) : null;
  void accept(
    BuildContext c,
    DragTargetDetails<CardDrag> d,
    CardDropZone zone,
    int? target,
  ) {
    final proposal = move(d.data, zone, target);
    if (proposal == null) {
      TableMotion.returnCard(c, d.data.card, d.offset);
      return;
    }
    rejection = null;
    TableMotion.dragOrigin(c, d.data.card, d.offset);
    HapticFeedback.lightImpact();
    s.action(proposal.action, card: proposal.card, target: proposal.target);
  }

  Widget cardTarget({
    required Key key,
    required CardDropZone zone,
    int? target,
    required Widget child,
    bool outline = false,
  }) => Builder(
    builder: (c) => DragTarget<CardDrag>(
      key: key,
      onWillAcceptWithDetails: (d) => move(d.data, zone, target) != null,
      onAcceptWithDetails: (d) => accept(c, d, zone, target),
      builder: (context, accepted, rejected) => AnimatedContainer(
        duration: motion(context, 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accepted.isNotEmpty
                ? gold
                : rejected.isNotEmpty
                ? const Color(0xffd58080)
                : outline
                ? gold.withValues(alpha: .35)
                : Colors.transparent,
            width: 2,
          ),
          color: accepted.isNotEmpty
              ? gold.withValues(alpha: .12)
              : Colors.transparent,
        ),
        child: child,
      ),
    ),
  );

  Widget pileTarget({
    required Key key,
    required bool take,
    required Widget child,
  }) => DragTarget<TableDrag>(
    key: key,
    onWillAcceptWithDetails: (d) =>
        ready &&
        d.data.revision == v['revision'] &&
        (take ? canTakeTable(v) : canFinishTable(v)),
    onAcceptWithDetails: (d) {
      if (!ready || d.data.revision != v['revision']) return;
      if (take ? canTakeTable(v) : canFinishTable(v)) {
        HapticFeedback.mediumImpact();
        s.action(take ? 'take' : 'finish');
      }
    },
    builder: (context, accepted, rejected) => AnimatedContainer(
      duration: motion(context, 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accepted.isNotEmpty
            ? gold.withValues(alpha: .16)
            : Colors.transparent,
        border: Border.all(
          color: accepted.isNotEmpty
              ? gold
              : draggingTable && (take ? canTakeTable(v) : canFinishTable(v))
              ? gold.withValues(alpha: .5)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) => TableMotion(
      view: v,
      child: LayoutBuilder(
        builder: (context, c) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final minHeight = 650.0 + math.max(0.0, scale - 1) * 260.0;
          return c.maxHeight < minHeight
              ? SingleChildScrollView(
                  child: SizedBox(height: minHeight, child: body()),
                )
              : body();
        },
      ),
    ),
  );

  Widget body() {
    final table = (v['table'] as List).cast<Map>();
    final finished = v['finished'] == true;
    final legal = legalCards(v), transfers = transferCards(v);
    final hand = List<int>.from(v['hand'] as List)
      ..sort((a, b) {
        int score(int c) =>
            (suitOf(c) == suitOf(v['trumpCard'] as int) ? 100 : 0) +
            suitOf(c) * 9 +
            rankOf(c);
        return score(a).compareTo(score(b));
      });
    final title = finished
        ? (v['loser'] == null
              ? 'Ничья!'
              : v['loser'] == v['you']
              ? 'Ещё одну партию?'
              : 'Вы победили!')
        : !s.connected
        ? 'Партия на паузе'
        : v['taking'] == true
        ? (attacking ? 'Соперник берёт' : 'Собираем карты…')
        : attacking
        ? 'Ваш ход'
        : 'Отбивайтесь';
    final hint =
        rejection ??
        (finished
            ? 'Хорошая партия. Сыграем ещё?'
            : !s.connected
            ? 'Дождитесь восстановления связи'
            : draggingTable
            ? (canTakeTable(v)
                  ? 'Опустите карты в свою руку'
                  : 'Поднимите карты к сопернику')
            : draggingCard != null
            ? (attacking
                  ? 'Положите карту на стол'
                  : transfers.contains(draggingCard)
                  ? 'На карту — побить · рядом — перевести'
                  : 'Положите поверх карты, которую бьёте')
            : v['taking'] == true
            ? (attacking
                  ? 'Подкиньте или смахните стол вверх'
                  : 'Ждём завершения розыгрыша')
            : canFinishTable(v)
            ? 'Смахните карты вверх — розыгрыш завершён'
            : attacking
            ? 'Тяните карту из руки на стол'
            : transfers.isNotEmpty
            ? 'На карту — побить · рядом — перевести'
            : 'Тяните свою карту на карту соперника');

    Widget pair(int i) => cardTarget(
      key: Key('defense-zone-$i'),
      zone: CardDropZone.defense,
      target: i,
      child: Semantics(
        label: 'Атака ${cardLabel(table[i]['a'] as int)} · ${table[i]['d']==null?'небита':'побита'}',
        child: SizedBox(
          width: 88,
          height: 116,
          child: Stack(
            children: [
              MotionAnchor(
                id: 'table-${table[i]['a']}',
                child: CardFace(
                  card: table[i]['a'] as int,
                  width: 65,
                  height: 94,
                  suggested: !attacking && table[i]['d'] == null,
                ),
              ),
              if (table[i]['d'] != null)
                Positioned(
                  left: 20,
                  top: 20,
                  child: Transform.rotate(
                    angle: .08,
                    child: MotionAnchor(
                      id: 'table-${table[i]['d']}',
                      child: CardFace(
                        card: table[i]['d'] as int,
                        width: 65,
                        height: 94,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final transferSlot =
        !attacking &&
        v['transferable'] == true &&
        table.isNotEmpty &&
        table.every((p) => p['d'] == null) &&
        v['taking'] != true;
    final cardRow = Wrap(
      spacing: 6,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < table.length; i++) pair(i),
        if (transferSlot)
          cardTarget(
            key: const Key('transfer-zone'),
            zone: CardDropZone.transfer,
            outline: true,
            child: const SizedBox(
              width: 72,
              height: 116,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz_rounded, color: gold, size: 26),
                  SizedBox(height: 6),
                  Text('Рядом', style: TextStyle(color: gold, fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
    final canMoveTable = ready && (canTakeTable(v) || canFinishTable(v));
    final tablePile = Semantics(
      label:
          'Карты на столе. Тяните вниз, чтобы взять, или вверх, чтобы завершить.',
      customSemanticsActions: {
        if (ready && canTakeTable(v))
          const CustomSemanticsAction(label: 'Взять карты'): () =>
              s.action('take'),
        if (ready && canFinishTable(v))
          const CustomSemanticsAction(label: 'Завершить розыгрыш'): () =>
              s.action('finish'),
      },
      child: Draggable<TableDrag>(
        hitTestBehavior: HitTestBehavior.opaque,
        key: const Key('table-pile'),
        data: TableDrag(v['revision'] as int),
        affinity: Axis.vertical,
        maxSimultaneousDrags: canMoveTable ? 1 : 0,
        onDragStarted: () {
          HapticFeedback.selectionClick();
          setState(() => draggingTable = true);
        },
        onDragEnd: (_) {
          if (mounted) setState(() => draggingTable = false);
        },
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 180,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final p in table) ...[
                  CardFace(card: p['a'] as int, width: 42, height: 60),
                  if (p['d'] != null)
                    CardFace(card: p['d'] as int, width: 42, height: 60),
                ],
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .12, child: cardRow),
        child: cardRow,
      ),
    );

    return Column(
      children: [
        pileTarget(
          key: const Key('finish-zone'),
          take: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: gold.withValues(alpha: .13),
                      ),
                      child: Icon(
                        s.offline
                            ? Icons.smart_toy_outlined
                            : Icons.person_outline,
                        color: gold,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.offline
                                ? 'Бот · ${s.botLevel.label}'
                                : 'Соперник',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${v['opponentCount']} карт',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 138,
                      child: Row(
                        children: [
                          Expanded(child: pill('Колода ${v['deckCount']}')),
                          const SizedBox(width: 5),
                          Expanded(
                            child: MotionAnchor(
                              id: 'discard',
                              child: pill('Бито ${v['discardCount']}'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MotionAnchor(
                        id: 'opponent',
                        child: Semantics(
                          label: 'Карты соперника: ${v['opponentCount']}',
                          excludeSemantics: true,
                          child: SizedBox(
                            width: 120,
                            height: 54,
                            child: Stack(
                              children: [
                                for (
                                  var i = 0;
                                  i < math.min(v['opponentCount'] as int, 6);
                                  i++
                                )
                                  Positioned(
                                    left: i * 13.0,
                                    top: (i - 2.5).abs() * 1.5,
                                    child: Transform.rotate(
                                      angle: (i - 2.5) * .06,
                                      child: const CardBack(
                                        width: 35,
                                        height: 48,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Semantics(
                        label: 'Козырь ${suits[suitOf(v['trumpCard'] as int)]}',
                        excludeSemantics: true,
                        child: MotionAnchor(
                          id: 'deck',
                          child: DeckPile(
                            trumpCard: v['trumpCard'] as int,
                            count: v['deckCount'] as int,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canFinishTable(v))
                  Text(
                    v['taking'] == true
                        ? 'Карты вверх — завершить'
                        : 'Карты вверх — бито',
                    style: const TextStyle(color: gold, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
        KeyedSubtree(
          key: const Key('turnLabel'),
          child: AnimatedSwitcher(
            duration: motion(context, 180),
            child: Text(
              title,
              key: ValueKey(title),
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        Text(
          '${v['transferable'] == true ? 'Переводной' : 'Подкидной'} · ${v['deckSize']} карт · ${s.offline ? 'Без интернета' : s.status}',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
        if (!attacking && table.isNotEmpty && !finished)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 164,
                height: 44,
                child: FilledButton.icon(
                  key: const Key('takeButton'),
                  onPressed: ready && canTakeTable(v)
                      ? () => s.action('take')
                      : null,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(v['taking'] == true ? 'Берём…' : 'Взять'),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: cardTarget(
              key: const Key('attack-zone'),
              zone: CardDropZone.attack,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    radius: .9,
                    colors: [Color(0xff255c48), Color(0xff163e33)],
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xff547962)),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: FeltPainter(),
                  child: Center(
                    child: table.isEmpty
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  finished
                                      ? Icons.emoji_events_outlined
                                      : Icons.style_outlined,
                                  color: gold.withValues(alpha: .6),
                                  size: 32,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  finished
                                      ? 'Партия завершена'
                                      : 'Стол свободен',
                                  style: const TextStyle(
                                    color: cream,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  attacking
                                      ? 'Положите сюда карту'
                                      : 'Ожидаем соперника',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: math.min(
                                  290,
                                  MediaQuery.sizeOf(context).width - 64,
                                ),
                                child: tablePile,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
          child: Row(
            children: [
              Text(
                'Ваши карты · ${hand.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'На столе ${table.length}/${v['limit']}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        pileTarget(
          key: const Key('take-zone'),
          take: true,
          child: Column(
            children: [
              SizedBox(
                height: 114,
                child: ListView.separated(
                  key: const Key('hand'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  itemCount: hand.length,
                  separatorBuilder: (c, i) => const SizedBox(width: 7),
                  itemBuilder: (cardContext, i) {
                    final c = hand[i];
                    final face = MotionAnchor(
                      id: 'hand-$c',
                      child: CardFace(
                        card: c,
                        selected: selectedCard == c,
                        suggested:
                            ready &&
                            (legal.contains(c) || transfers.contains(c)),
                      ),
                    );
                    return Semantics(
                      label: cardLabel(c),
                      button: true,
                      child: Draggable<CardDrag>(
                        key: Key('card-$c'),
                        data: CardDrag(c, v['revision'] as int),
                        affinity: Axis.vertical,
                        maxSimultaneousDrags: ready ? 1 : 0,
                        onDragStarted: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            draggingCard = c;
                            selectedCard = c;
                            rejection = null;
                          });
                        },
                        onDragEnd: (d) {
                          if (!mounted) return;
                          setState(() => draggingCard = null);
                          if (!d.wasAccepted) {
                            TableMotion.returnCard(cardContext, c, d.offset);
                            setState(
                              () => rejection =
                                  'Сюда нельзя. Карта вернулась в руку.',
                            );
                            HapticFeedback.selectionClick();
                          }
                        },
                        feedback: Material(
                          color: Colors.transparent,
                          child: CardFace(card: c, selected: true),
                        ),
                        childWhenDragging: Opacity(opacity: .1, child: face),
                        child: GestureDetector(
                          onTap: ready
                              ? () => setState(() => selectedCard = c)
                              : null,
                          child: face,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (ready && canTakeTable(v))
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Карты со стола сюда — беру',
                    style: TextStyle(color: gold, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            hint,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              color: rejection != null ? const Color(0xffe9a7a7) : muted,
              fontSize: 12,
            ),
          ),
        ),
        if (finished)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('newGame'),
                onPressed: () => s.offline
                    ? s.startBot(
                        level: s.botLevel,
                        deckSize: v['deckSize'] as int,
                        transferable: v['transferable'] == true,
                      )
                    : s.reset(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Новая партия'),
              ),
            ),
          ),
        if (!s.connected && !s.offline)
          Padding(
            padding: const EdgeInsets.all(12),
            child: s.isHost
                ? const Text('Оставьте стол открытым. Гость может вернуться.')
                : TextButton(
                    onPressed: s.reconnect,
                    child: const Text('Подключиться снова'),
                  ),
          ),
      ],
    );
  }

  Widget pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(10),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, style: const TextStyle(color: muted, fontSize: 11)),
    ),
  );
}
