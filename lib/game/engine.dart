import 'dart:math';

/// A card is an integer 0..35: suit * 9 + rank (6..A).
int rankOf(int card) => card % 9;
int suitOf(int card) => card ~/ 9;
const ranks = ['6', '7', '8', '9', '10', 'В', 'Д', 'К', 'Т'];
const suits = ['♣', '♦', '♥', '♠'];
String cardLabel(int card) => '${ranks[rankOf(card)]}${suits[suitOf(card)]}';
bool beats(int defense, int attack, int trump) =>
    (suitOf(defense) == suitOf(attack) && rankOf(defense) > rankOf(attack)) ||
    (suitOf(defense) == trump && suitOf(attack) != trump);

class RuleError implements Exception {
  final String message;
  RuleError(this.message);
  @override
  String toString() => message;
}

class TablePair {
  final int attack;
  int? defense;
  TablePair(this.attack, [this.defense]);
  Map<String, dynamic> toJson() => {'a': attack, 'd': defense};
}

/// Authoritative two-player throw-in Durak. Never send this object to a client.
class DurakGame {
  final List<int> deck;
  final List<List<int>> hands;
  final List<TablePair> table;
  final List<int> discarded;
  final int trumpCard;
  final int deckSize;
  final bool transferable;
  int attacker;
  int limit;
  bool taking = false;
  int revision = 0;
  bool finished = false;
  int? loser; // null with finished == true means a draw
  int get defender => 1 - attacker;
  int get trump => suitOf(trumpCard);
  bool get covered => table.isNotEmpty && table.every((p) => p.defense != null);

  DurakGame._(
    this.deck,
    this.hands,
    this.table,
    this.discarded,
    this.trumpCard,
    this.attacker,
    this.limit, {
    this.deckSize = 36,
    this.transferable = false,
  });

  factory DurakGame({
    Random? random,
    int deckSize = 36,
    bool transferable = false,
  }) {
    if (deckSize != 24 && deckSize != 36) {
      throw ArgumentError.value(deckSize, "deckSize", "24 or 36");
    }
    final rng = random ?? Random.secure();
    final cards = [
      for (var i = 0; i < 36; i++)
        if (deckSize == 36 || rankOf(i) >= 3) i,
    ]..shuffle(rng);
    // The bottom card is visible and must be drawn last.
    final trumpCard = cards.first;
    final hands = [<int>[], <int>[]];
    for (var i = 0; i < 6; i++) {
      hands[0].add(cards.removeLast());
      hands[1].add(cards.removeLast());
    }
    var attacker = rng.nextInt(2);
    var lowest = 10;
    for (var p = 0; p < 2; p++) {
      for (final c in hands[p]) {
        if (suitOf(c) == suitOf(trumpCard) && rankOf(c) < lowest) {
          lowest = rankOf(c);
          attacker = p;
        }
      }
    }
    return DurakGame._(
      cards,
      hands,
      [],
      [],
      trumpCard,
      attacker,
      6,
      deckSize: deckSize,
      transferable: transferable,
    );
  }

  /// Explicit fixture constructor for rule tests, not used by the application.
  factory DurakGame.fixture({
    required List<int> deck,
    required List<List<int>> hands,
    required int trumpCard,
    int attacker = 0,
    int deckSize = 36,
    bool transferable = false,
  }) => DurakGame._(
    List.of(deck),
    hands.map((h) => List<int>.of(h)).toList(),
    [],
    [],
    trumpCard,
    attacker,
    min(6, hands[1 - attacker].length),
    deckSize: deckSize,
    transferable: transferable,
  );

  bool canTransfer(int player, int card) =>
      transferable &&
      !finished &&
      player == defender &&
      !taking &&
      hands[player].contains(card) &&
      table.isNotEmpty &&
      table.every(
        (p) => p.defense == null && rankOf(p.attack) == rankOf(card),
      ) &&
      table.length + 1 <= min(6, hands[attacker].length);

