// Fixed deposits: every deposit by bank, what it is worth today, when it matures. Deposits can be added by
// hand here, or arrive by themselves from a bank "FD booked" SMS through Ping.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String _date(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

class FixedDepositsPage extends StatefulWidget {
  const FixedDepositsPage({Key? key}) : super(key: key);

  @override
  State<FixedDepositsPage> createState() => _FixedDepositsPageState();
}

class _FixedDepositsPageState extends State<FixedDepositsPage> {
  Future<void> _open([FixedDeposit? fd]) async {
    await pushRoute(context, FixedDepositFormPage(deposit: fd));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double v) => convertToMoney(allWallets, v);
    final DateTime today = DateTime.now();
    final List<FixedDeposit> all = loadFixedDeposits();
    final List<FixedDeposit> open = all.where((e) => !e.closed).toList()
      ..sort((a, b) => a.maturityDate.compareTo(b.maturityDate));
    final List<FixedDeposit> closed = all.where((e) => e.closed).toList();

    double invested = 0, value = 0, atMaturity = 0;
    for (final FixedDeposit fd in open) {
      invested += fd.principal;
      value += currentValue(fd, today);
      atMaturity += maturityValue(fd);
    }

    final Map<String, List<FixedDeposit>> byBank = {};
    for (final FixedDeposit fd in open) {
      byBank.putIfAbsent(fd.bank, () => []).add(fd);
    }

