// Loans on the Home page, under the accounts: one line per loan with what is left to pay (interest and GST
// included) and a thin bar of how much is repaid. Tap to open the loan.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/loanTermsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/loanTerms.dart';
import 'package:budget/widgets/financeUi.dart';
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(children: [
                Text('LOANS',
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
              ]),
            ),
            for (final Objective loan in loans) _LoanLine(loan: loan),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }
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
    return StreamBuilder<double?>(
      stream: database.watchTotalTowardsObjective(allWallets, loan),
      builder: (context, snapshot) {
        final LoanProgress p = loanProgress(terms, snapshot.data ?? 0);
        final Color accent = finColorFor(loan.name);
        return InkWell(
          onTap: () => pushRoute(context, LoanTermsPage(objective: loan)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(children: [
              Row(children: [
                FinAvatar(loan.name, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(loan.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('${(p.fraction * 100).round()}% repaid',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(convertToMoney(allWallets, p.outstanding),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  Text('left to pay',
                      style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(0.55))),
                ]),
              ]),
              const SizedBox(height: 8),
              FinProgress(p.fraction, height: 5, color: accent),
            ]),
          ),
        );
      },
    );
  }
}
