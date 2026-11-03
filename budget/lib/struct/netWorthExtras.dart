// Optional extras for the Net worth box on Home: take off what you still owe on loans (outstanding with
// interest and GST) and add the current value of fixed deposits. Both are off until you switch them on
// (long-press the Net worth box). Only applied when the net worth period is "all time", because loans and
// deposits are a position today, not a period's spending.

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/loanTerms.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/periodCyclePicker.dart';

/// What to add to the net worth: + fixed deposits' value today, - loans' outstanding.
Future<double> netWorthAdjustment(AllWallets allWallets) async {
  final bool loans = appStateSettings["netWorthIncludeLoans"] == true;
  final bool fds = appStateSettings["netWorthIncludeFds"] == true;
  if (!loans && !fds) return 0;
  if (appStateSettings["selectedPeriodCycleTypeNetWorth"] != CycleType.allTime.index) {
    return 0;
  }
  double adjustment = 0;
  try {
    if (fds) {
      final DateTime today = DateTime.now();
      for (final FixedDeposit fd in loadFixedDeposits()) {
        if (!fd.closed) adjustment += currentValue(fd, today);
      }
    }
    if (loans) {
      final List<Objective> all = await database.getAllObjectives(
          objectiveType: ObjectiveType.loan, isArchived: false);
      for (final Objective loan in all) {
        final LoanTerms? terms = loanTermsFor(loan.objectivePk);
        if (terms == null) continue;
        final double linked = await database.getTotalTowardsObjective(
                allWallets, loan.objectivePk, ObjectiveType.loan) ??
            0;
        adjustment -= loanProgress(terms, linked).outstanding;
      }
    }
  } catch (_) {
    // never break the Home page over this
  }
  return adjustment;
}
