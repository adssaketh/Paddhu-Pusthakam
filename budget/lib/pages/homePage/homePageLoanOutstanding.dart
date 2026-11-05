// Loans on the Home page, under the accounts: one row with what is left to pay in total (interest and GST
// included). Tap it to see every loan with its EMI, next date and repaid bar; tap a loan to open it.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/loanTermsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/householdSharedCopies.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/loanTerms.dart';
import 'package:budget/widgets/financeCollapsible.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:budget/widgets/householdSharePicker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePageLoanOutstanding extends StatelessWidget {
  const HomePageLoanOutstanding({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (loanPksWithTerms().isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<Objective>>(
      future: database.getAllObjectives(
          objectiveType: ObjectiveType.loan, isArchived: false),
      builder: (context, snapshot) {
        final List<Objective> loans = (snapshot.data ?? [])
            .where((o) => loanTermsFor(o.objectivePk) != null)
            .toList();
        if (loans.isEmpty) return const SizedBox.shrink();
        final AllWallets allWallets = Provider.of<AllWallets>(context);
        return _sum(context, allWallets, loans, 0, 0, (double total) {
          return FinCollapsible(
            settingKey: "homeLoansExpanded",
            icon: Icons.account_balance_outlined,
            title: 'Loans',
            subtitle: '${loans.length} loan${loans.length == 1 ? '' : 's'} · left to pay',
            total: convertToMoney(allWallets, total),
            details: Column(
              mainAxisSize: MainAxisSize.min,
              children: [for (final Objective loan in loans) _LoanLine(loan: loan)],
            ),
          );
        });
      },
    );
  }

  /// Adds up what is left on every loan; each one is watched so the total follows new payments.
  Widget _sum(BuildContext context, AllWallets allWallets, List<Objective> loans, int i,
      double acc, Widget Function(double) done) {
    if (i >= loans.length) return done(acc);
    final LoanTerms? terms = loanTermsFor(loans[i].objectivePk);
    if (terms == null) return _sum(context, allWallets, loans, i + 1, acc, done);
    return StreamBuilder<double?>(
      stream: database.watchTotalTowardsObjective(allWallets, loans[i]),
      builder: (context, snapshot) {
        final double left = loanProgress(terms, snapshot.data ?? 0).outstanding;
        return _sum(context, allWallets, loans, i + 1, acc + left, done);
      },
    );
  }
}

String _day(DateTime d) {
  const List<String> m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}';
}

class _LoanLine extends StatelessWidget {
  const _LoanLine({required this.loan});
  final Objective loan;

  @override
  Widget build(BuildContext context) {
    final LoanTerms? terms = loanTermsFor(loan.objectivePk);
    if (terms == null) return const SizedBox.shrink();
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    LoanInstalment? next;
    for (final LoanInstalment i in buildSchedule(terms)) {
      if (!terms.paidInstalments.contains(i.number)) {
        next = i;
        break;
      }
    }
    return StreamBuilder<double?>(
      stream: database.watchTotalTowardsObjective(allWallets, loan),
      builder: (context, snapshot) {
        final LoanProgress p = loanProgress(terms, snapshot.data ?? 0);
        return InkWell(
          onTap: () => pushRoute(context, LoanTermsPage(objective: loan)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(loan.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                  Text(convertToMoney(allWallets, p.outstanding),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                FinProgress(p.fraction, height: 6, color: finColorFor(loan.name)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: FinStat('Paid', convertToMoney(allWallets, p.repaid))),
                  Expanded(child: FinStat('Total', convertToMoney(allWallets, p.totalPayable))),
                  Expanded(
                      child: FinStat('EMI', convertToMoney(allWallets, terms.emi))),
                ]),
                const SizedBox(height: 8),
                Text(
                    '${terms.annualRatePct}% a year · ${(p.fraction * 100).round()}% repaid'
                    '${next == null ? '' : ' · next EMI ${_day(next.dueDate)}'}',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                // Who this person shared the loan with (nothing for a private loan).
                HouseholdSharedBadge(
                    kind: kSharedKindLoan,
                    localId: loan.objectivePk,
                    padding: const EdgeInsets.only(top: 4)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
