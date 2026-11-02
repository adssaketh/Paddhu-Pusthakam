// Checks that lib/struct/instrumentParser.dart gives the same answers as Ping's instrument.ts.
//
// Run from the project root (no extra packages needed):
//   dart run tool/check_instruments.dart
//
// It reads:
//   test/fixtures/instrument_synthetic.json  - small, fake-digit cases, safe to commit
//   test/fixtures/instrument_golden.json     - every transaction SMS from your real backup, with the
//                                              key Ping gives it (skipped when the file is missing;
//                                              keep it out of git, it holds your real messages)
// Exit code is 0 when everything matches and 1 otherwise.

import 'dart:convert';
import 'dart:io';

import '../lib/struct/instrumentParser.dart';

int _failures = 0;

bool _runFile(String path, {required bool optional}) {
  final file = File(path);
  if (!file.existsSync()) {
    if (optional) {
      print('SKIP  $path (not found)');
      return true;
    }
    print('FAIL  $path (not found)');
    _failures++;
    return false;
  }

  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (data['cases'] as List).cast<Map<String, dynamic>>();

  // The resolver looks at all messages together, so feed them in the file's order, all at once.
  final msgs = [
    for (final c in cases)
      InstrumentMessage(
        id: c['id'].toString(),
        sender: (c['sender'] ?? '') as String,
        text: c['text'] as String,
      ),
  ];
  final got = indexInstruments(msgs);

  var bad = 0;
  var checked = 0;
  for (final c in cases) {
    final id = c['id'].toString();
    final wantKey = c['key'] as String?;
    final gotKey = got[id];
    checked++;

    String? problem;
    if (gotKey != wantKey) {
      problem = 'key: want $wantKey, got $gotKey';
    } else if (gotKey != null) {
      final wantLabel = c['label'] as String?;
      final gotLabel = instrumentLabel(gotKey);
      final wantClosed = c['closed'] as bool? ?? false;
      final gotClosed = isClosedInstrument(gotKey);
      if (gotLabel != wantLabel) {
        problem = 'label: want $wantLabel, got $gotLabel';
      } else if (gotClosed != wantClosed) {
        problem = 'closed: want $wantClosed, got $gotClosed';
      }
    }

    if (problem != null) {
      bad++;
      if (bad <= 15) {
        final text = (c['text'] as String).replaceAll('\n', ' ');
        final shown = text.length > 90 ? '${text.substring(0, 90)}...' : text;
        print('  MISMATCH id=$id sender=${c['sender']}  $problem');
        print('           $shown');
      }
    }
  }

  if (bad == 0) {
    print('PASS  $path ($checked messages)');
    return true;
  }
  print('FAIL  $path ($bad of $checked messages differ)');
  _failures++;
  return false;
}

void main(List<String> args) {
  _runFile('test/fixtures/instrument_synthetic.json', optional: false);
  _runFile('test/fixtures/instrument_golden.json', optional: true);
  if (_failures > 0) {
    exit(1);
  }
  print('All instrument checks passed.');
}
