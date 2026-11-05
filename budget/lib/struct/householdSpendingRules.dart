// Pure grouping of household spending per member.
// No imports on purpose, so tests can run this file with plain `dart run`.

class HouseholdMemberSpending {
  const HouseholdMemberSpending({
    required this.uid,
    required this.total,
    required this.count,
  });

  final String uid;
  final double total; // positive, in the main currency
  final int count;
}

/// Adds up [amounts] (already in the main currency) per owner. A null owner is [myUid]'s.
/// Pure, so it can be checked with `dart run`. Biggest spender first.
List<HouseholdMemberSpending> groupSpendingByOwner(
  List<({String? ownerUid, double amount})> rows, {
  required String myUid,
}) {
  final Map<String, double> totals = {};
  final Map<String, int> counts = {};
  for (final row in rows) {
    final String uid = row.ownerUid ?? myUid;
    if (uid == "") continue;
    totals[uid] = (totals[uid] ?? 0) + row.amount.abs();
    counts[uid] = (counts[uid] ?? 0) + 1;
  }
  final List<HouseholdMemberSpending> out = [
    for (final String uid in totals.keys)
      HouseholdMemberSpending(
          uid: uid, total: totals[uid]!, count: counts[uid] ?? 0),
  ];
  out.sort((a, b) => b.total.compareTo(a.total));
  return out;
}
