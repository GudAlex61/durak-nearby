import 'view_rules.dart';

enum CardDropZone { attack, defense, transfer }

class CardDrag {
  final int card, revision;
  const CardDrag(this.card, this.revision);
}

class TableDrag {
  final int revision;
  const TableDrag(this.revision);
}

class CardMove {
  final String action;
  final int card;
  final int? target;
  const CardMove(this.action, this.card, [this.target]);
}

/// Drops use the current public projection and reject a stale drag payload.
CardMove? resolveDrop(
  Map<String, dynamic> view,
  CardDrag drag,
  CardDropZone zone, {
  int? target,
}) {
  if (view['finished'] == true || drag.revision != view['revision']) {
    return null;
  }
  final attacking = view['you'] == view['attacker'];
  switch (zone) {
    case CardDropZone.attack:
      return attacking && legalCards(view).contains(drag.card)
          ? CardMove('attack', drag.card)
          : null;
    case CardDropZone.defense:
      return !attacking &&
              target != null &&
              legalCards(view, target: target).contains(drag.card)
          ? CardMove('defend', drag.card, target)
          : null;
    case CardDropZone.transfer:
      return transferCards(view).contains(drag.card)
          ? CardMove('transfer', drag.card)
          : null;
  }
}

bool canTakeTable(Map<String, dynamic> v) =>
    v['finished'] != true &&
    v['you'] != v['attacker'] &&
    v['taking'] != true &&
    (v['table'] as List).isNotEmpty;
bool canFinishTable(Map<String, dynamic> v) =>
    v['finished'] != true &&
    v['you'] == v['attacker'] &&
    (v['table'] as List).isNotEmpty &&
    (v['taking'] == true || (v['table'] as List).every((p) => p['d'] != null));
