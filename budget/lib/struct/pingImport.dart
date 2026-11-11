// Reads the file that Ping shares (Settings > Send to Paddhu Pusthakam) and turns it into the rows
// shown on the import screen.
//
// Ping only sends bank and payment SMS of the date range you chose. Each SMS is read again here with
// the same parser the notification feature uses (smsTransactionParser.dart), so Paddhu and Ping agree
// on what an SMS means. Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

import 'dart:convert';

import 'cardDues.dart';
import 'fixedDeposit.dart';
import 'instrumentParser.dart';
import 'knownAccounts.dart';
import 'smsTransactionParser.dart';

/// Marks a transaction as coming from a Ping SMS, kept in its note. Used to skip duplicates when the
/// same range is imported twice. The SMS id is Android's own id, stable on the same phone.
const String kPingNoteMarker = 'Ping SMS #';

/// Second marker: the same SMS can arrive twice, once from the "Add to Paddhu" button (which has no Android
/// SMS id) and once from a date range, so the text of the message (and its day) is also remembered.
const String kPingKeyMarker = 'Ping SMS key ';

/// Third marker (additive, new notes only): the raw sender header of the message (for example `AX-AXISBK-S`),
/// so "View SMS in Ping" can find the message again (contract/ping-paddhu/SPEC.md section 8). Only written
/// for business-style headers (letters, digits, `.`, `_`, `&`, `-`); a phone number is never stored here.
const String kPingFromMarker = 'Ping SMS from ';

final RegExp _safeSenderRe = RegExp(r'^[A-Za-z0-9._&-]{1,32}$');

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
    this.extraNote = '',
    this.brandKey = '',
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

  /// Extra line for the note (for example the PhonePe details), before the duplicate markers.
  final String extraNote;

  /// Ping's `brandKey` for the sender (logo key, for example `axisbank`), '' when Ping sent none or an invalid one.
  final String brandKey;

  /// Text stored in the transaction's note: the account, then the duplicate marker.
  String get note {
    final account = accountName;
    final head = account == null ? '' : '$account${closed ? ' (closed)' : ''}\n';
    final extra = extraNote.isEmpty ? '' : '$extraNote\n';
    final String from =
        _safeSenderRe.hasMatch(sender) ? ' $kPingFromMarker$sender' : '';
    return '$head$extra$kPingNoteMarker$smsId $kPingKeyMarker$contentKey$from';
  }
}

class PingImport {
  const PingImport({
    required this.rows,
    required this.skipped,
    this.from,
    this.to,
    this.cardDues = const [],
  });

  /// Credit card spends, refunds and bill payments found in the file (see cardDues.dart).
  final List<CardDueEntry> cardDues;

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

/// The content key of a message (see kPingKeyMarker): shared contract with Ping, checked against
/// contract/ping-paddhu/golden/ids-and-keys.json by test/ping_contract_test.dart.
String pingContentKey(String body, DateTime date) => _contentKey(body, date);

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
  final cardDues = <CardDueEntry>[];
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
    if (parsed != null && parsed.amount > 0) {
      final CardDueEntry? due = _cardDueOf(parsed, body, date);
      if (due != null) cardDues.add(due);
    }
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
      brandKey: _brandKeyOf(item['brandKey']),
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
    cardDues: cardDues,
  );
}

/// `brandKey` as the contract defines it (lower-case letters and digits), else ''. Only used to ask Ping for a logo.
String _brandKeyOf(dynamic value) {
  final String v = (value ?? '').toString();
  return RegExp(r'^[a-z0-9]{1,40}$').hasMatch(v) ? v : '';
}

/// The effect of this message on what you owe on a credit card, or null when it is not about a credit card.
/// The id comes from the day and text of the message, so the same SMS counts once however it arrives.
CardDueEntry? _cardDueOf(ParsedSmsTransaction parsed, String body, DateTime date) {
  final KnownAccount? known = knownAccountFor(parsed.instrumentKey);
  if (known != null && known.closed) return null;
  final bool credit = parsed.cardPayment ||
      parsed.instrumentKey.contains(':credit_card') ||
      (known != null && RegExp(r'credit card|emi card', caseSensitive: false).hasMatch(known.name));
  if (!credit) return null;
  final String kind = parsed.cardPayment ? 'payment' : (parsed.isExpense ? 'spend' : 'refund');
  return CardDueEntry(
    id: 'cd-${_contentKey(body, date)}',
    card: (known != null && known.dueCard.isNotEmpty) ? known.dueCard : (known?.name ?? parsed.instrumentName ?? parsed.instrumentKey),
    kind: kind,
    amount: parsed.amount,
    date: date,
    note: parsed.title,
  );
}

