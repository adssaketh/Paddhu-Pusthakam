// Edit a loan or fixed deposit that another household member shared with this person AND allowed them to
// change (membersCanEdit). Nothing here touches this person's own loans, deposits, accounts or totals: the
// change is written to the household's copy (householdSharedEdit.dart) and the owner's phone applies it to
// the real item. Only the owner deletes the item or changes who sees it.

import 'package:budget/functions.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/householdSharedCopies.dart';
import 'package:budget/struct/householdSharedEdit.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:flutter/material.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String _date(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';
String _day(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

class HouseholdSharedEditPage extends StatefulWidget {
  const HouseholdSharedEditPage(
      {required this.docId, required this.kind, Key? key})
      : super(key: key);

  final String docId;
  final String kind;

  @override
  State<HouseholdSharedEditPage> createState() =>
      _HouseholdSharedEditPageState();
}

class _HouseholdSharedEditPageState extends State<HouseholdSharedEditPage> {
  // The copy as it was when this page opened: the edit starts from it, so a change that came in meanwhile
  // is noticed when saving (the server refuses an edit made on top of an older copy).
  SharedCopy? _copy;

  // deposit: _name is the bank, _a the amount. loan: _name is the loan's name, _a the loan amount.
  final TextEditingController _name = TextEditingController();
  final TextEditingController _a = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _maturityAmount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _months = TextEditingController();
  final TextEditingController _emi = TextEditingController();
  final TextEditingController _fee = TextEditingController();
  final TextEditingController _gst = TextEditingController(text: '18');

  DateTime _start = DateTime.now();
  DateTime _maturity = DateTime.now().add(const Duration(days: 365));
  int _compounding = 4;
  bool _closed = false;

  DateTime _firstEmi = DateTime.now();
  bool _feePaid = false;
  Set<int> _paid = <int>{};
  bool _showAll = false;

  bool _saving = false;

  bool get _isLoan => widget.kind == kSharedKindLoan;

  @override
  void initState() {
    super.initState();
    for (final SharedCopy copy in visibleSharedCopies(widget.kind)) {
      if (copy.docId == widget.docId) _copy = copy;
    }
    final SharedCopy? copy = _copy;
    if (copy == null) return;
    if (_isLoan) {
      _name.text = sharedLoanName(copy.payload);
      final LoanTerms? t = sharedLoanTerms(copy.payload);
      if (t != null) {
        _a.text = _n(t.principal);
        _rate.text = _n(t.annualRatePct);
        _months.text = t.months.toString();
        _emi.text = _n(t.emi);
        _fee.text = _n(t.feeAmount);
        _gst.text = _n(t.gstPct);
        _firstEmi = t.firstEmiDate;
        _feePaid = t.feePaid;
        _paid = Set<int>.from(t.paidInstalments);
      }
    } else {
      final FixedDeposit? d = sharedDeposit(copy.payload);
      if (d != null) {
        _name.text = d.bank;
        _number.text = d.fdNumber;
        _a.text = _n(d.principal);
        _rate.text = _n(d.ratePct);
        _maturityAmount.text =
            d.maturityAmount == null ? '' : _n(d.maturityAmount!);
        _note.text = d.note;
        _start = d.startDate;
        _maturity = d.maturityDate;
        _compounding = d.compounding;
        _closed = d.closed;
      }
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in [
      _name, _a, _rate, _number, _maturityAmount, _note, _months, _emi, _fee, _gst
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100));

  // ---- what is built from the form

  FixedDeposit? _buildDeposit() {
    final SharedCopy? copy = _copy;
    final FixedDeposit? base = copy == null ? null : sharedDeposit(copy.payload);
    if (base == null) return null;
    final double principal = _num(_a);
    if (principal <= 0 || _name.text.trim().isEmpty || !_maturity.isAfter(_start)) {
      return null;
    }
    final double stated = _num(_maturityAmount);
    return base.copyWith(
      bank: _name.text.trim(),
      fdNumber: _number.text.trim(),
      principal: principal,
      ratePct: _num(_rate),
      startDate: _start,
      maturityDate: _maturity,
      compounding: _compounding,
      maturityAmount: stated > 0 ? stated : null,
      clearMaturityAmount: stated <= 0,
      closed: _closed,
      note: _note.text.trim(),
    );
  }

  LoanTerms? _buildTerms() {
    final SharedCopy? copy = _copy;
    final LoanTerms? base = copy == null ? null : sharedLoanTerms(copy.payload);
    if (base == null) return null;
    final double principal = _num(_a);
    final int months = _num(_months).round();
    if (principal <= 0 || months <= 0) return null;
    final double rate = _num(_rate);
    return base.copyWith(
      principal: principal,
      annualRatePct: rate,
      months: months,
      emi: _num(_emi) > 0 ? _num(_emi) : suggestedEmi(principal, rate, months),
      firstEmiDate: _firstEmi,
      feeAmount: _num(_fee),
      gstPct: _num(_gst),
      feePaid: _feePaid,
      paidInstalments: {
        for (final int n in _paid)
          if (n >= 1 && n <= months) n
      },
    );
  }

  // ---- saving

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final SharedCopy? copy = _copy;
    if (copy == null || _saving) return;
    final Map<String, dynamic> payload;
    if (_isLoan) {
      final LoanTerms? terms = _buildTerms();
      if (terms == null || _name.text.trim().isEmpty) {
        _say('Enter a name, the loan amount and the number of months.');
        return;
      }
      payload = sharedLoanPayloadFrom(
          oldPayload: copy.payload, name: _name.text, terms: terms);
    } else {
      final FixedDeposit? fd = _buildDeposit();
      if (fd == null) {
        _say('Enter the bank, the amount, and a maturity date after the start date.');
        return;
      }
      payload = sharedDepositPayload(fd);
    }
    setState(() => _saving = true);
    final String? error = await saveSharedCopyEdit(
        kind: widget.kind, docId: copy.docId, payload: payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _say(error);
      return;
    }
    popRoute(context);
  }

  // ---- screen

  @override
  Widget build(BuildContext context) {
    final SharedCopy? copy = _copy;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool readable = copy != null &&
        (_isLoan
            ? sharedLoanTerms(copy.payload) != null
            : sharedDeposit(copy.payload) != null);

    if (copy == null || !copy.canEdit || !readable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Household'), centerTitle: false),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
                copy == null
                    ? 'This is not shared with you any more.'
                    : !copy.canEdit
                        ? 'The owner has not allowed you to change this.'
                        : 'The details of this cannot be changed here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(_isLoan ? 'Edit shared loan' : 'Edit shared deposit'),
          centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FinCard(
              child: Row(children: [
                Icon(Icons.group_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      'Shared by ${copy.ownerName}. Your change goes to them and to everyone it is shared with. '
                      'Only ${copy.ownerName} can delete it or change who sees it.',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(0.75))),
                ),
              ]),
            ),
            if (_isLoan) ..._loanForm(context) else ..._depositForm(context),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Save',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
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

  Widget _gap(Widget w) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

  Widget _two(Widget a, Widget b) => _gap(Row(children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ]));

  Widget _dateTile(String label, DateTime d, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: InputDecorator(
          decoration: finInput(context, label),
          child: Row(children: [
            const Icon(Icons.event, size: 18),
            const SizedBox(width: 8),
            Text(_date(d), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  List<Widget> _depositForm(BuildContext context) {
    return [
      const FinSectionTitle('Deposit'),
      FinCard(
        child: Column(children: [
          _gap(_field('Bank', _name, text: true)),
          _gap(_field('FD number / account (optional)', _number, text: true)),
          _two(_field('Amount', _a), _field('Interest', _rate, suffix: '% a year')),
        ]),
      ),
      const FinSectionTitle('Dates and interest'),
      FinCard(
        child: Column(children: [
          _gap(Row(children: [
            Expanded(
                child: _dateTile('Start', _start, () async {
              final DateTime? p = await _pick(_start);
              if (p != null) setState(() => _start = p);
            })),
            const SizedBox(width: 12),
            Expanded(
                child: _dateTile('Maturity', _maturity, () async {
              final DateTime? p = await _pick(_maturity);
              if (p != null) setState(() => _maturity = p);
            })),
          ])),
          _gap(DropdownButtonFormField<int>(
            value: _compounding,
            isExpanded: true,
            decoration: finInput(context, 'Interest added'),
            items: [
              for (final MapEntry<int, String> e in kFdCompoundingNames.entries)
                DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _compounding = v);
            },
          )),
          _field('Maturity amount from the bank (optional)', _maturityAmount),
        ]),
      ),
      const FinSectionTitle('Other'),
      FinCard(
        child: Column(children: [
          _gap(_field('Note (optional)', _note, text: true)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Closed'),
            subtitle: const Text('Turn on when the deposit has matured and been paid out'),
            value: _closed,
            onChanged: (v) => setState(() => _closed = v),
          ),
        ]),
      ),
    ];
  }

  List<Widget> _loanForm(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final LoanTerms? t = _buildTerms();
    final List<LoanInstalment> schedule =
        t == null ? <LoanInstalment>[] : buildSchedule(t);
    final List<LoanInstalment> shown =
        _showAll ? schedule : schedule.take(12).toList();
    return [
      const FinSectionTitle('Loan details'),
      FinCard(
        child: Column(children: [
          _gap(_field('Name', _name, text: true)),
          _two(_field('Loan amount', _a), _field('Interest', _rate, suffix: '% a year')),
          _two(
            _field('Months', _months),
            Row(children: [
              Expanded(child: _field('EMI', _emi)),
              IconButton(
                tooltip: 'Calculate the EMI',
                icon: const Icon(Icons.calculate_outlined),
                onPressed: () {
                  final double e = suggestedEmi(
                      _num(_a), _num(_rate), _num(_months).round());
                  setState(() => _emi.text = _n(e));
                },
              ),
            ]),
          ),
          _two(_field('Processing fee', _fee), _field('GST', _gst, suffix: '%')),
          _gap(OutlinedButton.icon(
            onPressed: () async {
              final DateTime? p = await _pick(_firstEmi);
              if (p != null) setState(() => _firstEmi = p);
            },
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
            value: _feePaid,
            onChanged: (v) => setState(() => _feePaid = v),
          ),
        ]),
      ),
      if (t != null) ...[
        FinSectionTitle(
          'Instalments paid',
          trailing: TextButton(
            onPressed: () =>
                setState(() => _paid = instalmentsDueBy(t, DateTime.now())),
            child: const Text('Tick all due so far'),
          ),
        ),
        FinCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tap a month that has been paid.',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final LoanInstalment i in shown)
                FilterChip(
                  label: Text('${i.number} · ${_day(i.dueDate)}'),
                  selected: _paid.contains(i.number),
                  onSelected: (bool on) => setState(() {
                    if (on) {
                      _paid.add(i.number);
                    } else {
                      _paid.remove(i.number);
                    }
                  }),
                ),
            ]),
            if (schedule.length > shown.length)
              TextButton(
                  onPressed: () => setState(() => _showAll = true),
                  child: Text('Show all ${schedule.length} instalments')),
          ]),
        ),
      ],
    ];
  }
}
