// Fixed deposits on the Home page, under the accounts: one row with what they are worth in total. Tap it to
// see every deposit (bank, number, rate, days left, interest so far); tap a deposit to open it, or the link
// at the bottom for the full Fixed deposits page.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/fixedDepositsPage.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
import 'package:budget/widgets/financeCollapsible.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePageFixedDeposits extends StatelessWidget {
  const HomePageFixedDeposits({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    String money(double v) => convertToMoney(allWallets, v);
    final DateTime today = DateTime.now();
    final List<FixedDeposit> open = loadFixedDeposits().where((e) => !e.closed).toList()
      ..sort((a, b) => a.maturityDate.compareTo(b.maturityDate));

    if (open.isEmpty) {
      return InkWell(
        onTap: () => pushRoute(context, const FixedDepositFormPage()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(children: [
            Icon(Icons.add_circle_outline, color: cs.primary),
            const SizedBox(width: 12),
            const Text('Add a fixed deposit', style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }

    double total = 0;
    for (final FixedDeposit fd in open) {
      total += currentValue(fd, today);
    }

    Widget line(FixedDeposit fd) {
      final int days = daysToMaturity(fd, today);
      final int span = fd.maturityDate.difference(fd.startDate).inDays;
      final double progress =
          span <= 0 ? 1 : (today.difference(fd.startDate).inDays / span).clamp(0.0, 1.0).toDouble();
      final String last4 = fd.fdNumber.isEmpty
          ? ''
          : '  ••${fd.fdNumber.length > 4 ? fd.fdNumber.substring(fd.fdNumber.length - 4) : fd.fdNumber}';
      return InkWell(
        onTap: () => pushRoute(context, FixedDepositFormPage(deposit: fd)),
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
                FinAvatar(fd.bank, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${fd.bank}$last4',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                Text(money(currentValue(fd, today)),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              FinProgress(progress, height: 6, color: finColorFor(fd.bank)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: FinStat('Deposited', money(fd.principal))),
                Expanded(child: FinStat('Interest so far', money(accruedInterest(fd, today)))),
                Expanded(child: FinStat('At maturity', money(maturityValue(fd)))),
              ]),
              const SizedBox(height: 8),
              Text(
                  '${fd.ratePct}% · ${days > 0 ? 'matures ${fd.maturityDate.day}/${fd.maturityDate.month}/${fd.maturityDate.year} ($days day${days == 1 ? '' : 's'})' : 'matured, check it'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            ]),
          ),
        ),
      );
    }

    return FinCollapsible(
      settingKey: "homeFdsExpanded",
      icon: Icons.savings_outlined,
      title: 'Fixed deposits',
      subtitle: '${open.length} deposit${open.length == 1 ? '' : 's'} · worth today',
      total: money(total),
      details: Column(mainAxisSize: MainAxisSize.min, children: [for (final FixedDeposit fd in open) line(fd)]),
      footer: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextButton(
          onPressed: () => pushRoute(context, const FixedDepositsPage()),
          child: const Text('Open the fixed deposits page'),
        ),
      ),
    );
  }
}
