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
import 'package:budget/struct/householdSpendingRules.dart';
import 'package:drift/drift.dart';

export 'package:budget/struct/householdSpendingRules.dart';

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
