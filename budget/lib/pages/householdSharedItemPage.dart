// A loan or fixed deposit that another household member shared with this person, read only.
// It is a copy kept on this phone (householdSharedCopies.dart): it is never counted in this person's net
// worth, loan totals or reminders, and it follows the owner's changes. If the owner stops sharing it, the
// page says so.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/householdSharedCopies.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String _date(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

class HouseholdSharedItemPage extends StatefulWidget {
  const HouseholdSharedItemPage(
      {required this.docId, required this.kind, Key? key})
      : super(key: key);

  final String docId;
  final String kind;

  @override
  State<HouseholdSharedItemPage> createState() =>
      _HouseholdSharedItemPageState();
}

class _HouseholdSharedItemPageState extends State<HouseholdSharedItemPage> {
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

  SharedCopy? _find() {
    for (final SharedCopy copy in visibleSharedCopies(widget.kind)) {
      if (copy.docId == widget.docId) return copy;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final SharedCopy? copy = _find();
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (copy == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Household'), centerTitle: false),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('This is not shared with you any more.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
          ),
        ),
      );
    }
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double v) => convertToMoney(allWallets, v);

    final List<Widget> body = copy.kind == kSharedKindLoan
        ? _loanBody(context, copy, money)
        : _depositBody(context, copy, money);
    final String title = copy.kind == kSharedKindLoan
        ? sharedLoanName(copy.payload)
        : (sharedDeposit(copy.payload)?.bank ?? 'Fixed deposit');

    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            FinCard(
              child: Row(children: [
                Icon(Icons.group_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      'Shared by ${copy.ownerName}. You can look at it but not change it. '
                      'It is not counted in your own totals.',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(0.75))),
                ),
              ]),
            ),
            ...body,
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(label,
                style: TextStyle(color: cs.onSurface.withOpacity(0.65)))),
        const SizedBox(width: 12),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }

  List<Widget> _depositBody(
      BuildContext context, SharedCopy copy, String Function(double) money) {
    final FixedDeposit? fd = sharedDeposit(copy.payload);
    if (fd == null) {
      return [
        const FinCard(child: Text('The details of this deposit could not be read.'))
      ];
    }
    final DateTime today = DateTime.now();
    final int days = daysToMaturity(fd, today);
    final String number = fd.fdNumber.isEmpty ? '' : fd.fdNumber;
    return [
      FinCard(
        child: Column(children: [
          _row(context, 'Bank', fd.bank),
          if (number.isNotEmpty) _row(context, 'Deposit number', number),
          _row(context, 'Deposited', money(fd.principal)),
          _row(context, 'Interest rate', '${fd.ratePct}%'),
          _row(context, 'Interest added', kFdCompoundingNames[fd.compounding] ?? ''),
          _row(context, 'Started', _date(fd.startDate)),
          _row(context, 'Matures', _date(fd.maturityDate)),
          if (!fd.closed)
            _row(
                context,
                'Time left',
                days > 0
                    ? '$days day${days == 1 ? '' : 's'}'
                    : 'Matured'),
          if (fd.closed) _row(context, 'Status', 'Closed'),
        ]),
      ),
      FinCard(
        child: Column(children: [
          _row(context, 'Worth today', money(currentValue(fd, today))),
          _row(context, 'Interest so far', money(accruedInterest(fd, today))),
          _row(context, 'At maturity', money(maturityValue(fd))),
        ]),
      ),
      if (fd.note.trim().isNotEmpty)
        FinCard(child: _row(context, 'Note', fd.note.trim())),
    ];
  }

  List<Widget> _loanBody(
      BuildContext context, SharedCopy copy, String Function(double) money) {
    final LoanTerms? terms = sharedLoanTerms(copy.payload);
    if (terms == null) {
      return [
        const FinCard(
            child: Text(
                'This loan has no repayment schedule, so there is nothing more to show.')),
      ];
    }
    final LoanSummary summary = summarize(terms);
    final LoanProgress progress = loanProgress(terms, 0);
    final List<LoanInstalment> schedule = buildSchedule(terms);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return [
      FinCard(
        child: Column(children: [
          _row(context, 'Borrowed', money(terms.principal)),
          _row(context, 'Interest rate', '${terms.annualRatePct}% a year'),
          _row(context, 'Instalments',
              '${terms.months} × ${money(terms.emi)} a month'),
          _row(context, 'First instalment', _date(terms.firstEmiDate)),
          _row(context, 'Total to pay', money(summary.totalPayable)),
        ]),
      ),
      FinCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(context, 'Paid (ticked instalments)', money(progress.repaid)),
          const SizedBox(height: 6),
          FinProgress(progress.fraction,
              height: 6, color: finColorFor(sharedLoanName(copy.payload))),
          const SizedBox(height: 8),
          Text(
              'This only counts the instalments ${copy.ownerName} ticked as paid. '
              'Payments they recorded as transactions are not shown here.',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        ]),
      ),
      FinSectionTitle('Schedule'),
      for (final LoanInstalment i in schedule)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(children: [
            Icon(
                terms.paidInstalments.contains(i.number)
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
                color: terms.paidInstalments.contains(i.number)
                    ? cs.primary
                    : cs.onSurface.withOpacity(0.4)),
            const SizedBox(width: 10),
            Expanded(child: Text('${i.number}.  ${_date(i.dueDate)}')),
            Text(money(i.totalDue),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
    ];
  }
}
