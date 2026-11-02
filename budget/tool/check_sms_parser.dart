// Checks lib/struct/smsTransactionParser.dart against the answers produced by the Python reference
// (tool/reference/smsparse.py) and Ping's instrument.ts.
//
// Run from the project root (no extra packages needed):
//   dart run tool/check_sms_parser.dart
//
// Reads:
//   test/fixtures/sms_synthetic.json  - made-up messages with fake digits, safe to commit
//   test/fixtures/sms_golden.json     - every SMS of your real backup (optional, keep it out of git)
// Exit code 0 when everything matches, 1 otherwise.

import 'dart:convert';
import 'dart:io';

import '../lib/struct/smsTransactionParser.dart';

int _failures = 0;

String _describe(ParsedSmsTransaction? p) => p == null
    ? 'null'
    : '{amount: ${p.amount}, isExpense: ${p.isExpense}, merchant: "${p.merchant}", '
        'cardPayment: ${p.cardPayment}, category: "${p.category}", title: "${p.title}", '
        'instrumentKey: ${p.instrumentKey}}';

String? _compare(Map<String, dynamic>? want, ParsedSmsTransaction? got) {
  if (want == null) {
    return got == null ? null : 'expected null, got ${_describe(got)}';
  }
  if (got == null) return 'expected $want, got null';
  final diffs = <String>[];
  if ((want['amount'] as num).toDouble() != got.amount) {
    diffs.add('amount ${want['amount']} vs ${got.amount}');
  }
  if (want['isExpense'] != got.isExpense) {
    diffs.add('isExpense ${want['isExpense']} vs ${got.isExpense}');
  }
  if (want['merchant'] != got.merchant) {
    diffs.add('merchant "${want['merchant']}" vs "${got.merchant}"');
  }
  if (want['cardPayment'] != got.cardPayment) {
    diffs.add('cardPayment ${want['cardPayment']} vs ${got.cardPayment}');
  }
  if (want['category'] != got.category) {
    diffs.add('category "${want['category']}" vs "${got.category}"');
  }
  if (want['title'] != got.title) {
    diffs.add('title "${want['title']}" vs "${got.title}"');
  }
  if (want['instrumentKey'] != got.instrumentKey) {
    diffs.add('instrumentKey ${want['instrumentKey']} vs ${got.instrumentKey}');
  }
  return diffs.isEmpty ? null : diffs.join('; ');
}

void _runFile(String path, {required bool optional}) {
  final file = File(path);
  if (!file.existsSync()) {
    if (optional) {
      print('SKIP  $path (not found)');
      return;
    }
    print('FAIL  $path (not found)');
    _failures++;
    return;
  }

  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (data['cases'] as List).cast<Map<String, dynamic>>();

  var bad = 0;
  for (final c in cases) {
    final got = parseSmsTransaction(
        (c['sender'] ?? '') as String, c['text'] as String);
    final problem =
        _compare((c['expected'] as Map?)?.cast<String, dynamic>(), got);
    if (problem != null) {
      bad++;
      if (bad <= 15) {
        final text = (c['text'] as String).replaceAll('\n', ' ');
        final shown = text.length > 90 ? '${text.substring(0, 90)}...' : text;
        print('  MISMATCH id=${c['id']} sender=${c['sender']}');
        print('           $problem');
        print('           $shown');
      }
    }
  }

  if (bad == 0) {
    print('PASS  $path (${cases.length} messages)');
  } else {
    print('FAIL  $path ($bad of ${cases.length} messages differ)');
    _failures++;
  }
}

void main() {
  _runFile('test/fixtures/sms_synthetic.json', optional: false);
  _runFile('test/fixtures/sms_golden.json', optional: true);
  if (_failures > 0) exit(1);
  print('All SMS parser checks passed.');
}