  void apply(int player, String action, {int? card, int? target}) {
    if (finished) throw RuleError('Партия завершена');
    if (player != 0 && player != 1) throw RuleError('Неизвестный игрок');
    switch (action) {
      case 'attack':
        if (player != attacker) {
          throw RuleError('Сейчас вы отбиваетесь');
        }
        if (card == null || !hands[player].contains(card)) {
          throw RuleError('У вас нет этой карты');
        }
        if (table.length >= limit) {
          throw RuleError('Достигнут лимит подкидывания');
        }
        if (table.isNotEmpty &&
            !table.any(
              (p) =>
                  rankOf(p.attack) == rankOf(card) ||
                  (p.defense != null && rankOf(p.defense!) == rankOf(card)),
            )) {
          throw RuleError('Подкинуть можно только достоинство со стола');
        }
        hands[player].remove(card);
        table.add(TablePair(card));
        break;
      case 'transfer':
        if (card == null || !canTransfer(player, card)) {
          throw RuleError(
            'Перевести можно до защиты, картой того же достоинства, если у соперника хватает карт',
          );
        }
        hands[player].remove(card);
        table.add(TablePair(card));
        attacker = player;
        limit = min(6, hands[defender].length);
        break;
      case 'defend':
        if (player != defender || taking) {
          throw RuleError('Сейчас нельзя отбиваться');
        }
        if (target == null ||
            target < 0 ||
            target >= table.length ||
            table[target].defense != null) {
          throw RuleError('Выберите небитую карту');
        }
        if (card == null || !hands[player].contains(card)) {
          throw RuleError('У вас нет этой карты');
        }
        if (!beats(card, table[target].attack, trump)) {
          throw RuleError('Эта карта не бьёт выбранную');
        }
        hands[player].remove(card);
        table[target].defense = card;
        break;
      case 'take':
        if (player != defender || table.isEmpty || taking) {
          throw RuleError('Сейчас нельзя взять');
        }
        taking = true;
        break;
      case 'finish':
        if (player != attacker || table.isEmpty || (!taking && !covered)) {
          throw RuleError('Сначала соперник должен отбиться или взять');
        }
        final oldAttacker = attacker;
        final oldDefender = defender;
        final cards = table.expand(
          (p) => [p.attack, if (p.defense != null) p.defense!],
        );
        if (taking) {
          hands[oldDefender].addAll(cards);
        } else {
          discarded.addAll(cards);
        }
        for (final p in [oldAttacker, oldDefender]) {
          while (hands[p].length < 6 && deck.isNotEmpty) {
            hands[p].add(deck.removeLast());
          }
        }
        if (!taking) attacker = oldDefender;
        table.clear();
        taking = false;
        limit = min(6, hands[defender].length);
        if (deck.isEmpty && hands.any((h) => h.isEmpty)) {
          finished = true;
          if (hands[0].isEmpty != hands[1].isEmpty) {
            loser = hands[0].isEmpty ? 1 : 0;
          }
        }
        break;
      default:
        throw RuleError('Неизвестное действие');
    }
    revision++;
  }

  /// A recipient-specific projection. Opponent cards and deck order stay private.
  Map<String, dynamic> view(int player) => {
    'revision': revision,
    'deckSize': deckSize,
    'transferable': transferable,
    'you': player,
    'hand': List<int>.of(hands[player]),
    'opponentCount': hands[1 - player].length,
    'deckCount': deck.length,
    'trumpCard': trumpCard,
    'attacker': attacker,
    'limit': limit,
    'taking': taking,
    'table': table.map((p) => p.toJson()).toList(),
    'finished': finished,
    'loser': loser,
    'discardCount': discarded.length,
  };
}

enum BotLevel {
  easy('Лёгкий', 'Для знакомства с правилами'),
  normal('Обычный', 'Бережёт козыри и играет младшими'),
  hard('Сложный', 'Планирует защиту и выбирает подкидывание');

  final String label, description;
  const BotLevel(this.label, this.description);
}

/// All levels use their own cards and public table information only.
Map<String, dynamic>? botMove(
  DurakGame game,
  int player, {
  BotLevel level = BotLevel.normal,
  Random? random,
}) {
  if (game.finished) return null;
  final cards = List<int>.of(game.hands[player])
    ..sort((a, b) {
      final av = rankOf(a) + (suitOf(a) == game.trump ? 20 : 0);
      final bv = rankOf(b) + (suitOf(b) == game.trump ? 20 : 0);
      return av.compareTo(bv);
    });
  if (cards.isEmpty && game.table.isEmpty) return null;
  if (level == BotLevel.easy) cards.shuffle(random ?? Random());
  if (level == BotLevel.hard && game.table.isEmpty) {
    final counts = <int, int>{};
    for (final c in cards) {
      counts[rankOf(c)] = (counts[rankOf(c)] ?? 0) + 1;
    }
    int score(int c) =>
        rankOf(c) +
        (suitOf(c) == game.trump ? 24 : 0) -
        (counts[rankOf(c)]! - 1) * 3;
    cards.sort((a, b) => score(a).compareTo(score(b)));
  }
  if (player == game.attacker) {
    if (game.table.isEmpty) return {'action': 'attack', 'card': cards.first};
    if (!game.taking && !game.covered) return null;
    if (game.table.length < game.limit) {
      for (final c in cards) {
        if (game.table.any(
          (p) =>
              rankOf(p.attack) == rankOf(c) ||
              (p.defense != null && rankOf(p.defense!) == rankOf(c)),
        )) {
          if (level == BotLevel.hard &&
              game.taking &&
              game.deck.isNotEmpty &&
              suitOf(c) == game.trump &&
              rankOf(c) >= 5) {
            continue;
          }
          return {'action': 'attack', 'card': c};
        }
      }
    }
    return {'action': 'finish'};
  }
  if (game.taking) return null;
  for (final c in cards) {
    if (game.canTransfer(player, c)) return {'action': 'transfer', 'card': c};
  }
  var target = game.table.indexWhere((p) => p.defense == null);
  if (level == BotLevel.hard && target >= 0) {
    // Resolve the most constrained attack first, preserving flexible trumps.
    final uncovered = [
      for (var i = 0; i < game.table.length; i++)
        if (game.table[i].defense == null) i,
    ];
    uncovered.sort(
      (a, b) => cards
          .where((c) => beats(c, game.table[a].attack, game.trump))
          .length
          .compareTo(
            cards
                .where((c) => beats(c, game.table[b].attack, game.trump))
                .length,
          ),
    );
    target = uncovered.first;
  }
  if (target < 0) return null;
  for (final c in cards) {
    if (beats(c, game.table[target].attack, game.trump)) {
      return {'action': 'defend', 'card': c, 'target': target};
    }
  }
  return {'action': 'take'};
}
