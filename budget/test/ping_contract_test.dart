// Checks Paddhu Pusthakam against the shared Ping <-> Paddhu contract (contract/ping-paddhu/, identical
// in both repositories). Pure Dart. Run from budget/ with the phone's time zone, because the content key
// uses the local day:
//
//   TZ=Asia/Kolkata dart run test/ping_contract_test.dart
//
// Exit code 0 when everything matches, 1 otherwise.

import 'dart:convert';
import 'dart:io';

import '../lib/struct/pingImport.dart';

int failures = 0;
int checks = 0;

void expectEq(String name, Object? want, Object? got) {
  checks++;
  if (want != got) {
    failures++;
    print('  MISMATCH $name: want $want, got $got');
  }
}

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  const String dir = '../contract/ping-paddhu';
  if (!Directory(dir).existsSync()) {
    print('FAIL  $dir not found (run from budget/)');
    exit(1);
  }
  final DateTime probe = DateTime.fromMillisecondsSinceEpoch(1793000000000);
  expectEq('time zone offset (run with TZ=Asia/Kolkata)', const Duration(hours: 5, minutes: 30), probe.timeZoneOffset);

  // 1. content keys equal Ping's golden vectors
  final golden = readJson('$dir/golden/ids-and-keys.json');
  for (final dynamic k in golden['contentKeys'] as List) {
    final Map<String, dynamic> e = k as Map<String, dynamic>;
    final String key = pingContentKey(
        e['body'] as String, DateTime.fromMillisecondsSinceEpoch((e['dateMs'] as num).toInt()));
    expectEq('content key of "${(e['body'] as String).replaceAll('\n', ' ')}"', e['key'], key);
  }

  // 2. every sample is readable, and the optional fields change nothing
  final List<FileSystemEntity> samples =
      Directory('$dir/samples').listSync().where((e) => e.path.endsWith('.json')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  expectEq('number of samples', 5, samples.length);
  for (final FileSystemEntity f in samples) {
    final String name = f.path.split('/').last;
    final String text = File(f.path).readAsStringSync();
    final Map<String, dynamic> doc = jsonDecode(text) as Map<String, dynamic>;
    expectEq('$name type', 'paddhu-sms-export', doc['type']);
    expectEq('$name version', 1, doc['version']);
    for (final dynamic item in doc['sms'] as List) {
      final Map<String, dynamic> m = item as Map<String, dynamic>;
      for (final String field in ['id', 'address', 'body', 'date']) {
        expectEq('$name item has $field', true, m.containsKey(field));
      }
      final Object? kind = m['kind'];
      expectEq('$name kind value', true, kind == null || kind == 'transaction' || kind == 'fixed_deposit');
    }
    final PingImport withFields = parsePingExport(text);
    // the same file with the optional fields removed (what an old Ping sends)
    final Map<String, dynamic> legacy = jsonDecode(text) as Map<String, dynamic>;
    for (final dynamic item in legacy['sms'] as List) {
      for (final String k in ['brand', 'brandKey', 'kind', 'category']) {
        (item as Map<String, dynamic>).remove(k);
      }
    }
    final PingImport without = parsePingExport(jsonEncode(legacy));
    expectEq('$name rows with/without optional fields', without.rows.length, withFields.rows.length);
    expectEq('$name skipped with/without optional fields', without.skipped, withFields.skipped);
    expectEq('$name ids with/without optional fields',
        without.rows.map((r) => '${r.smsId}|${r.contentKey}|${r.amount}').join(','),
        withFields.rows.map((r) => '${r.smsId}|${r.contentKey}|${r.amount}').join(','));
    print('  $name: ${withFields.rows.length} row(s), ${withFields.skipped} skipped');
  }

  // 3. fixed deposits: routed by `kind`, with Paddhu's own detection as the fallback (SPEC section 2)
  String sample(String name) => File('$dir/samples/$name').readAsStringSync();
  final String fdText = sample('auto-send-fixed-deposit.json');
  expectEq('FD sample (kind fixed_deposit)', 1, parsePingFixedDeposits(fdText).length);
  Map<String, dynamic> fdDoc() => jsonDecode(fdText) as Map<String, dynamic>;
  void setKind(Map<String, dynamic> doc, Object? kind) {
    final Map<String, dynamic> item = (doc['sms'] as List).first as Map<String, dynamic>;
    if (kind == null) {
      item.remove('kind');
    } else {
      item['kind'] = kind;
    }
  }

  for (final Object? kind in [null, 'something_new', '']) {
    final Map<String, dynamic> d = fdDoc();
    setKind(d, kind);
    expectEq('FD with kind $kind falls back to own detection', 1,
        parsePingFixedDeposits(jsonEncode(d)).length);
  }
  final Map<String, dynamic> asTransaction = fdDoc();
  setKind(asTransaction, 'transaction');
  expectEq('kind transaction is not tried as FD', 0, parsePingFixedDeposits(jsonEncode(asTransaction)).length);
  final fd = parsePingFixedDeposits(fdText).first.deposit;
  expectEq('FD principal', 30000.0, fd.principal);
  for (final String name in ['auto-send-single.json', 'date-range.json', 'legacy-minimal.json', 'long-press.json']) {
    expectEq('$name has no fixed deposit', 0, parsePingFixedDeposits(sample(name)).length);
  }
  // a date-range file that now also carries a fixed deposit: the deposit is found, the debit rows stay
  final Map<String, dynamic> mixed = jsonDecode(sample('date-range.json')) as Map<String, dynamic>;
  ((mixed['sms'] as List)).add(((fdDoc()['sms'] as List).first as Map<String, dynamic>)..['id'] = '1203');
  expectEq('mixed range: FD found', 1, parsePingFixedDeposits(jsonEncode(mixed)).length);
  expectEq('mixed range: no duplicate id twice', 1,
      parsePingFixedDeposits(jsonEncode({...mixed, 'sms': [...mixed['sms'] as List, (mixed['sms'] as List).last]})).length);
  var notExport = false;
  try {
    parsePingFixedDeposits('{"type":"x","sms":[]}');
  } on FormatException {
    notExport = true;
  }
  expectEq('FD reader refuses a non-export', true, notExport);

  // 4. "View SMS in Ping": what Ping needs is found again from the note of a saved transaction (SPEC section 8)
  final PingImport single = parsePingExport(sample('auto-send-single.json'));
  final String singleNote = single.rows.first.note;
  expectEq('note carries the sender', true, singleNote.endsWith('Ping SMS from AX-AXISBK-S'));
  final PingSmsRef? nRef = pingSmsRefOfNote(singleNote);
  expectEq('n-id: address', 'AX-AXISBK-S', nRef?.address);
  expectEq('n-id: date from the id', 1793000000000, nRef?.date);
  expectEq('n-id: no smsId', null, nRef?.smsId);
  final PingImport range = parsePingExport(sample('date-range.json'));
  final PingSmsRef? rRef = pingSmsRefOfNote(range.rows.first.note);
  expectEq('system id: smsId', true, rRef?.smsId == '1201' || rRef?.smsId == '1202');
  expectEq('system id: address kept', true, (rRef?.address ?? '').endsWith('AXISBK-S'));
  expectEq('long-press ping- id', 'ping-m-test-1', pingSmsRefOfNote(parsePingExport(sample('long-press.json')).rows.first.note)?.smsId);
  // old notes (written before the sender marker existed)
  expectEq('old note, system id', '77', pingSmsRefOfNote('Ping SMS #77 Ping SMS key 20261026-abc')?.smsId);
  expectEq('old note, n-id has no sender: cannot be found', null,
      pingSmsRefOfNote('Ping SMS #n1793000000000-c8c2791f Ping SMS key 20261026-abc'));
  expectEq('PhonePe entry is not an SMS', null, pingSmsRefOfNote('Ping SMS #pp-123 Ping SMS key x'));
  expectEq('no marker', null, pingSmsRefOfNote('lunch with friends'));
  // the sender marker is never written for a phone number (Ping does not send those anyway)
  final PingImport personal = parsePingExport(jsonEncode({
    'type': 'paddhu-sms-export',
    'sms': [
      {'id': '5', 'address': '+919999999999', 'body': single.rows.isEmpty ? '' : 'INR 50.00 debited A/c no. XX1234 07-11-26, 07:52:58 UPI/P2M/000000000001/Test shop', 'date': 1793000000000}
    ]
  }));
  for (final r in personal.rows) {
    expectEq('no sender marker for a phone number', false, r.note.contains(kPingFromMarker));
  }
  // saving the same message twice stays one message: the duplicate markers are unchanged by the sender marker
  expectEq('id marker still first', true, RegExp(r'Ping SMS #([\w-]+) Ping SMS key ([\w-]+)').hasMatch(singleNote));

  // 5. a file that is not a Ping export is refused
  var refused = false;
  try {
    parsePingExport('{"type":"something-else","sms":[]}');
  } on FormatException {
    refused = true;
  }
  expectEq('wrong type is refused', true, refused);

  if (failures == 0) {
    print('PASS  contract ($checks checks)');
  } else {
    print('FAIL  $failures of $checks checks');
    exit(1);
  }
}
