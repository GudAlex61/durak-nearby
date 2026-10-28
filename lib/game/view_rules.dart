import 'engine.dart';

/// Uses only the player's public projection, never the opponent's hidden hand.
Set<int> legalCards(Map<String, dynamic> v, {int? target}) {
  if (v['finished'] == true) return {};
  final hand = List<int>.from(v['hand'] as List);
  final table = (v['table'] as List).cast<Map>();
  if (v['you'] == v['attacker']) {
    if (table.length >= (v['limit'] as int)) return {};
    final ranks = {
      for (final p in table) ...[
        rankOf(p['a'] as int),
        if (p['d'] != null) rankOf(p['d'] as int),
      ],
    };
    return hand
        .where((c) => table.isEmpty || ranks.contains(rankOf(c)))
        .toSet();
  }
  if (v['taking'] == true) return {};
  final i = target ?? table.indexWhere((p) => p['d'] == null);
  if (i < 0 || i >= table.length || table[i]['d'] != null) return {};
  return hand
      .where(
        (c) => beats(c, table[i]['a'] as int, suitOf(v['trumpCard'] as int)),
      )
      .toSet();
}

Set<int> transferCards(Map<String, dynamic> v) {
  if (v['transferable'] != true ||
      v['finished'] == true ||
      v['taking'] == true ||
      v['you'] == v['attacker']) {
    return {};
  }
  final table = (v['table'] as List).cast<Map>();
  if (table.isEmpty ||
      table.any((p) => p['d'] != null) ||
      table.length + 1 > 6 ||
      table.length + 1 > (v['opponentCount'] as int)) {
    return {};
  }
  return List<int>.from(v['hand'] as List)
      .where((c) => table.every((p) => rankOf(p['a'] as int) == rankOf(c)))
      .toSet();
}
