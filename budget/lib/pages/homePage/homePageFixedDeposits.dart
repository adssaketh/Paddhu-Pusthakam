// Fixed deposits on the Home page, under the accounts: one line per bank and a total. Tap to open the
// Fixed deposits page (add, check, mark matured).

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/fixedDepositsPage.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePageFixedDeposits extends StatelessWidget {
  const HomePageFixedDeposits({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double v) => convertToMoney(allWallets, v);
    final DateTime today = DateTime.now();
    final List<FixedDeposit> open = loadFixedDeposits().where((e) => !e.closed).toList();

    final Map<String, double> byBank = {};
    final Map<String, int> countByBank = {};
    double total = 0;
    FixedDeposit? next;
    for (final FixedDeposit fd in open) {
      final double v = currentValue(fd, today);
      total += v;
      byBank[fd.bank] = (byBank[fd.bank] ?? 0) + v;
      countByBank[fd.bank] = (countByBank[fd.bank] ?? 0) + 1;
      if (next == null || fd.maturityDate.isBefore(next.maturityDate)) next = fd;
    }

    Widget row(IconData icon, String title, String? sub, String? trailing, {bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          child: Row(children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
                if (sub != null) Text(sub, style: const TextStyle(fontSize: 12)),
              ]),
            ),
            if (trailing != null)
              Text(trailing, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
        );

    return InkWell(
      onTap: () => pushRoute(context, const FixedDepositsPage()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (open.isEmpty)
            row(Icons.savings_outlined, 'Fixed deposits', 'Tap to add one', null)
          else ...[
            row(Icons.savings_outlined, 'Fixed deposits',
                next == null
                    ? null
                    : 'Next maturity ${next.maturityDate.day}/${next.maturityDate.month}/${next.maturityDate.year} (${daysToMaturity(next, today)} days)',
                money(total),
                bold: true),
            for (final MapEntry<String, double> e in byBank.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 34),
                child: row(Icons.subdirectory_arrow_right, e.key,
                    '${countByBank[e.key]} deposit${countByBank[e.key] == 1 ? '' : 's'}', money(e.value)),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
