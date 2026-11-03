// Checks which bank SMS Paddhu Pusthakam saves by itself and which go to the review list
// (lib/struct/autoSmsPolicy.dart). Pure Dart, run it with:  dart run test/auto_sms_policy_test.dart
//
// The SMS texts follow the formats the parser already handles (see tool/reference/smsparse.py).

import 'dart:convert';
import 'dart:io';

import '../lib/struct/autoSmsPolicy.dart';
import '../lib/struct/pingImport.dart';

int failures = 0;

PingImportRow rowOf(String sender, String body) {
  final String json = jsonEncode({
    'app': 'Ping',
    'type': 'paddhu-sms-export',
    'version': 1,
    'sms': [
      {'id': 'n1-test', 'address': sender, 'body': body, 'date': 1793600000000},
    ],
  });
  final PingImport parsed = parsePingExport(json);
  if (parsed.rows.isEmpty) throw StateError('parser skipped: $body');
  return parsed.rows.first;
}

void expectVerdict(String name, PingImportRow row, AutoSmsVerdict want,
    {String? learned}) {
  final AutoSmsDecision d = decideAutoSave(row, learnedCategoryPk: learned);
  final bool ok = d.verdict == want;
  if (!ok) failures++;
  print('${ok ? 'PASS' : 'FAIL'}  $name  (${d.verdict.name}: ${d.reason})');
}

void main() {
  // known account (Axis 6372) + merchant keyword (Zepto -> groceries)
  expectVerdict(
      'known account + merchant keyword is saved',
      rowOf('AX-AXISBK-S',
          'INR 250.00 debited from A/c no. XX6372 on 03-11-26 12:30:11 UPI/P2M/412345678901/Zepto Not you? SMS BLOCK UPI to 7308080808, Axis Bank'),
      AutoSmsVerdict.save);

  // transfer to a person: no keyword, nothing learned
  final PingImportRow person = rowOf('VM-SBIUPI-S',
      'Dear UPI user A/C X6919 debited by 500.0 on date 03Nov26 trf to RAJESH KUMAR Refno 412345678901. If not u? call 1800111109 for other services-call 1800112211 -SBI');
  expectVerdict('transfer to a person goes to review', person,
      AutoSmsVerdict.review);
  // ...until you have categorised that name once (Paddhu's associated titles)
  expectVerdict('same person after you chose a category is saved', person,
      AutoSmsVerdict.save,
      learned: '2');

  // account that is not in knownAccounts.dart
  expectVerdict(
      'account not in your list goes to review',
      rowOf('AX-HDFCBK-S',
          'Rs 300.00 debited from a/c **9999 on 03-11-26 to VPA swiggy@icici(UPI Ref No 412345678903). Not you? Call 18002586161'),
      AutoSmsVerdict.review);

  // closed account
  expectVerdict(
      'closed account goes to review',
      rowOf('AX-ICICIT-S',
          'ICICI Bank Acct XX090 debited for Rs 120.00 on 03-Nov-26; Hyderabad Metro credited. UPI:412345678904. Call 18002662 for dispute.'),
      AutoSmsVerdict.review);

  // salary credit to a known account needs no merchant
  expectVerdict(
      'salary credit is saved',
      rowOf('AX-AXISBK-S',
          'INR 5000.00 credited to A/c no. XX6372 on 03-11-26 12:30:11 Salary from ACME CORP. Axis Bank'),
      AutoSmsVerdict.save);

  // pension / provident fund rows are never automatic
  expectVerdict(
      'pension scheme row goes to review',
      rowOf('JD-KFNCRA',
          'Contribution of Rs 5000.00 credited to your NPS Tier 1 account XXXXXXXX0840 on 03-11-26'),
      AutoSmsVerdict.review);

  print(failures == 0 ? '\nALL PASSED' : '\n$failures FAILED');
  exit(failures == 0 ? 0 : 1);
}
