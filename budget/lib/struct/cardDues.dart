// What you owe on each credit card, worked out from the bank SMS:
//   "... spent using ICICI Bank Card XX1000 ..."            -> you owe more
//   "Payment of Rs ... has been received on your ... Card"  -> you owe less
//   a refund on the card                                    -> you owe less
// The payment message is not saved as a transaction (the money leaving your bank account is its own SMS), so
// these entries are kept on the side and only used to show "you owe".
//
// Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

class CardDueEntry {
  const CardDueEntry({
    required this.id,
    required this.card,
    required this.kind,
    required this.amount,
    required this.date,
    this.note = '',
  });

  /// Same SMS (or the same hand-made entry) always has the same id, so it is only counted once.
  final String id;

  /// Your name for the card, for example "Saketh - ICICI Amazon Pay Credit Card".
  final String card;

  /// 'spend', 'payment', 'refund' or 'opening' (a correction you make by hand; may be negative).
  final String kind;
  final double amount;
  final DateTime date;
  final String note;

  /// What this entry adds to the amount owed (negative when it reduces it).
  double get effect {
    switch (kind) {
      case 'spend':
        return amount;
      case 'opening':
        return amount;
      default:
        return -amount;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'card': card,
        'kind': kind,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      };

  static CardDueEntry? fromJson(dynamic j) {
    if (j is! Map || j['_d'] == true) return null;
    final DateTime? date = DateTime.tryParse('${j['date']}');
    final double? amount = j['amount'] is num ? (j['amount'] as num).toDouble() : double.tryParse('${j['amount']}');
    if (date == null || amount == null || j['id'] == null || '${j['card']}'.isEmpty) return null;
    return CardDueEntry(
      id: '${j['id']}',
      card: '${j['card']}',
      kind: '${j['kind']}',
      amount: amount,
      date: date,
      note: '${j['note'] ?? ''}',
    );
  }
}

/// Owed amount per card (can be below zero when you paid more than you spent: shown as a credit).
Map<String, double> owedByCard(Iterable<CardDueEntry> entries) {
  final Map<String, double> out = {};
  for (final CardDueEntry e in entries) {
    out[e.card] = (out[e.card] ?? 0) + e.effect;
  }
  return out;
}

/// The entry that makes [card] show [target] as owed, given what the other entries add up to.
CardDueEntry correctionFor(String card, double currentOwed, double target, DateTime now) {
  return CardDueEntry(
    id: 'cd-open-${now.microsecondsSinceEpoch}',
    card: card,
    kind: 'opening',
    amount: double.parse((target - currentOwed).toStringAsFixed(2)),
    date: now,
    note: 'Set to ${target.toStringAsFixed(2)}',
  );
}
