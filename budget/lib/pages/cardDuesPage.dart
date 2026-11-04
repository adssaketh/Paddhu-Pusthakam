// What you owe on one credit card: the amount, every spend and payment that made it, and two buttons for
// what the SMS cannot know (a payment made some other way, or the amount owed from before Paddhu started
// counting).

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/cardDues.dart';
import 'package:budget/struct/cardDuesStore.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

Future<double?> _askAmount(BuildContext context, String title, {String hint = 'Amount'}) async {
  final TextEditingController c = TextEditingController();
  final String? text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: hint, prefixText: '₹ '),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
      ],
    ),
  );
  if (text == null) return null;
  return double.tryParse(text.replaceAll(',', '').trim());
}

class CardDuePage extends StatefulWidget {
  const CardDuePage({required this.card, Key? key}) : super(key: key);
  final String card;

  @override
  State<CardDuePage> createState() => _CardDuePageState();
}

class _CardDuePageState extends State<CardDuePage> {
  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    String money(double v) => convertToMoney(allWallets, v);
    final List<CardDueEntry> entries = loadCardDues().where((e) => e.card == widget.card).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final double owed = owedByCard(entries)[widget.card] ?? 0;
    double spent = 0, paid = 0;
    for (final CardDueEntry e in entries) {
      if (e.kind == 'spend') spent += e.amount;
      if (e.kind == 'payment' || e.kind == 'refund') paid += e.amount;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.card, style: const TextStyle(fontSize: 16)), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            FinHero(
              icon: Icons.credit_card_outlined,
              label: owed < -0.005 ? 'Paid in advance' : 'You owe',
              amount: money(owed < 0 ? -owed : owed),
              caption: widget.card,
              pills: [
                FinPill('Spent ${money(spent)}', icon: Icons.north_east, onHero: true),
                FinPill('Paid / refunded ${money(paid)}', icon: Icons.south_west, onHero: true),
              ],
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('I paid'),
                  onPressed: () async {
                    final double? v = await _askAmount(context, 'Payment made');
                    if (v == null || v <= 0) return;
                    final DateTime now = DateTime.now();
                    await addCardDue(CardDueEntry(
                        id: 'cd-hand-${now.microsecondsSinceEpoch}',
                        card: widget.card,
                        kind: 'payment',
                        amount: v,
                        date: now,
                        note: 'Added by hand'));
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Set amount owed'),
                  onPressed: () async {
                    final double? v = await _askAmount(context, 'What do you owe on this card right now?');
                    if (v == null) return;
                    await setCardOwed(widget.card, v);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            FinSectionTitle('Spends and payments (${entries.length})'),
            for (final CardDueEntry e in entries)
              FinCard(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(children: [
                  Icon(
                      e.kind == 'spend'
                          ? Icons.north_east
                          : (e.kind == 'opening' ? Icons.tune : Icons.south_west),
                      size: 18,
                      color: e.kind == 'spend' ? cs.error : cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                          e.kind == 'payment'
                              ? 'Payment received'
                              : (e.kind == 'refund' ? 'Refund' : (e.kind == 'opening' ? 'Correction' : (e.note.isEmpty ? 'Spend' : e.note))),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(_date(e.date), style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                    ]),
                  ),
                  Text('${e.effect >= 0 ? '+' : '−'}${money(e.effect.abs())}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: e.effect > 0 ? cs.error : cs.primary)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      await deleteCardDue(e.id);
                      if (mounted) setState(() {});
                    },
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
