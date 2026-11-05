// Fixed deposits: every deposit by bank, what it is worth today, when it matures. Deposits can be added by
// hand here, or arrive by themselves from a bank "FD booked" SMS through Ping.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/financeUi.dart';
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
  bool _showClosed = false;

  Future<void> _open([FixedDeposit? fd]) async {
    await pushRoute(context, FixedDepositFormPage(deposit: fd));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
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
    final FixedDeposit? next = open.isEmpty ? null : open.first;

    final Map<String, List<FixedDeposit>> byBank = {};
    for (final FixedDeposit fd in open) {
      byBank.putIfAbsent(fd.bank, () => []).add(fd);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fixed deposits'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Add deposit'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            FinHero(
              icon: Icons.savings_outlined,
              label: 'Worth today',
              amount: money(value),
              caption: open.isEmpty
                  ? 'No open deposits'
                  : '${open.length} open deposit${open.length == 1 ? '' : 's'} in ${byBank.length} bank${byBank.length == 1 ? '' : 's'}',
              progress: atMaturity <= invested ? null : ((value - invested) / (atMaturity - invested)),
              progressLeft: open.isEmpty ? null : 'Interest earned ${money(value - invested)}',
              progressRight: open.isEmpty ? null : 'of ${money(atMaturity - invested)}',
              pills: [
                FinPill('Invested ${money(invested)}', icon: Icons.south_west, onHero: true),
                FinPill('At maturity ${money(atMaturity)}', icon: Icons.flag_outlined, onHero: true),
                if (next != null)
                  FinPill(
                      daysToMaturity(next, today) > 0
                          ? 'Next in ${daysToMaturity(next, today)} days'
                          : 'Matured: check ${next.bank}',
                      icon: Icons.notifications_none,
                      onHero: true),
              ],
            ),
            if (open.isEmpty)
              FinCard(
                child: Column(children: [
                  Icon(Icons.savings_outlined, size: 40, color: cs.primary),
                  const SizedBox(height: 10),
                  const Text('No fixed deposits yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                      'Tap "Add deposit". Deposits booked from now on are added automatically when Ping sees the bank SMS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.65))),
                ]),
              ),
            for (final MapEntry<String, List<FixedDeposit>> e in byBank.entries) ...[
              FinSectionTitle(e.key,
                  trailing: Text(
                      money(e.value.fold(0.0, (double a, FixedDeposit f) => a + currentValue(f, today))),
                      style: const TextStyle(fontWeight: FontWeight.w800))),
              for (final FixedDeposit fd in e.value) _card(fd, today, money),
            ],
            if (closed.isNotEmpty) ...[
              FinSectionTitle('Closed (${closed.length})',
                  trailing: TextButton(
                      onPressed: () => setState(() => _showClosed = !_showClosed),
                      child: Text(_showClosed ? 'Hide' : 'Show'))),
              if (_showClosed)
                for (final FixedDeposit fd in closed)
                  FinCard(
                    onTap: () => _open(fd),
                    child: Row(children: [
                      FinAvatar(fd.bank, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${fd.bank} · ${money(fd.principal)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_date(fd.startDate)} to ${_date(fd.maturityDate)}',
                            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                      ])),
                    ]),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(FixedDeposit fd, DateTime today, String Function(double) money) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int days = daysToMaturity(fd, today);
    final int total = fd.maturityDate.difference(fd.startDate).inDays;
    final int gone = today.difference(fd.startDate).inDays;
    final double progress = total <= 0 ? 1 : (gone / total).clamp(0.0, 1.0).toDouble();
    final Color accent = finColorFor(fd.bank);
    final String last4 = fd.fdNumber.isEmpty
        ? ''
        : ' ••${fd.fdNumber.length > 4 ? fd.fdNumber.substring(fd.fdNumber.length - 4) : fd.fdNumber}';
    return FinCard(
      onTap: () => _open(fd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FinAvatar(fd.bank),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${money(fd.principal)}$last4',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('${fd.ratePct}% · ${kFdCompoundingNames[fd.compounding] ?? ''}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(currentValue(fd, today)), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text('worth today', style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(0.55))),
          ]),
        ]),
        const SizedBox(height: 14),
        FinProgress(progress, color: accent),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: Text('Matures ${_date(fd.maturityDate)}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.7)))),
          FinPill(days > 0 ? '$days day${days == 1 ? '' : 's'} left' : 'Matured',
              color: days > 0 ? accent : Colors.orange.shade800),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FinStat('Interest so far', money(accruedInterest(fd, today)))),
          Expanded(child: FinStat('At maturity', money(maturityValue(fd)), bold: true)),
        ]),
        if (fd.fromSms)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FinPill('Added from SMS · tap to check', icon: Icons.sms_outlined, color: Colors.orange.shade800),
          ),
      ]),
    );
  }
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
      Transaction(isPrivate: false, 
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
    String money(double v) => convertToMoney(allWallets, v);
    final DateTime today = DateTime.now();

    Widget field(String label, TextEditingController c, {bool text = false, String? suffix}) => TextField(
          controller: c,
          keyboardType: text ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
          decoration: finInput(context, label, suffix: suffix),
          onChanged: (_) => setState(() {}),
        );
    Widget gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

    Widget dateTile(String label, DateTime d, VoidCallback onTap) => InkWell(
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

    return Scaffold(
      appBar: AppBar(title: Text(widget.deposit == null ? 'New fixed deposit' : 'Fixed deposit'), centerTitle: false),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          FinHero(
            icon: Icons.savings_outlined,
            label: _bank.text.trim().isEmpty ? 'Fixed deposit' : _bank.text.trim(),
            amount: preview == null ? '—' : money(maturityValue(preview)),
            caption: preview == null
                ? 'Fill in the details below'
                : 'At maturity · interest ${money(interestAtMaturity(preview))} · worth today ${money(currentValue(preview, today))}',
            pills: [
              if (preview != null) FinPill('${_n(preview.ratePct)}% a year', icon: Icons.percent, onHero: true),
              if (preview != null)
                FinPill('${preview.maturityDate.difference(preview.startDate).inDays} days',
                    icon: Icons.timelapse, onHero: true),
            ],
          ),
          if (widget.deposit?.fromSms == true)
            FinCard(
              child: Row(children: [
                Icon(Icons.sms_outlined, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Added automatically from a bank SMS. Check the details and save to confirm.')),
              ]),
            ),
          const FinSectionTitle('Deposit'),
          FinCard(
            child: Column(children: [
              gap(field('Bank', _bank, text: true)),
              if (banks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final String b in banks)
                        ActionChip(label: Text(b), onPressed: () => setState(() => _bank.text = b)),
                    ]),
                  ),
                ),
              gap(field('FD number / account (optional)', _number, text: true)),
              Row(children: [
                Expanded(child: field('Amount', _principal)),
                const SizedBox(width: 12),
                Expanded(child: field('Interest', _rate, suffix: '% a year')),
              ]),
            ]),
          ),
          const FinSectionTitle('Dates and interest'),
          FinCard(
            child: Column(children: [
              gap(Row(children: [
                Expanded(
                    child: dateTile('Start', _start, () async {
                  final DateTime? p = await _pick(_start);
                  if (p != null) setState(() => _start = p);
                })),
                const SizedBox(width: 12),
                Expanded(
                    child: dateTile('Maturity', _maturity, () async {
                  final DateTime? p = await _pick(_maturity);
                  if (p != null) setState(() => _maturity = p);
                })),
              ])),
              gap(DropdownButtonFormField<int>(
                value: _compounding,
                isExpanded: true,
                decoration: finInput(context, 'Interest added'),
                items: [
                  for (final MapEntry<int, String> e in kFdCompoundingNames.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _compounding = v);
                },
              )),
              field('Maturity amount from the bank (optional)', _maturityAmount),
            ]),
          ),
          const FinSectionTitle('Account'),
          FinCard(
            child: Column(children: [
              gap(DropdownButtonFormField<String>(
                value: allWallets.indexedByPk.containsKey(_walletPk) ? _walletPk : null,
                isExpanded: true,
                decoration: finInput(context, 'Account'),
                items: [
                  for (final TransactionWallet w in allWallets.ownList)
                    DropdownMenuItem(value: w.walletPk, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _walletPk = v);
                },
              )),
              gap(field('Note (optional)', _note, text: true)),
              if (widget.deposit == null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Take the amount out of the account'),
                  subtitle: const Text('Adds an expense for the deposit. Turn off if the bank SMS already recorded it.'),
                  value: _deduct,
                  onChanged: (v) => setState(() => _deduct = v),
                ),
            ]),
          ),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (widget.deposit != null && !widget.deposit!.closed)
            TextButton(onPressed: _markMatured, child: const Text('Mark as matured / closed')),
          if (widget.deposit != null)
            TextButton(
                onPressed: _delete,
                child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
    );
  }
}
