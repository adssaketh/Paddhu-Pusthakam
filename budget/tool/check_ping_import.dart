// Checks lib/struct/pingImport.dart (what the "Import from Ping" screen shows) against the expected
// rows in test/fixtures/ping_export_synthetic.json, which were produced from the reference parser.
//
//   dart run tool/check_ping_import.dart
//
// Exit code 0 when everything matches, 1 otherwise.

import 'dart:convert';
import 'dart:io';

import '../lib/struct/pingImport.dart';

void main() {
  final file = File('test/fixtures/ping_export_synthetic.json');
  if (!file.existsSync()) {
    print('FAIL  ${file.path} not found');
    exit(1);
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final expected = (data['expectedRows'] as List).cast<Map<String, dynamic>>();
  final result = parsePingExport(file.readAsStringSync());

  var bad = 0;
  void problem(String message) {
    bad++;
    print('  MISMATCH $message');
  }

  if (result.skipped != data['expectedSkipped']) {
    problem('skipped: want ${data['expectedSkipped']}, got ${result.skipped}');
  }
  if (result.rows.length != expected.length) {
    problem('rows: want ${expected.length}, got ${result.rows.length}');
  }
  final byId = {for (final r in result.rows) r.smsId: r};
  for (final e in expected) {
    final row = byId[e['smsId']];
    if (row == null) {
      problem('sms ${e['smsId']} is missing');
      continue;
    }
    void check(String field, Object? want, Object? got) {
      if (want != got) problem('sms ${e['smsId']} $field: want $want, got $got');
    }

    check('amount', (e['amount'] as num).toDouble(), row.amount);
    check('isExpense', e['isExpense'], row.isExpense);
    check('title', e['title'], row.title);
    check('categoryLabel', e['categoryLabel'], row.categoryLabel);
    check('walletName', e['walletName'], row.walletName);
    check('accountName', e['accountName'], row.accountName);
    check('closed', e['closed'], row.closed);
    check('tickByDefault', e['tickByDefault'], row.tickByDefault);
  }

  if (bad == 0) {
    print('PASS  ${file.path} (${expected.length} rows)');
  } else {
    print('FAIL  $bad differences');
    exit(1);
  }
}