/// The fixed deposit one SMS item of a Ping export announces, or null (A5.2 item 4 of the Ping <-> Paddhu
/// contract, contract/ping-paddhu/SPEC.md section 2).
///
/// Ping (6a onwards) writes `kind` into each item: `fixed_deposit` is routed to the fixed deposit reader,
/// `transaction` is not tried (Ping already found it is no deposit booking). When `kind` is missing or has a
/// value this app does not know (an older Ping, a newer Ping), Paddhu's own detection decides, exactly as
/// before. The reader itself ([parseFixedDepositSms]) always has the last word.
FdSmsParse? fixedDepositOfPingItem(Map item) {
  final String kind = (item['kind'] ?? '').toString();
  if (kind == 'transaction') return null;
  final DateTime date = _dateFromMs(item['date']) ?? DateTime.now();
  return parseFixedDepositSms(
    body: (item['body'] ?? '').toString(),
    sender: (item['address'] ?? '').toString(),
    smsDate: date,
    smsId: (item['id'] ?? '').toString(),
  );
}

/// Every fixed deposit announced in a Ping export (date-range file, share, or review list), see
/// [fixedDepositOfPingItem]. Throws a FormatException when the text is not a Ping export.
List<FdSmsParse> parsePingFixedDeposits(String jsonText) {
  final dynamic decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic> ||
      decoded['type'] != 'paddhu-sms-export' ||
      decoded['sms'] is! List) {
    throw const FormatException(
        'This file is not a Ping export for Paddhu Pusthakam.');
  }
  final found = <FdSmsParse>[];
  final seen = <String>{};
  for (final dynamic item in decoded['sms'] as List) {
    if (item is! Map) continue;
    final String id = (item['id'] ?? '').toString();
    if (id.isNotEmpty && !seen.add(id)) continue;
    final FdSmsParse? fd = fixedDepositOfPingItem(item);
    if (fd != null) found.add(fd);
  }
  return found;
}

/// What "View SMS in Ping" sends to Ping (action com.ping.sms.action.OPEN_SMS): Ping needs [smsId], or
/// [address] together with [date] (contract/ping-paddhu/SPEC.md section 8).
class PingSmsRef {
  const PingSmsRef({this.smsId, this.address, this.date});
  final String? smsId;
  final String? address;

  /// Milliseconds since the epoch.
  final int? date;

  @override
  String toString() => 'PingSmsRef($smsId, $address, $date)';
}

/// Finds the Ping message a transaction was made from, from its note, or null when the note does not say
/// enough to find it again (a PhonePe entry, a transaction not from Ping, an older note of an
/// automatically sent message whose sender was not stored).
///
/// - The phone's SMS `_id` (all digits) or `ping-<id>`: sent as `smsId` (with the sender when known).
/// - `n<timestamp>-<hash>` (the notification button and automatic send, which have no phone `_id`): the
///   timestamp in the id is the message's date, so `date` plus the stored sender is used.
PingSmsRef? pingSmsRefOfNote(String note) {
  final RegExpMatch? idMatch = RegExp(r'Ping SMS #([\w-]+)').firstMatch(note);
  if (idMatch == null) return null;
  final String id = idMatch.group(1)!;
  if (id.startsWith('pp-')) return null;
  final String? address =
      RegExp(r'Ping SMS from ([A-Za-z0-9._&-]{1,32})').firstMatch(note)?.group(1);
  final RegExpMatch? n = RegExp(r'^n(\d{10,15})-[0-9a-f]{1,8}$').firstMatch(id);
  if (n != null) {
    if (address == null) return null;
    return PingSmsRef(address: address, date: int.parse(n.group(1)!));
  }
  if (id.length > 40) return null;
  return PingSmsRef(smsId: id, address: address);
}
