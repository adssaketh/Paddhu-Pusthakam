// Add or edit an instalment loan (fixed rate, monthly EMI, 18% GST on the interest and on the fee), such as
// the Axis Bank "Instant Loan on Credit Card". Shows the schedule, lets you tick the EMIs you have already
// paid, and keeps the total outstanding (with interest and GST) up to date.
//
// Payments you record later: choose this loan in "Long term loan" when adding the transaction, and the
// amount is taken off the outstanding automatically.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/loanTerms.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _date(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

class LoanTermsPage extends StatefulWidget {
  const LoanTermsPage({Key? key, this.objective}) : super(key: key);

  /// Null: a new loan is created when you save.
  final Objective? objective;

  @override
  State<LoanTermsPage> createState() => _LoanTermsPageState();
}

class _LoanTermsPageState extends State<LoanTermsPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _principal = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _months = TextEditingController();
  final TextEditingController _emi = TextEditingController();
  final TextEditingController _fee = TextEditingController();
  final TextEditingController _gst = TextEditingController(text: '18');
  DateTime _firstEmi = DateTime.now();
  bool _feePaid = false;
  Set<int> _paid = <int>{};
  String _walletPk = appStateSettings["selectedWalletPk"].toString();
  double _linkedSum = 0;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    final Objective? o = widget.objective;
    if (o != null) {
      _name.text = o.name;
      _walletPk = o.walletFk;
      final LoanTerms? t = loanTermsFor(o.objectivePk);
      if (t != null) _fill(t);
      _loadLinked(o);
    }
  }

  Future<void> _loadLinked(Objective o) async {
    try {
      final double sum = await database.getTotalTowardsObjective(
              Provider.of<AllWallets>(context, listen: false),
              o.objectivePk,
              ObjectiveType.loan) ??
          0;
      if (mounted) setState(() => _linkedSum = sum);
    } catch (_) {}
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  void _fill(LoanTerms t) {
    _principal.text = _n(t.principal);
    _rate.text = _n(t.annualRatePct);
    _months.text = t.months.toString();
    _emi.text = _n(t.emi);
    _fee.text = _n(t.feeAmount);
    _gst.text = _n(t.gstPct);
    _firstEmi = t.firstEmiDate;
    _feePaid = t.feePaid;
    _paid = Set<int>.from(t.paidInstalments);
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  LoanTerms? _terms() {
    final double principal = _num(_principal);
    final int months = _num(_months).round();
    if (principal <= 0 || months <= 0) return null;
    return LoanTerms(
      principal: principal,
      annualRatePct: _num(_rate),
      months: months,
      emi: _num(_emi) > 0
          ? _num(_emi)
          : suggestedEmi(principal, _num(_rate), months),
      firstEmiDate: _firstEmi,
      feeAmount: _num(_fee),
      gstPct: _num(_gst),
      feePaid: _feePaid,
      paidInstalments: _paid,
      walletPk: _walletPk,
      note: widget.objective == null ? _name.text : '',
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _firstEmi,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _firstEmi = picked);
  }

  Future<void> _save() async {
    final LoanTerms? t = _terms();
    if (t == null || _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a name, the loan amount and the number of months.')));
      return;
    }
    final double total = summarize(t).totalPayable;
    final Objective? existing = widget.objective;
    String pk;
    if (existing == null) {
      final int count = (await database.getTotalCountOfObjectives(
              objectiveType: ObjectiveType.loan))[0] ??
          0;
      final int rowId = await database.createOrUpdateObjective(
        Objective(
          objectivePk: "-1",
          name: _name.text.trim(),
          colour: null,
          dateCreated: DateTime.now(),
          endDate: null,
          dateTimeModified: null,
          order: count,
          emojiIconName: null,
          iconName: "image.png",
          amount: total,
          income: false,
          pinned: true,
          walletFk: _walletPk,
          archived: false,
          type: ObjectiveType.loan,
        ),
        insert: true,
      );
      pk = (await database.getObjectiveFromRowId(rowId)).objectivePk;
    } else {
      pk = existing.objectivePk;
      await database.createOrUpdateObjective(existing.copyWith(
        name: _name.text.trim(),
        amount: total,
        income: false,
        walletFk: _walletPk,
      ));
    }
    await saveLoanTerms(pk, t);
    if (mounted) popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final LoanTerms? t = _terms();
    final LoanSummary? s = t == null ? null : summarize(t);
    final List<LoanInstalment> schedule =
        t == null ? <LoanInstalment>[] : buildSchedule(t);
    final LoanProgress? p = t == null ? null : loanProgress(t, _linkedSum);
    String money(double v) => convertToMoney(allWallets, v);
    final DateTime today = DateTime.now();

    LoanInstalment? next;
    for (final LoanInstalment i in schedule) {
      if (!_paid.contains(i.number)) {
        next = i;
        break;
      }
    }

    Widget field(String label, TextEditingController c,
        {String? suffix, bool text = false}) {
      return TextField(
        controller: c,
        keyboardType: text
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: finInput(context, label, suffix: suffix),
        onChanged: (_) => setState(() {}),
      );
    }

    Widget two(Widget a, Widget b) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ]),
        );
    Widget one(Widget a) => Padding(padding: const EdgeInsets.only(bottom: 12), child: a);

    final List<LoanInstalment> shown =
        _showAll ? schedule : schedule.take(12).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.objective == null ? 'New instalment loan' : 'Loan'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // ---- hero
            FinHero(
              icon: Icons.account_balance_outlined,
              label: _name.text.trim().isEmpty ? 'Loan' : _name.text.trim(),
              amount: p == null ? '—' : money(p.outstanding),
              caption: s == null ? 'Fill in the details below' : 'Outstanding: left to pay with interest and GST',
              progress: p?.fraction,
              progressLeft: p == null ? null : 'Paid ${money(p.repaid)}',
              progressRight: p == null ? null : 'of ${money(p.totalPayable)}',
              pills: [
                if (t != null) FinPill('EMI ${money(t.emi)}', icon: Icons.event_repeat, onHero: true),
                if (t != null) FinPill('${_n(t.annualRatePct)}% a year', icon: Icons.percent, onHero: true),
                if (t != null)
                  FinPill('${_paid.length} of ${schedule.length} EMIs paid', icon: Icons.check_circle_outline, onHero: true),
                if (next != null)
                  FinPill('Next ${_date(next.dueDate)}', icon: Icons.schedule, onHero: true),
              ],
            ),

            // ---- details
            const FinSectionTitle('Loan details'),
            FinCard(
              child: Column(children: [
                one(field('Name', _name, text: true)),
                one(DropdownButtonFormField<String>(
                  value: allWallets.indexedByPk.containsKey(_walletPk) ? _walletPk : null,
                  isExpanded: true,
                  decoration: finInput(context, 'Account'),
                  items: [
                    for (final TransactionWallet w in allWallets.list)
                      DropdownMenuItem(value: w.walletPk, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _walletPk = v);
                  },
                )),
                two(field('Loan amount', _principal), field('Interest', _rate, suffix: '% a year')),
                two(field('Months', _months), Row(children: [
                  Expanded(child: field('EMI', _emi)),
                  IconButton(
                    tooltip: 'Calculate the EMI',
                    icon: const Icon(Icons.calculate_outlined),
                    onPressed: () {
                      final double e = suggestedEmi(_num(_principal), _num(_rate), _num(_months).round());
                      setState(() => _emi.text = _n(e));
                    },
                  ),
                ])),
                two(field('Processing fee', _fee), field('GST', _gst, suffix: '%')),
                one(OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text('First EMI on ${_date(_firstEmi)}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                )),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Processing fee already paid'),
                  subtitle: const Text('Turn on if it was taken out of the money you received'),
                  value: _feePaid,
                  onChanged: (v) => setState(() => _feePaid = v),
                ),
              ]),
            ),

            // ---- breakdown
            if (s != null && p != null) ...[
              const FinSectionTitle('Where the total comes from'),
              FinCard(
                child: Column(children: [
                  FinLine('Loan amount', money(s.principal)),
                  FinLine('Interest', money(s.totalInterest)),
                  FinLine('GST on interest', money(s.gstOnInterest)),
                  FinLine('Processing fee', money(s.fee)),
                  FinLine('GST on fee', money(s.gstOnFee)),
                  const Divider(height: 18),
                  FinLine('Total to pay', money(s.totalPayable), bold: true),
                  const SizedBox(height: 4),
                  FinLine('Paid: ticked instalments', '− ${money(s.paidFromTicks)}', dim: true),
                  if (widget.objective != null)
                    FinLine('Paid: linked transactions', '− ${money(_linkedSum < 0 ? -_linkedSum : 0)}', dim: true),
                  const Divider(height: 18),
                  FinLine('Outstanding now', money(p.outstanding), bold: true),
                ]),
              ),

              // ---- instalments
              FinSectionTitle(
                'Instalments',
                trailing: TextButton(
                  onPressed: () => setState(() => _paid = instalmentsDueBy(t!, today)),
                  child: const Text('Tick all due so far'),
                ),
              ),
              FinCard(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    child: Text(
                        'Tap a month you already paid outside the app. For payments from now on, add a transaction and pick this loan under "Long term loan"; do not tick those here too.',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  ),
                  for (final LoanInstalment i in shown) _instalmentRow(i, today, money, next?.number == i.number),
                  if (schedule.length > shown.length)
                    TextButton(
                        onPressed: () => setState(() => _showAll = true),
                        child: Text('Show all ${schedule.length} instalments')),
                ]),
              ),
            ],

            const SizedBox(height: 4),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _instalmentRow(LoanInstalment i, DateTime today, String Function(double) money, bool isNext) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool paid = _paid.contains(i.number);
    final bool overdue = !paid && i.dueDate.isBefore(DateTime(today.year, today.month, today.day));
    final Color accent = paid ? Colors.green.shade600 : (overdue ? cs.error : cs.primary);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        if (paid) {
          _paid.remove(i.number);
        } else {
          _paid.add(i.number);
        }
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isNext ? cs.primary.withOpacity(0.08) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: paid ? accent : accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: paid
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text('${i.number}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_date(i.dueDate),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: paid ? TextDecoration.lineThrough : null,
                      color: paid ? cs.onSurface.withOpacity(0.5) : null)),
              Text('EMI ${money(i.emi)} + GST ${money(i.gstOnInterest)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            ]),
          ),
          Text(money(i.totalDue), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (overdue) ...[
            const SizedBox(width: 8),
            Icon(Icons.error_outline, size: 18, color: cs.error),
          ],
        ]),
      ),
    );
  }
}
