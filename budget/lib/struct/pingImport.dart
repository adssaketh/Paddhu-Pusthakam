// Reads the file that Ping shares (Settings > Send to Paddhu Pusthakam) and turns it into the rows
// shown on the import screen.
//
// Ping only sends bank and payment SMS of the date range you chose. Each SMS is read again here with
// the same parser the notification feature uses (smsTransactionParser.dart), so Paddhu and Ping agree
// on what an SMS means. Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

import 'dart:convert';

import 'instrumentParser.dart';
import 'knownAccounts.dart';
import 'smsTransactionParser.dart';

/// Marks a transaction as coming from a Ping SMS, kept in its note. Used to skip duplicates when the
/// same range is imported twice. The SMS id is Android's own id, stable on the same phone.
const String kPingNoteMarker = 'Ping SMS #';

/// Second marker: the same SMS can arrive twice, once from the "Add to Paddhu" button (which has no Android
/// SMS id) and once from a date range, so the text of the message (and its day) is also remembered.
const String kPingKeyMarker = 'Ping SMS key ';

/// File name used when the shared file is copied into the app's cache (ShareReceiverActivity.java).
const String kPingImportFileName = 'ping-import.json';

class PingImportRow {
  const PingImportRow({
    required this.smsId,
    required this.contentKey,
    required this.sender,
    required this.date,
    required this.amount,
    required this.isExpense,
    required this.title,
    required this.merchant,
    required this.categoryLabel,
    required this.categoryPk,
    required this.accountName,
    required this.walletName,
    required this.closed,
    required this.tickByDefault,
    this.knownAccount = false,
  });

  final String smsId;

  /// Day plus a hash of the message text, see kPingKeyMarker.
  final String contentKey;
  final String sender;
  final DateTime date;

  /// Always positive, see isExpense.
  final double amount;
  final bool isExpense;
  final String title;
  final String merchant;

  /// Rule-based label ('dining', 'groceries', ...), '' when none was suggested.
  final String categoryLabel;

  /// Paddhu default categoryPk for the label, null when the label has none.
  final String? categoryPk;

  /// Your name for the account / card, or "SBI ••6919" style, or null when the SMS does not say.
  final String? accountName;

  /// Wallet this transaction is imported into (created when it does not exist yet).
  final String walletName;
  final bool closed;
  final bool tickByDefault;

  /// true when the account / card is in your own list (knownAccounts.dart). Only those are saved
  /// automatically, see autoSmsPolicy.dart.
  final bool knownAccount;

  /// Text stored in the transaction's note: the account, then the duplicate marker.
  String get note {
    final account = accountName;
    final head = account == null ? '' : '$account${closed ? ' (closed)' : ''}\n';
    return '$head$kPingNoteMarker$smsId $kPingKeyMarker$contentKey';
  }
}

class PingImport {
  const PingImport({
    required this.rows,
    required this.skipped,
    this.from,
    this.to,
  });

  /// Newest first.
  final List<PingImportRow> rows;

  /// Messages in the file that are not importable (not a transaction, or a credit card bill
  /// acknowledgement whose bank-side debit is a separate SMS).
  final int skipped;
  final DateTime? from;
  final DateTime? to;
}

/// A bank debit that pays a credit card bill. The card's own spends are separate rows, so with cards
/// and bank accounts sharing one wallet this would count the same money twice: shown, but not ticked.
final RegExp _cardBillDebitRe = RegExp(
  r'credit ?card payment|cc ?bill|billpay|card bill|sbi card +payment|cc payment',
  caseSensitive: false,
);

String _two(int n) => n.toString().padLeft(2, '0');

/// FNV-1a, the same on every run (Dart's String.hashCode is not).
String _stableHash(String text) {
  int h = 0x811c9dc5;
  for (final int unit in text.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

String _contentKey(String body, DateTime date) {
  final String normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return '${date.year}${_two(date.month)}${_two(date.day)}-${_stableHash(normalized)}';
}

String _walletForUnknown(String instrumentKey) {
  final parts = instrumentKey.split(':');
  final kind = parts.length > 1 ? parts[1] : '';
  // The SMS does not say which account it is, or the sender is not a bank or wallet we know by
  // name: keep those together instead of guessing.
  if (kind.isEmpty || kind == 'unknown') return 'Unassigned';
  return knownIssuerLabelOf(instrumentKey) ?? 'Unassigned';
}

DateTime? _dateFromMs(dynamic value) {
  final int? ms = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Throws a FormatException (with a readable message) when the text is not a Ping export.
PingImport parsePingExport(String jsonText) {
  final dynamic decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic> ||
      decoded['type'] != 'paddhu-sms-export' ||
      decoded['sms'] is! List) {
    throw const FormatException(
        'This file is not a Ping export for Paddhu Pusthakam.');
  }

  final rows = <PingImportRow>[];
  final seen = <String>{};
  var skipped = 0;

  for (final dynamic item in decoded['sms'] as List) {
    if (item is! Map) {
      skipped++;
      continue;
    }
    final String id = (item['id'] ?? '').toString();
    final String sender = (item['address'] ?? '').toString();
    final String body = (item['body'] ?? '').toString();
    final DateTime? date = _dateFromMs(item['date']);
    if (id.isEmpty || date == null) {
      skipped++;
      continue;
    }
    if (!seen.add(id)) continue;

    final ParsedSmsTransaction? parsed = parseSmsTransaction(sender, body);
    if (parsed == null || parsed.cardPayment || parsed.amount <= 0) {
      skipped++;
      continue;
    }

    final KnownAccount? known = knownAccountFor(parsed.instrumentKey);
    rows.add(PingImportRow(
      smsId: id,
      contentKey: _contentKey(body, date),
      sender: sender,
      date: date,
      amount: parsed.amount,
      isExpense: parsed.isExpense,
      title: parsed.title,
      merchant: parsed.merchant,
      categoryLabel: parsed.category,
      categoryPk: parsed.categoryPk,
      accountName: known?.name ?? parsed.instrumentName,
      walletName: known != null && known.wallet.isNotEmpty
          ? known.wallet
          : _walletForUnknown(parsed.instrumentKey),
      // Only your own list decides: old Federal UPI SMS carry no account number, so they are not
      // marked closed (the active Jupiter account may send the same format).
      closed: known?.closed ?? false,
      knownAccount: known != null,
      tickByDefault: (known?.tickByDefault ?? true) &&
          !(parsed.isExpense && _cardBillDebitRe.hasMatch(body)),
    ));
  }

  rows.sort((a, b) => b.date.compareTo(a.date));
  return PingImport(
    rows: rows,
    skipped: skipped,
    from: _dateFromMs(decoded['from']),
    to: _dateFromMs(decoded['to']),
  );
}
