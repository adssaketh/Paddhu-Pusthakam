// The automatic part of "Ping > Send new bank messages to Paddhu Pusthakam automatically".
//
// While Paddhu Pusthakam is closed, Ping drops each new bank SMS into files/ping_inbox/ through
// PingInboxProvider.java. Every time the app opens (or comes back to the front) [processPingInbox] reads
// that folder and, for each message:
//   - already in Paddhu (same Ping SMS id or same text on the same day): dropped,
//   - confident (autoSmsPolicy.dart): saved straight away,
//   - anything else: kept in files/ping_review/ for the review list (ImportFromPingPage with reviewQueue).
//
// A message is only removed from the inbox after it was saved or moved to the review folder, so nothing
// is lost if the app is closed half way through.

import 'dart:convert';
import 'dart:io';

import 'package:budget/struct/autoSmsPolicy.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
import 'package:budget/struct/phonePeTwins.dart';
import 'package:budget/struct/pingImport.dart';
import 'package:budget/struct/pingSave.dart';
import 'package:budget/database/tables.dart';
import 'package:path_provider/path_provider.dart';

/// Same as INBOX_DIR in PingInboxProvider.java.
const String kPingInboxDirName = 'ping_inbox';

/// Messages waiting for you in the review list.
const String kPingReviewDirName = 'ping_review';

/// What one run did, for the snackbar.
class PingInboxResult {
  const PingInboxResult({
    this.saved = 0,
    this.toReview = 0,
    this.duplicates = 0,
    this.ignored = 0,
    this.failed = 0,
    this.fixedDeposits = 0,
  });

  final int saved;
  final int toReview;
  final int duplicates;

  /// Not a transaction after all (the parser did not accept it).
  final int ignored;

  /// Left in the inbox to try again next time.
  final int failed;

  /// Fixed deposits added from "FD booked" messages.
  final int fixedDeposits;

  bool get didSomething => saved > 0 || toReview > 0 || fixedDeposits > 0;
}

Future<Directory> _supportSubDir(String name) async {
  final Directory base = await getApplicationSupportDirectory();
  return Directory('${base.path}/$name');
}

/// File name safe to use for an SMS id.
String _safeName(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

/// The JSON object of one SMS as Ping sent it, or null when the text is not usable.
/// Ping sends the same format as the date-range export, with one message inside.
List<Map<String, dynamic>> _smsItemsOf(String jsonText) {
  final dynamic decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic> ||
      decoded['type'] != 'paddhu-sms-export' ||
      decoded['sms'] is! List) {
    throw const FormatException('not a Ping export');
  }
  final List<Map<String, dynamic>> items = [];
  for (final dynamic item in decoded['sms'] as List) {
    if (item is Map) items.add(Map<String, dynamic>.from(item));
  }
  return items;
}

Map<String, dynamic>? _itemWithId(List<Map<String, dynamic>> items, String id) {
  for (final Map<String, dynamic> item in items) {
    if ((item['id'] ?? '').toString() == id) return item;
  }
  return null;
}

/// The export JSON for these SMS items, so the existing parser (parsePingExport) can read them.
String _exportJsonOf(List<Map<String, dynamic>> items) => jsonEncode({
      'app': 'Ping',
      'type': 'paddhu-sms-export',
      'version': 1,
      'sms': items,
    });

/// How many messages are waiting in the review list.
Future<int> pendingReviewCount() async {
  try {
    final Directory dir = await _supportSubDir(kPingReviewDirName);
    if (!await dir.exists()) return 0;
    int n = 0;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) n++;
    }
    return n;
  } catch (_) {
    return 0;
  }
}

/// The review list as one export JSON (newest and oldest mixed, the page sorts them), or null when empty.
Future<String?> readReviewQueueAsExport() async {
  final Directory dir = await _supportSubDir(kPingReviewDirName);
  if (!await dir.exists()) return null;
  final List<Map<String, dynamic>> items = [];
  await for (final FileSystemEntity e in dir.list()) {
    if (e is! File || !e.path.endsWith('.json')) continue;
    try {
      // each review file holds one SMS item, exactly as Ping sent it (see processPingInbox)
      final dynamic item = jsonDecode(await e.readAsString());
      if (item is Map && (item['id'] ?? '').toString().isNotEmpty) {
        items.add(Map<String, dynamic>.from(item));
      } else {
        throw const FormatException('not an SMS item');
      }
    } catch (_) {
      // an unreadable file would block the whole list: remove it
      try {
        await e.delete();
      } catch (_) {}
    }
  }
  if (items.isEmpty) return null;
  return _exportJsonOf(items);
}