    Widget tile(FixedDeposit fd) {
      final int days = daysToMaturity(fd, today);
      final String when = days > 0
          ? 'matures ${_date(fd.maturityDate)} · in $days day${days == 1 ? '' : 's'}'
          : 'matured ${_date(fd.maturityDate)}';
      return ListTile(
        onTap: () => _open(fd),
        title: Text(
            '${money(fd.principal)} at ${fd.ratePct}%${fd.fdNumber.isEmpty ? '' : '  ·  ••${fd.fdNumber.length > 4 ? fd.fdNumber.substring(fd.fdNumber.length - 4) : fd.fdNumber}'}'),
        subtitle: Text(
            '$when\nNow ${money(currentValue(fd, today))} · at maturity ${money(maturityValue(fd))}'
            '${fd.fromSms ? '\nAdded from SMS: tap to check the details' : ''}'),
        isThreeLine: true,
        trailing: days <= 0 && !fd.closed
            ? const Icon(Icons.notifications_active_outlined)
            : null,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fixed deposits')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _line('Invested', money(invested)),
                _line('Worth today', money(value), bold: true),
                _line('Interest earned so far', money(value - invested)),
                _line('Total at maturity', money(atMaturity)),
              ]),
            ),
            if (open.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'No fixed deposits yet. Tap + to add one. Deposits booked from now on are added automatically when Ping sees the bank SMS.'),
              ),
            for (final MapEntry<String, List<FixedDeposit>> e in byBank.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                  Text(money(e.value.fold(0.0, (double a, FixedDeposit f) => a + currentValue(f, today))),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
              for (final FixedDeposit fd in e.value) tile(fd),
              const Divider(),
            ],
            if (closed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Closed', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final FixedDeposit fd in closed)
                ListTile(
                  onTap: () => _open(fd),
                  title: Text('${fd.bank} · ${money(fd.principal)}'),
                  subtitle: Text('${_date(fd.startDate)} to ${_date(fd.maturityDate)}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ]),
      );
}

class FixedDepositFormPage extends StatefulWidget {
  const FixedDepositFormPage({Key? key, this.deposit}) : super(key: key);
  final FixedDeposit? deposit;

  @override
  State<FixedDepositFormPage> createState() => _FixedDepositFormPageState();
}

class _FixedDepositFormPageState extends State<FixedDepositFormPage> {
  final TextEditingController _bank = TextEditingController();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _principal = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _maturityAmount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime _maturity = DateTime.now().add(const Duration(days: 365));
  int _compounding = 4;
  String _walletPk = appStateSettings["selectedWalletPk"].toString();
  bool _deduct = true;

  @override
  void initState() {
    super.initState();
    final FixedDeposit? d = widget.deposit;
    if (d != null) {
      _bank.text = d.bank;
      _number.text = d.fdNumber;
      _principal.text = _n(d.principal);
      _rate.text = _n(d.ratePct);
      _maturityAmount.text = d.maturityAmount == null ? '' : _n(d.maturityAmount!);
      _note.text = d.note;
      _start = d.startDate;
      _maturity = d.maturityDate;
      _compounding = d.compounding;
      if (d.walletPk != null) _walletPk = d.walletPk!;
    }
  }

  String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  FixedDeposit? _build() {
    final double principal = _num(_principal);
    if (principal <= 0 || _bank.text.trim().isEmpty || !_maturity.isAfter(_start)) return null;
    final FixedDeposit? old = widget.deposit;
    return FixedDeposit(
      id: old?.id ?? newFixedDepositId(),
      bank: _bank.text.trim(),
      fdNumber: _number.text.trim(),
      principal: principal,
      ratePct: _num(_rate),
      startDate: _start,
      maturityDate: _maturity,
      compounding: _compounding,
      maturityAmount: _num(_maturityAmount) > 0 ? _num(_maturityAmount) : null,
      walletPk: _walletPk,
      closed: old?.closed ?? false,
      note: _note.text.trim(),
      fromSms: false,
      smsId: old?.smsId ?? '',
    );
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100));

  /// Records a transaction in the account (the category is asked for). false when cancelled.
  Future<bool> _post({
    required String name,
    required double amount,
    required bool income,
    required DateTime date,
  }) async {
    final MainAndSubcategory c = await selectCategorySequence(
      context,
      selectedCategory: null,
      setSelectedCategory: (_) {},
      selectedSubCategory: null,
      setSelectedSubCategory: (_) {},
      selectedIncomeInitial: null,
      subtitle: 'Pick a category for this transaction',
    );
    if (c.main == null) return false;
    await database.createOrUpdateTransaction(
      insert: true,
      Transaction(
        transactionPk: "-1",
        name: name,
        note: "",
        amount: income ? amount.abs() : -amount.abs(),
        categoryFk: c.main!.categoryPk,
        subCategoryFk: c.sub?.categoryPk,
        walletFk: _walletPk,
        dateCreated: date,
        income: income,
        paid: true,
        skipPaid: false,
        type: null,
        objectiveLoanFk: null,
      ),
    );
    return true;
  }

  Future<void> _save() async {
    final FixedDeposit? fd = _build();
    if (fd == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter the bank, the amount, and a maturity date after the start date.')));
      return;
    }
    if (widget.deposit == null && _deduct) {
      final bool done = await _post(
        name: 'Fixed deposit · ${fd.bank}',
        amount: fd.principal,
        income: false,
        date: fd.startDate,
      );
      if (!done) return; // category not chosen: nothing saved yet
    }
    await upsertFixedDeposit(fd);
    if (mounted) popRoute(context);
  }

  Future<void> _markMatured() async {
    final FixedDeposit? fd = _build();
    if (fd == null) return;
    final double payout = maturityValue(fd);
    final String? choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mark as matured'),
        content: Text(
            'Add ${convertToMoney(Provider.of<AllWallets>(context, listen: false), payout)} back to the account as income?\n\nSkip this if the bank credit already came in through an SMS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, 'no'), child: const Text('Only close it')),
          TextButton(onPressed: () => Navigator.pop(c, 'yes'), child: const Text('Add income')),
        ],
      ),
    );
    if (choice == null || choice == 'cancel') return;
    if (choice == 'yes') {
      final bool done = await _post(
        name: 'Fixed deposit matured · ${fd.bank}',
        amount: payout,
        income: true,
        date: DateTime.now(),
      );
      if (!done) return;
    }
    await upsertFixedDeposit(fd.copyWith(closed: true));
    if (mounted) popRoute(context);
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this fixed deposit?'),
        content: const Text('Transactions already recorded are not removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await deleteFixedDeposit(widget.deposit!.id);
    if (mounted) popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final FixedDeposit? preview = _build();
    final List<String> banks = {for (final FixedDeposit f in loadFixedDeposits()) f.bank}.toList();

    Widget field(String label, TextEditingController c, {bool text = false, String? suffix}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: text ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(widget.deposit == null ? 'Add fixed deposit' : 'Fixed deposit')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.deposit?.fromSms == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Added automatically from a bank SMS. Check the details and save to confirm.'),
            ),
          field('Bank', _bank, text: true),
          if (banks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(spacing: 8, children: [
                for (final String b in banks)
                  ActionChip(label: Text(b), onPressed: () => setState(() => _bank.text = b)),
              ]),
            ),
          field('FD number / account (optional)', _number, text: true),
          field('Amount deposited', _principal),
          field('Interest rate (per year)', _rate, suffix: '%'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () async {
                final DateTime? p = await _pick(_start);
                if (p != null) setState(() => _start = p);
              },
              child: Text('Start date: ${_date(_start)}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () async {
                final DateTime? p = await _pick(_maturity);
                if (p != null) setState(() => _maturity = p);
              },
              child: Text('Maturity date: ${_date(_maturity)}'),
            ),
          ),
          DropdownButtonFormField<int>(
            value: _compounding,
            decoration: const InputDecoration(labelText: 'Interest added', border: OutlineInputBorder()),
            items: [
              for (final MapEntry<int, String> e in kFdCompoundingNames.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _compounding = v);
            },
          ),
          const SizedBox(height: 10),
          field('Maturity amount from the bank (optional)', _maturityAmount),
          DropdownButtonFormField<String>(
            value: allWallets.indexedByPk.containsKey(_walletPk) ? _walletPk : null,
            decoration: const InputDecoration(labelText: 'Account', border: OutlineInputBorder()),
            items: [
              for (final TransactionWallet w in allWallets.list)
                DropdownMenuItem(value: w.walletPk, child: Text(w.name)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _walletPk = v);
            },
          ),
          const SizedBox(height: 10),
          field('Note (optional)', _note, text: true),
          if (widget.deposit == null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Take the amount out of the account'),
              subtitle: const Text('Adds an expense for the deposit. Turn off if the bank SMS already recorded it.'),
              value: _deduct,
              onChanged: (v) => setState(() => _deduct = v),
            ),
          if (preview != null) ...[
            const Divider(),
            Text('At maturity: ${convertToMoney(allWallets, maturityValue(preview))}  '
                '(interest ${convertToMoney(allWallets, interestAtMaturity(preview))})'),
            Text('Worth today: ${convertToMoney(allWallets, currentValue(preview, DateTime.now()))}'),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
          if (widget.deposit != null && !widget.deposit!.closed)
            TextButton(onPressed: _markMatured, child: const Text('Mark as matured / closed')),
          if (widget.deposit != null)
            TextButton(onPressed: _delete, child: const Text('Delete')),
        ]),
      ),
    );
  }
}
