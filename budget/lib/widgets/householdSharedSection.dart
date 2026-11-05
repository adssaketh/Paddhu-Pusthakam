// The "Household" list on the Loans page and the Fixed deposits page: the loans or deposits that other
// household members shared with this person. It is its own list and has no total on purpose: these are
// somebody else's money, so they are never added to this person's net worth or loan totals (the copies are
// kept apart from the person's own items, see householdSharedCopies.dart).
//
// Shows nothing at all outside a household or when nobody shared anything of this kind.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/householdSharedItemPage.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/householdSharedCopies.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String _day(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';
String _date(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

class HouseholdSharedSection extends StatefulWidget {
  /// [kind] is [kSharedKindLoan] or [kSharedKindFixedDeposit]. [padding] is only added when the list is
  /// shown, so a person without shared items sees no extra space.
  const HouseholdSharedSection(
      {required this.kind, this.padding = EdgeInsets.zero, Key? key})
      : super(key: key);

  final String kind;
  final EdgeInsetsGeometry padding;

  @override
  State<HouseholdSharedSection> createState() => _HouseholdSharedSectionState();
}

class _HouseholdSharedSectionState extends State<HouseholdSharedSection> {
  @override
  void initState() {
    super.initState();
    sharedCopiesVersion.addListener(_refresh);
  }

  @override
  void dispose() {
    sharedCopiesVersion.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<SharedCopy> copies = visibleSharedCopies(widget.kind);
    if (copies.isEmpty) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double v) => convertToMoney(allWallets, v);

    final List<Widget> cards = widget.kind == kSharedKindLoan
        ? _loanCards(context, copies, money)
        : _depositCards(context, copies, money);
    if (cards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const FinSectionTitle('Household'),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
              'Shared with you by other members. Not counted in your totals.',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(0.6))),
        ),
        ...cards,
      ]),
    );
  }

  void _open(SharedCopy copy) {
    pushRoute(context,
        HouseholdSharedItemPage(docId: copy.docId, kind: copy.kind));
  }

  Widget _sharedBy(BuildContext context, SharedCopy copy) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(Icons.group_outlined, size: 14, color: cs.onSurface.withOpacity(0.55)),
      const SizedBox(width: 5),
      Flexible(
        child: Text('Shared by ${copy.ownerName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
      ),
    ]);
  }

  // ---- fixed deposits

  List<Widget> _depositCards(BuildContext context, List<SharedCopy> copies,
      String Function(double) money) {
    final DateTime today = DateTime.now();
    final List<MapEntry<SharedCopy, FixedDeposit>> list = [
      for (final SharedCopy copy in copies)
        if (sharedDeposit(copy.payload) != null)
          MapEntry(copy, sharedDeposit(copy.payload)!)
    ]..sort((a, b) {
        if (a.value.closed != b.value.closed) return a.value.closed ? 1 : -1;
        return a.value.maturityDate.compareTo(b.value.maturityDate);
      });
    return [
      for (final MapEntry<SharedCopy, FixedDeposit> e in list)
        _depositCard(context, e.key, e.value, today, money)
    ];
  }

  Widget _depositCard(BuildContext context, SharedCopy copy, FixedDeposit fd,
      DateTime today, String Function(double) money) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int days = daysToMaturity(fd, today);
    final int total = fd.maturityDate.difference(fd.startDate).inDays;
    final int gone = today.difference(fd.startDate).inDays;
    final double progress =
        total <= 0 ? 1 : (gone / total).clamp(0.0, 1.0).toDouble();
    final String last4 = fd.fdNumber.isEmpty
        ? ''
        : ' ••${fd.fdNumber.length > 4 ? fd.fdNumber.substring(fd.fdNumber.length - 4) : fd.fdNumber}';
    return FinCard(
      onTap: () => _open(copy),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FinAvatar(fd.bank),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fd.bank}$last4',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              Text('${money(fd.principal)} · ${fd.ratePct}%',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(currentValue(fd, today)),
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
            Text('worth today',
                style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(0.55))),
          ]),
        ]),
        const SizedBox(height: 12),
        FinProgress(progress, color: finColorFor(fd.bank)),
        const SizedBox(height: 8),
        Text(
            fd.closed
                ? 'Closed'
                : days > 0
                    ? 'Matures ${_date(fd.maturityDate)} ($days day${days == 1 ? '' : 's'})'
                    : 'Matured ${_date(fd.maturityDate)}',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 4),
        _sharedBy(context, copy),
      ]),
    );
  }

  // ---- loans

  List<Widget> _loanCards(BuildContext context, List<SharedCopy> copies,
      String Function(double) money) {
    final List<SharedCopy> list = [
      for (final SharedCopy copy in copies)
        if (!sharedLoanArchived(copy.payload)) copy
    ]..sort((a, b) => sharedLoanName(a.payload)
        .toLowerCase()
        .compareTo(sharedLoanName(b.payload).toLowerCase()));
    return [for (final SharedCopy copy in list) _loanCard(context, copy, money)];
  }

  Widget _loanCard(
      BuildContext context, SharedCopy copy, String Function(double) money) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String name = sharedLoanName(copy.payload);
    final LoanTerms? terms = sharedLoanTerms(copy.payload);
    LoanInstalment? next;
    LoanProgress? progress;
    if (terms != null) {
      progress = loanProgress(terms, 0);
      for (final LoanInstalment i in buildSchedule(terms)) {
        if (!terms.paidInstalments.contains(i.number)) {
          next = i;
          break;
        }
      }
    }
    return FinCard(
      onTap: () => _open(copy),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
          if (terms != null)
            Text(money(terms.emi),
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        ]),
        if (terms != null && progress != null) ...[
          const SizedBox(height: 10),
          FinProgress(progress.fraction, height: 6, color: finColorFor(name)),
          const SizedBox(height: 8),
          Text(
              '${terms.annualRatePct}% a year · ${(progress.fraction * 100).round()}% ticked as paid'
              '${next == null ? '' : ' · next EMI ${_day(next.dueDate)}'}',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        ],
        const SizedBox(height: 4),
        _sharedBy(context, copy),
      ]),
    );
  }
}
