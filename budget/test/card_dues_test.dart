import 'dart:convert';
import '../lib/struct/cardDues.dart';
import '../lib/struct/pingImport.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

String export(List<List<dynamic>> sms) => jsonEncode({
      'type': 'paddhu-sms-export',
      'sms': [
        for (final s in sms) {'id': s[0], 'address': 'AX-ICICIT', 'body': s[1], 'date': s[2]}
      ]
    });

void main() {
  final day = DateTime(2026, 11, 3, 14).millisecondsSinceEpoch;
  const spend =
      'INR 1,974.00 spent using ICICI Bank Card XX1000 on 03-Nov-26 on GOOGLE PLAY. Avl Limit: INR 98,026.00. If not you, call 1800 2662/SMS BLOCK 1000 to 9215676766.';
  const paid = 'Payment of Rs 1,974.00 has been received on your ICICI Bank Credit Card XX1000 through Bharat Bill Payment System on 03-NOV-26.';

  var imp = parsePingExport(export([['1', spend, day]]));
  check(imp.cardDues.length == 1 && imp.cardDues[0].kind == 'spend' && imp.cardDues[0].amount == 1974, 'spend counted');
  check(imp.cardDues[0].card == 'Saketh - ICICI Amazon Pay Credit Card', 'card name: ${imp.cardDues[0].card}');
  check(imp.rows.length == 1, 'the spend is still a normal transaction row');

  imp = parsePingExport(export([['1', spend, day], ['2', paid, day + 3600000]]));
  check(imp.cardDues.length == 2 && imp.cardDues[1].kind == 'payment', 'payment counted');
  check(owedByCard(imp.cardDues)['Saketh - ICICI Amazon Pay Credit Card'] == 0, 'spend then payment: nothing owed');
  check(imp.rows.length == 1, 'the payment message is not a transaction (no double count with the bank debit)');

  imp = parsePingExport(export([['1', spend, day]]));
  check(owedByCard(imp.cardDues).values.first == 1974, 'you owe 1974 after the spend');

  // the same SMS sent twice under another id is the same entry
  final a = parsePingExport(export([['1', spend, day]])).cardDues[0];
  final b = parsePingExport(export([['77', spend, day]])).cardDues[0];
  check(a.id == b.id, 'same text and day, same id');

  // add-on cards share one limit with the main Scapia card: their dues are counted together
  const scp = 'Rs 500.00 spent on Federal Bank Scapia Rupay Credit Card XX3777 at SWIGGY on 03-Nov-26';
  const scpPay = 'Payment of Rs 500.00 has been received on your Federal Bank Scapia Credit Card XX1736 on 03-NOV-26.';
  final fed = parsePingExport(jsonEncode({'type': 'paddhu-sms-export', 'sms': [
    {'id': '10', 'address': 'FEDSCP', 'body': scp, 'date': day},
    {'id': '11', 'address': 'FEDSCP', 'body': scpPay, 'date': day + 1000},
  ]})).cardDues;
  print(fed.map((e) => '${e.kind} ${e.amount} ${e.card}').toList());
  check(fed.length == 2 && fed[0].card == fed[1].card && fed[0].card == 'Saketh - Federal Bank Scapia Visa Credit Card', 'add-on and main card share one due');
  check(owedByCard(fed).values.first == 0, 'add-on spend paid through the main card');

  // a debit card is not a credit card
  imp = parsePingExport(export([['3', 'Rs 250.00 spent using SBI Debit Card XX2617 on 03-Nov-26 at SWIGGY', day]]));
  check(imp.cardDues.isEmpty, 'debit card spends are not dues');

  // correcting the amount by hand
  final fix = correctionFor('X', 1974, 5000, DateTime(2026, 11, 4));
  check(owedByCard([...parsePingExport(export([['1', spend, day]])).cardDues.map((e) => CardDueEntry(id: e.id, card: 'X', kind: e.kind, amount: e.amount, date: e.date)), fix])['X'] == 5000, 'set owed to a number');
  check(CardDueEntry.fromJson(fix.toJson())!.amount == fix.amount, 'json round trip');
}