/// Removes these messages from the review list (after they were saved, or when you dismiss them).
Future<void> removeFromReviewQueue(Iterable<String> smsIds) async {
  final Directory dir = await _supportSubDir(kPingReviewDirName);
  for (final String id in smsIds) {
    final File f = File('${dir.path}/${_safeName(id)}.json');
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

bool _running = false;

/// Reads the inbox and handles every message in it. Safe to call often: it does nothing when another run
/// is still going, when the folder is empty, or when Paddhu Pusthakam has no wallet yet.
Future<PingInboxResult> processPingInbox() async {
  if (_running) return const PingInboxResult();
  _running = true;
  try {
    final Directory inbox = await _supportSubDir(kPingInboxDirName);
    if (!await inbox.exists()) return const PingInboxResult();

    final List<File> files = [];
    await for (final FileSystemEntity e in inbox.list()) {
      if (e is File && e.path.endsWith('.json')) files.add(e);
    }
    if (files.isEmpty) return const PingInboxResult();
    files.sort((a, b) => a.path.compareTo(b.path));

    final PingSaver saver = PingSaver();
    if (!await saver.init()) return const PingInboxResult();

    final List<Set<String>> existing = await existingPingMarkers();
    final Set<String> savedIds = existing[0];
    final Set<String> savedKeys = existing[1];

    final Directory review = await _supportSubDir(kPingReviewDirName);
    int saved = 0, toReview = 0, duplicates = 0, ignored = 0, failed = 0, fixedDeposits = 0;

    for (final File file in files) {
      // 1. Read it. A file that is not a Ping message at all is thrown away, it can never work.
      final List<Map<String, dynamic>> items;
      final PingImport parsed;
      try {
        items = _smsItemsOf(await file.readAsString());
        parsed = parsePingExport(_exportJsonOf(items));
      } catch (_) {
        try {
          await file.delete();
        } catch (_) {}
        continue;
      }

      // A fixed deposit being booked is added to the Fixed deposits page. The message itself stays in the
      // list below: when it also says money was debited, that part is still saved as a transaction.
      for (final Map<String, dynamic> item in items) {
        try {
          final DateTime date = DateTime.fromMillisecondsSinceEpoch(
              item['date'] is num ? (item['date'] as num).toInt() : DateTime.now().millisecondsSinceEpoch);
          final FdSmsParse? fd = parseFixedDepositSms(
            body: (item['body'] ?? '').toString(),
            sender: (item['address'] ?? '').toString(),
            smsDate: date,
            smsId: (item['id'] ?? '').toString(),
          );
          if (fd != null && await addFixedDepositIfNew(fd.deposit)) fixedDeposits++;
        } catch (_) {}
      }

      // Messages the parser skipped (not a payment, card bill acknowledgement...) simply disappear.
      ignored += items.length - parsed.rows.length;

      // 2. Save or queue each message. If something fails here the file stays for the next run; the
      //    messages already saved are recognised as duplicates then.
      try {
        for (final PingImportRow row in parsed.rows) {
          if (savedIds.contains(row.smsId) || savedKeys.contains(row.contentKey)) {
            duplicates++;
            continue;
          }

          // already in Paddhu from a PhonePe screenshot / statement: only add the SMS markers to it
          if (await claimPhonePeTwinForSms(row)) {
            savedIds.add(row.smsId);
            savedKeys.add(row.contentKey);
            duplicates++;
            continue;
          }

          final TransactionCategory? learned = await learnedCategoryFor(row);
          final AutoSmsDecision decision =
              decideAutoSave(row, learnedCategoryPk: learned?.categoryPk);

          if (decision.isSave) {
            await saver.save(row, categoryPkOverride: learned?.categoryPk);
            savedIds.add(row.smsId);
            savedKeys.add(row.contentKey);
            saved++;
          } else {
            // Keep the original SMS (not the parsed row), so the review list parses it again with
            // whatever rules are current when you open it.
            final Map<String, dynamic>? item = _itemWithId(items, row.smsId);
            if (item != null) {
              await review.create(recursive: true);
              final File out =
                  File('${review.path}/${_safeName(row.smsId)}.json');
              await out.writeAsString(jsonEncode(item), flush: true);
              toReview++;
            }
          }
        }
        await file.delete();
      } catch (_) {
        failed++;
      }
    }
    return PingInboxResult(
      saved: saved,
      toReview: toReview,
      duplicates: duplicates,
      ignored: ignored,
      failed: failed,
      fixedDeposits: fixedDeposits,
    );
  } catch (_) {
    return const PingInboxResult();
  } finally {
    _running = false;
  }
}
