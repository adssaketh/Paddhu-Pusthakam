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
    final LoanTerms? t = _terms();
    final LoanSummary? s = t == null ? null : summarize(t);
    final List<LoanInstalment> schedule =
        t == null ? <LoanInstalment>[] : buildSchedule(t);
    final LoanProgress? p = t == null ? null : loanProgress(t, _linkedSum);
    String money(double v) => convertToMoney(allWallets, v);

    Widget field(String label, TextEditingController c,
        {String? suffix, bool text = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: text
              ? TextInputType.text
              : const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
      );
    }

    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ]),
        );

    final List<LoanInstalment> shown =
        _showAll ? schedule : schedule.take(12).toList();

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.objective == null ? 'Add instalment loan' : 'Loan terms')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            field('Name', _name, text: true),
            DropdownButtonFormField<String>(
              value: allWallets.indexedByPk.containsKey(_walletPk)
                  ? _walletPk
                  : null,
              decoration: const InputDecoration(
                  labelText: 'Account', border: OutlineInputBorder()),
              items: [
                for (final TransactionWallet w in allWallets.list)
                  DropdownMenuItem(value: w.walletPk, child: Text(w.name)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _walletPk = v);
              },
            ),
            const SizedBox(height: 10),
            field('Loan amount', _principal),
            field('Interest rate (per year, reducing balance)', _rate, suffix: '%'),
            field('Number of monthly instalments', _months),
            Row(children: [
              Expanded(child: field('EMI (from the letter)', _emi)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextButton(
                  onPressed: () {
                    final double e = suggestedEmi(
                        _num(_principal), _num(_rate), _num(_months).round());
                    setState(() => _emi.text = _n(e));
                  },
                  child: const Text('Calculate'),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: _pickDate,
                child: Text('First EMI date: ${_date(_firstEmi)}'),
              ),
            ),
            field('Processing fee (before GST)', _fee),
            field('GST on interest and fee', _gst, suffix: '%'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Processing fee already paid'),
              subtitle: const Text(
                  'Turn on if it was taken out of the money you received'),
              value: _feePaid,
              onChanged: (v) => setState(() => _feePaid = v),
            ),
            if (s != null && p != null) ...[
              const Divider(),
              line('Loan amount', money(s.principal)),
              line('Interest over the whole loan', money(s.totalInterest)),
              line('GST on interest', money(s.gstOnInterest)),
              line('Processing fee', money(s.fee)),
              line('GST on fee', money(s.gstOnFee)),
              line('Total to pay', money(s.totalPayable), bold: true),
              const SizedBox(height: 6),
              line('Paid: ticked instalments', money(s.paidFromTicks)),
              if (widget.objective != null)
                line('Paid: transactions linked to this loan',
                    money(_linkedSum < 0 ? -_linkedSum : 0)),
              line('Outstanding now', money(p.outstanding), bold: true),
              const Divider(),
              Row(children: [
                const Expanded(
                    child: Text('Instalments paid so far',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                TextButton(
                  onPressed: () => setState(
                      () => _paid = instalmentsDueBy(t!, DateTime.now())),
                  child: const Text('Tick all due so far'),
                ),
              ]),
              const Text(
                  'Tick the months you already paid outside the app. For payments from now on, add a transaction and pick this loan under "Long term loan"; do not tick those here as well.',
                  style: TextStyle(fontSize: 12)),
              for (final LoanInstalment i in shown)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _paid.contains(i.number),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _paid.add(i.number);
                    } else {
                      _paid.remove(i.number);
                    }
                  }),
                  title: Text('#${i.number}  ${_date(i.dueDate)}'),
                  subtitle: Text(
                      'EMI ${money(i.emi)} + GST ${money(i.gstOnInterest)} = ${money(i.totalDue)}'),
                ),
              if (schedule.length > shown.length)
                TextButton(
                    onPressed: () => setState(() => _showAll = true),
                    child: Text('Show all ${schedule.length} instalments')),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
