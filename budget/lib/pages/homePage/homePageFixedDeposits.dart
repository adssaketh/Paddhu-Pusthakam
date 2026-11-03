// Fixed deposits on the Home page, under the accounts: one line per deposit (bank, number, what it is worth
// today, days to maturity and a thin bar of the time gone). The heading opens the Fixed deposits page.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/fixedDepositsPage.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Column(children: [
            Row(children: [
              FinAvatar(fd.bank, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${fd.bank}$last4',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                      days > 0
                          ? '${fd.ratePct}% · matures in $days day${days == 1 ? '' : 's'}'
                          : '${fd.ratePct}% · matured, check it',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(currentValue(fd, today)),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text('of ${money(maturityValue(fd))}',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(0.55))),
              ]),
            ]),
            const SizedBox(height: 8),
            FinProgress(progress, height: 5, color: finColorFor(fd.bank)),
          ]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => pushRoute(context, const FixedDepositsPage()),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
            child: Row(children: [
              Expanded(
                child: Text('FIXED DEPOSITS',
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(0.5))),
              ),
              if (open.isNotEmpty)
                Text(money(total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withOpacity(0.5)),
            ]),
          ),
        ),
        if (open.isEmpty)
          InkWell(
            onTap: () => pushRoute(context, const FixedDepositFormPage()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(children: [
                Icon(Icons.add_circle_outline, color: cs.primary),
                const SizedBox(width: 12),
                const Text('Add a fixed deposit', style: TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          )
        else
          for (final FixedDeposit fd in open) line(fd),
        const SizedBox(height: 6),
      ],
    );
  }
}
