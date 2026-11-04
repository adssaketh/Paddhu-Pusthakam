// Credit cards on the Home page, under the accounts: one row with what you owe in total. Tap it to see what
// is owed on each card; tap a card for its spends and payments.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/cardDuesPage.dart';
import 'package:budget/struct/cardDues.dart';
import 'package:budget/struct/cardDuesStore.dart';
import 'package:budget/widgets/financeCollapsible.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePageCardDues extends StatelessWidget {
  const HomePageCardDues({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<CardDueEntry> entries = loadCardDues();
    if (entries.isEmpty) return const SizedBox.shrink();
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Map<String, double> owed = owedByCard(entries);
    final double total = owed.values.fold(0.0, (a, b) => a + (b > 0 ? b : 0));
    final List<MapEntry<String, double>> cards = owed.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return FinCollapsible(
      settingKey: 'homeCardDuesExpanded',
      icon: Icons.credit_card_outlined,
      title: 'Credit cards',
      subtitle: total <= 0 ? 'nothing owed' : 'you owe',
      total: convertToMoney(allWallets, total),
      details: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry<String, double> c in cards)
            InkWell(
              onTap: () => pushRoute(context, CardDuePage(card: c.key)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(c.key,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    c.value < -0.005 ? '${convertToMoney(allWallets, -c.value)} credit' : convertToMoney(allWallets, c.value),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: c.value > 0.005 ? cs.error : cs.onSurface.withOpacity(0.7)),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
