// Who spent how much: the household's shared spending in a period, split by the member who
// added each transaction.
//
// Counted: paid expenses that are shared with the household (not private, not kept personal),
// without balance corrections and loans. Amounts are converted to the main currency.
// The Everyone / Mine switch does not matter here: this is always the household as a whole.

import 'package:budget/database/tables.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/householdService.dart';
import 'package:drift/drift.dart';

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

/// Spending per member from [start] (included) up to [end] (not included).
Future<List<HouseholdMemberSpending>> getHouseholdSpendingByMember(
  AllWallets allWallets,
  DateTime start,
  DateTime end,
) async {
  final List<Transaction> transactions =
      await (database.select(database.transactions)
            ..where((t) =>
                t.paid.equals(true) &
                t.income.equals(false) &
                t.categoryFk.equals("0").not() &
                t.objectiveLoanFk.isNull() &
                (t.type.isNull() |
                    t.type.isNotInValues([
                      TransactionSpecialType.credit,
                      TransactionSpecialType.debt,
                    ])) &
                t.isPrivate.equals(false) &
                (t.ownerUid.isNull() | t.ownerUid.equals("").not()) &
                t.dateCreated.isBiggerOrEqualValue(start) &
                t.dateCreated.isSmallerThanValue(end)))
          .get();

  final List<({String? ownerUid, double amount})> rows = [
    for (final Transaction transaction in transactions)
      (
        ownerUid: transaction.ownerUid,
        amount: transaction.amount.abs() *
            amountRatioToPrimaryCurrency(
              allWallets,
              allWallets.indexedByPk[transaction.walletFk]?.currency,
            ),
      ),
  ];
  return groupSpendingByOwner(rows, myUid: currentHouseholdUserUid);
}
