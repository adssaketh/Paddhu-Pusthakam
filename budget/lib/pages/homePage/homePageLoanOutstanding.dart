// "Loans outstanding" lines under the accounts on the Home page, for loans that have terms
// (interest + GST), see loanTermsPage.dart.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/loanTermsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/loanTerms.dart';
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
            for (final Objective loan in loans) _LoanLine(loan: loan),
            const SizedBox(height: 8),
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
    return StreamBuilder<double?>(
      stream: database.watchTotalTowardsObjective(allWallets, loan),
      builder: (context, snapshot) {
        final LoanProgress p = loanProgress(terms, snapshot.data ?? 0);
        return InkWell(
          onTap: () => pushRoute(context, LoanTermsPage(objective: loan)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.account_balance_outlined, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const Text('Loan outstanding',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                Text(convertToMoney(allWallets, p.outstanding),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }
}
