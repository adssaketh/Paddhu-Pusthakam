// Reads PhonePe payments from three places and turns each into a PingImportRow, so they go through the same
// review screen as the bank SMS:
//   - a screenshot of the "Transaction Successful" page (text read by the phone, see phonePeImport.dart),
//   - a PhonePe statement PDF (text pulled out of the PDF),
//   - a PhonePe statement CSV.
//
// Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

import 'knownAccounts.dart';
import 'pingImport.dart';
import 'smsTransactionParser.dart';

/// Written in the note of every transaction that came from PhonePe. Used to find them again.
const String kPhonePeNoteMarker = 'PhonePe';

class PhonePeEntry {
  const PhonePeEntry({
    required this.amount,
    required this.isExpense,
    required this.party,
    required this.date,
    this.txnId = '',
    this.utr = '',
    this.upiId = '',
    this.message = '',
    this.accountDigits = '',
    this.app = 'PhonePe',
    this.amountUnconfirmed = false,
  });

  /// Which app the payment was made with ('PhonePe', 'Paytm', 'Google Pay', 'BHIM', 'CRED', ...).
  final String app;

  /// True when the amount was taken from a line of digits because no rupee sign (or Rs / INR) was found
  /// in the picture. The rupee sign is easily read as another character, even as a digit (a "7"), and then
  /// that digit would be part of the amount, so such an amount has to be checked.
  final bool amountUnconfirmed;

  /// Always positive.
  final double amount;
  final bool isExpense;

  /// Who was paid, or who paid you.
  final String party;

  /// Date and, when known, the time.
  final DateTime date;
  final String txnId;
  final String utr;
  final String upiId;

  /// The message typed with the payment.
  final String message;

  /// Digits of the account that was debited / credited, as far as they are shown ("566372").
  final String accountDigits;
}

// ---------------------------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------------------------

const List<String> _monthAbbr = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
];

int? _month(String s) {
  final int i = _monthAbbr.indexOf(s.toLowerCase().substring(0, 3));
  return i < 0 ? null : i + 1;
}

double? _money(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(',', '').trim());
}

/// The most one payment can be. A UPI payment is far below this; a bigger "amount" is a transaction id, a
/// UTR or some other long number that was read as money, and is never taken as the amount.
const double kMaxPlausiblePaymentAmount = 10000000;

double? _plausibleMoney(String? s) {
  final double? v = _money(s);
  return v != null && v > 0 && v <= kMaxPlausiblePaymentAmount ? v : null;
}

/// The first amount written with a rupee sign (or Rs / INR) that can be an amount.
double? _firstPlausibleAmount(String t) {
  for (final RegExpMatch m in _amountRe.allMatches(t)) {
    final double? v = _plausibleMoney(m.group(1));
    if (v != null) return v;
  }
  return null;
}

/// The amount written with a rupee sign (or Rs / INR). A payment page shows it more than once (at the top
/// and again under "Debited from"), so the value found most often wins and the first one found decides a
/// tie. Numbers that cannot be an amount (ids, UTRs) are skipped.
double? _amountFromText(String t) {
  final Map<double, int> counts = {};
  final List<double> order = [];
  for (final RegExpMatch m in _amountRe.allMatches(t)) {
    final double? v = _plausibleMoney(m.group(1));
    if (v == null) continue;
    if (!counts.containsKey(v)) order.add(v);
    counts[v] = (counts[v] ?? 0) + 1;
  }
  if (order.isEmpty) return null;
  double best = order.first;
  for (final double v in order) {
    if (counts[v]! > counts[best]!) best = v;
  }
  return best;
}

({int hour, int minute})? _time(String? h, String? m, String? ap) {
  if (h == null || m == null) return null;
  int hour = int.parse(h);
  final int minute = int.parse(m);
  if (ap != null) {
    final bool pm = ap.toLowerCase() == 'pm';
    if (hour == 12) hour = 0;
    if (pm) hour += 12;
  }
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

String _tidy(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _titleCase(String s) {
  if (s == s.toUpperCase() || s == s.toLowerCase()) {
    return s
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w.substring(0, 1).toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
  return s;
}

final RegExp _amountRe =
    RegExp(r'(?:₹|\b(?:Rs\.?|INR))\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
final RegExp _upiRe = RegExp(r'\b([\w.\-]{2,}@[a-z][a-z0-9]{1,})\b', caseSensitive: false);
final RegExp _utrRe = RegExp(r'UTR\s*(?:No\.?|Number)?\s*[:\-]?\s*(\d{9,})', caseSensitive: false);
final RegExp _accountRe = RegExp(
    r'(?:Debited from|Credited to|Paid by|Received in|Credited in)\s*[:\-]?\s*[\n ]*([Xx*•]{2,}\s*\d{3,8})',
    caseSensitive: false);

String _digitsOf(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

// ---------------------------------------------------------------------------------------------
// Screenshot ("Transaction Successful" page)
// ---------------------------------------------------------------------------------------------

final RegExp _shotDateRe = RegExp(
    r'(\d{1,2}):(\d{2})\s*([ap]m)?\s+on\s+(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})',
    caseSensitive: false);
final RegExp _avatarRe = RegExp(r'^[A-Z]{1,3}$');
final RegExp _moneyOnlyRe = RegExp(r'^(?:₹|Rs\.?|INR)?\s*[\d,]+(?:\.\d+)?$', caseSensitive: false);
final RegExp _labelRe = RegExp(
    r'^(transfer details|message|phonepe transaction id|debited from|credited to|paid to|received from|utr|powered by|transaction (?:successful|failed|pending)|bank reference)',
    caseSensitive: false);

/// When the rupee sign was read as some other character ("T950", "?950", "% 950"): lines that are only a
/// short number, with at most one stray character in front. The amount is shown twice on the screen, so the
/// value that appears most often wins. Numbers right after "Message" or an id label are skipped.
double? _amountFromLooseLines(List<String> lines) {
  final RegExp loose = RegExp(r'^[^\dA-Za-z]?[A-Za-z]?\s*(\d{1,3}(?:,\d{2,3})*(?:\.\d{1,2})?|\d{1,7}(?:\.\d{1,2})?)$');
  final Map<double, int> counts = {};
  for (int i = 0; i < lines.length; i++) {
    if (i > 0 && RegExp(r'^(message|phonepe transaction id|utr|bank reference|order id)', caseSensitive: false).hasMatch(lines[i - 1])) continue;
    final RegExpMatch? m = loose.firstMatch(lines[i]);
    String? raw = m?.group(1);
    // The rupee sign itself is often read as a "7" ("₹286" becomes "7286"). A real amount of a thousand or
    // more is written with a comma ("₹7,286") or has decimals, so a bare run of four or more digits that
    // starts with 7 and has no rupee sign is a rupee sign read as a 7: that first digit is dropped.
    if (raw != null && raw.length >= 4 && raw.startsWith('7') && RegExp(r'^\d+$').hasMatch(raw)) {
      raw = raw.substring(1);
    }
    final double? v = _plausibleMoney(raw);
    if (v != null) counts[v] = (counts[v] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  double best = counts.keys.first;
  for (final MapEntry<double, int> e in counts.entries) {
    if (e.value > counts[best]!) best = e.key;
  }
  return best;
}

/// Reads the text of a PhonePe "Transaction Successful" screen. null when it is not one, or when the amount
/// or the date cannot be found (nothing is guessed).
PhonePeEntry? parsePhonePeScreenshotText(String text) {
  final String t = text.replaceAll('\r', '');
  if (!RegExp(r'transaction successful|payment successful|money sent|paid to|received from', caseSensitive: false).hasMatch(t)) {
    return null;
  }
  if (RegExp(r'transaction (?:failed|pending)|payment (?:failed|pending)', caseSensitive: false).hasMatch(t) &&
      !RegExp(r'successful', caseSensitive: false).hasMatch(t)) {
    return null;
  }

  final RegExpMatch? dm = _shotDateRe.firstMatch(t);
  if (dm == null) return null;
  final int? mo = _month(dm.group(5)!);
  final tm = _time(dm.group(1), dm.group(2), dm.group(3));
  if (mo == null) return null;
  final DateTime date = DateTime(int.parse(dm.group(6)!), mo, int.parse(dm.group(4)!), tm?.hour ?? 0, tm?.minute ?? 0);

  final List<String> lines =
      t.split('\n').map(_tidy).where((l) => l.isNotEmpty).toList();

  double? amount = _amountFromText(t);
  final bool amountUnconfirmed = amount == null;
  amount ??= _amountFromLooseLines(lines);
  if (amount == null || amount <= 0) return null;

  final bool received = RegExp(r'received from|credited to', caseSensitive: false).hasMatch(t) &&
      !RegExp(r'paid to|debited from', caseSensitive: false).hasMatch(t);

  // who: the first real line after "Paid to" / "Received from"
  String party = '';
  for (int i = 0; i < lines.length && party.isEmpty; i++) {
    final RegExpMatch? m = RegExp(r'^(?:paid to|received from)\s*(.*)$', caseSensitive: false).firstMatch(lines[i]);
    if (m == null) continue;
    final List<String> candidates = [if (m.group(1)!.isNotEmpty) m.group(1)!, ...lines.skip(i + 1).take(5)];
    for (final String c0 in candidates) {
      String c = c0.replaceAll(_amountRe, '').trim();
      if (c.isEmpty || _avatarRe.hasMatch(c) || _moneyOnlyRe.hasMatch(c) || _labelRe.hasMatch(c)) continue;
      if (_upiRe.hasMatch(c) && c.contains('@') && !c.contains(' ')) continue; // the UPI id line
      party = c;
      break;
    }
  }

  // the UPI id (the one that is not PhonePe's own)
  String upi = '';
  for (final RegExpMatch m in _upiRe.allMatches(t)) {
    upi = m.group(1)!;
    break;
  }

  // the message typed with the payment
  String message = '';
  for (int i = 0; i < lines.length; i++) {
    if (RegExp(r'^message$', caseSensitive: false).hasMatch(lines[i]) && i + 1 < lines.length) {
      final String next = lines[i + 1];
      if (!_labelRe.hasMatch(next)) message = next;
      break;
    }
  }

  final String txn = RegExp(r'PhonePe Transaction ID\s*[:\-]?\s*\n?\s*([A-Z0-9]{10,})', caseSensitive: false)
          .firstMatch(t)
          ?.group(1) ??
      RegExp(r'\b(T\d{16,})\b').firstMatch(t)?.group(1) ??
      '';
  final String utr = _utrRe.firstMatch(t)?.group(1) ?? '';
  final String account = _digitsOf(_accountRe.firstMatch(t)?.group(1));

  return PhonePeEntry(
    amount: amount,
    amountUnconfirmed: amountUnconfirmed,
    isExpense: !received,
    party: _titleCase(party),
    date: date,
    txnId: txn,
    utr: utr,
    upiId: upi,
    message: message,
    accountDigits: account,
  );
}


// ---------------------------------------------------------------------------------------------
// Screenshots of other UPI apps (Paytm, Google Pay, BHIM, CRED, MobiKwik and similar)
// ---------------------------------------------------------------------------------------------

final RegExp _anyDateRe = RegExp(
    r"(?<!\d)(\d{1,2})(?:st|nd|rd|th)?[ \t\-/]*([A-Za-z]{3})[a-z]*\.?,?[ \t]*['’]?[ \t]*(\d{4}|\d{2})\b");
final RegExp _anyTimeRe = RegExp(r'(\d{1,2}):(\d{2})\s*([ap]\.?m)?', caseSensitive: false);
final RegExp _anyRefRe = RegExp(
    r'(?:UPI\s*Ref(?:erence)?\s*(?:No\.?|Number)?|UPI\s*transaction\s*ID|Transaction\s*ID)[\s:\-]*(\d{9,})',
    caseSensitive: false);
final RegExp _maskedAccountRe = RegExp(r'[Xx*•]{2,}\s*(\d{2,8})\b');
final RegExp _bankDashAccountRe = RegExp(r'\bbank\s*[-–—]\s*(\d{4})\b', caseSensitive: false);

String _appOf(String t) {
  final String l = t.toLowerCase();
  if (l.contains('paytm')) return 'Paytm';
  if (l.contains('google pay') || l.contains('google transaction')) return 'Google Pay';
  if (l.contains('bhim')) return 'BHIM';
  if (l.contains('mobikwik')) return 'MobiKwik';
  if (RegExp(r'\bcred\b', caseSensitive: false).hasMatch(t)) return 'CRED';
  if (l.contains('amazon pay')) return 'Amazon Pay';
  return 'UPI app';
}

bool _stopsName(String l) =>
    l.contains('@') ||
    _amountRe.hasMatch(l) ||
    _moneyOnlyRe.hasMatch(l) ||
    RegExp(r'^(upi|from|completed|paid|banking|transaction|remarks|debited|message|google)', caseSensitive: false).hasMatch(l);

String _partyOfOtherApp(List<String> lines) {
  for (int i = 0; i < lines.length; i++) {
    if (RegExp(r'^banking name$', caseSensitive: false).hasMatch(lines[i]) && i + 1 < lines.length) {
      return lines[i + 1];
    }
  }
  for (int i = 0; i < lines.length; i++) {
    final RegExpMatch? m = RegExp(r'^To(?=[\s:]|$)\s*:?\s*(.*)$').firstMatch(lines[i]);
    if (m == null || RegExp(r'^upi\b', caseSensitive: false).hasMatch(m.group(1)!)) continue;
    final List<String> parts = [if (m.group(1)!.isNotEmpty) m.group(1)!];
    int extra = 0;
    for (int j = i + 1; j < lines.length && extra < 3; j++) {
      final String l = lines[j];
      if (_avatarRe.hasMatch(l)) continue;
      if (_stopsName(l)) break;
      parts.add(l);
      extra++;
    }
    final String name = parts.join(' ').trim();
    if (name.isNotEmpty) return name;
  }
  // CRED style: the merchant is the last text line above the amount
  String last = '';
  for (final String l in lines) {
    if (_amountRe.hasMatch(l) || _moneyOnlyRe.hasMatch(l)) break;
    if (RegExp(r'[A-Za-z]{3,}').hasMatch(l) && !l.contains('@')) last = l;
  }
  return last.replaceAll(RegExp(r'[.…]+$'), '').trim();
}

/// Reads the payment-success screen of another UPI app. Null when it does not look like one, or when the
/// amount or the date is missing (nothing is guessed).
PhonePeEntry? parseOtherUpiScreenshotText(String text) {
  final String t = text.replaceAll('\r', '');
  final bool success = RegExp(r'successful|completed|\bpaid\b|payment (?:received|sent)', caseSensitive: false).hasMatch(t);
  final bool failed = RegExp(r'failed|declined|reversed|pending', caseSensitive: false).hasMatch(t);
  if (!success || (failed && !RegExp(r'successful|completed', caseSensitive: false).hasMatch(t))) return null;
  if (!RegExp(r'\bupi\b|@', caseSensitive: false).hasMatch(t)) return null;

  DateTime? day;
  for (final RegExpMatch m in _anyDateRe.allMatches(t)) {
    final int? mo = _month(m.group(2)!);
    if (mo == null) continue;
    int year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    day = DateTime(year, mo, int.parse(m.group(1)!));
    break;
  }
  if (day == null) return null;
  ({int hour, int minute})? tm;
  for (final RegExpMatch m in _anyTimeRe.allMatches(t)) {
    if (m.group(3) == null) continue;
    tm = _time(m.group(1), m.group(2), m.group(3)!.replaceAll('.', ''));
    if (tm != null) break;
  }
  final DateTime date = DateTime(day.year, day.month, day.day, tm?.hour ?? 0, tm?.minute ?? 0);

  final List<String> lines = t.split('\n').map(_tidy).where((l) => l.isNotEmpty).toList();
  double? amount = _amountFromText(t);
  final bool amountUnconfirmed = amount == null;
  amount ??= _amountFromLooseLines(lines);
  if (amount == null || amount <= 0) return null;

  final bool received = RegExp(r'received from|money received', caseSensitive: false).hasMatch(t);
  final String account = _digitsOf(
      (_maskedAccountRe.firstMatch(t) ?? _bankDashAccountRe.firstMatch(t))?.group(1));

  return PhonePeEntry(
    amount: amount,
    amountUnconfirmed: amountUnconfirmed,
    isExpense: !received,
    party: _titleCase(_partyOfOtherApp(lines)),
    date: date,
    utr: _anyRefRe.firstMatch(t)?.group(1) ??
        // two-column pages (BHIM) put other labels between "Transaction ID" and the number
        RegExp(r'^(\d{12})$', multiLine: true).firstMatch(t)?.group(1) ??
        '',
    upiId: _upiRe.firstMatch(t)?.group(1) ?? '',
    accountDigits: account,
    app: _appOf(t),
  );
}

/// PhonePe's own page first, then the other apps' pages.
PhonePeEntry? parseUpiScreenshotText(String text) =>
    parsePhonePeScreenshotText(text) ?? parseOtherUpiScreenshotText(text);

// ---------------------------------------------------------------------------------------------
// Statement PDF (text pulled out of it)
// ---------------------------------------------------------------------------------------------

final RegExp _stmtDateRe = RegExp(
    r'(?:^|\n)\s*(?:([A-Za-z]{3})[a-z]*\s+(\d{1,2}),?\s+(\d{4})|(\d{1,2})\s+([A-Za-z]{3})[a-z]*,?\s+(\d{4}))');
final RegExp _stmtTimeRe = RegExp(r'(\d{1,2}):(\d{2})\s*([AP]M)', caseSensitive: false);
final RegExp _stmtTypeRe = RegExp(r'\b(DEBIT|CREDIT)\b');
final RegExp _stmtPartyRe = RegExp(
    r'(Paid to|Received from|Payment to|Paid for|Refund from|Money sent to|Mobile recharged|Bill paid|Added to wallet|Sent to)\s*(.*)',
    caseSensitive: false);

/// Reads the text of a PhonePe statement. Each payment starts with its date; type (DEBIT / CREDIT), amount,
/// "Paid to ...", transaction id, UTR and the account follow, in whatever order the PDF gives them.
List<PhonePeEntry> parsePhonePeStatementText(String text) {
  final String t = '\n${text.replaceAll('\r', '')}';
  final List<RegExpMatch> starts = _stmtDateRe.allMatches(t).toList();
  final List<PhonePeEntry> out = [];

  for (int i = 0; i < starts.length; i++) {
    final RegExpMatch s = starts[i];
    final String block = t.substring(s.start, i + 1 < starts.length ? starts[i + 1].start : t.length);

    int? mo;
    int day, year;
    if (s.group(1) != null) {
      mo = _month(s.group(1)!);
      day = int.parse(s.group(2)!);
      year = int.parse(s.group(3)!);
    } else {
      mo = _month(s.group(5)!);
      day = int.parse(s.group(4)!);
      year = int.parse(s.group(6)!);
    }
    if (mo == null) continue;
    final RegExpMatch? tmM = _stmtTimeRe.firstMatch(block);
    final tm = tmM == null ? null : _time(tmM.group(1), tmM.group(2), tmM.group(3));
    final DateTime date = DateTime(year, mo, day, tm?.hour ?? 0, tm?.minute ?? 0);

    if (RegExp(r'\bFAILED\b|\bPENDING\b', caseSensitive: false).hasMatch(block)) continue;

    final RegExpMatch? ty = _stmtTypeRe.firstMatch(block);
    // the rupee sign can come out as another character in a PDF: then take the number after DEBIT / CREDIT
    final double? amount = _firstPlausibleAmount(block) ??
        _plausibleMoney(RegExp(r'\b(?:DEBIT|CREDIT)\b\s*[^\d\s]?\s*([\d,]+(?:\.\d{1,2})?)').firstMatch(block)?.group(1));
    if (amount == null || amount <= 0) continue;

    final RegExpMatch? pm = _stmtPartyRe.firstMatch(block);
    bool? isExpense = ty == null ? null : ty.group(1) == 'DEBIT';
    final String prefix = (pm?.group(1) ?? '').toLowerCase();
    isExpense ??= !(prefix.startsWith('received') || prefix.startsWith('refund') || prefix.startsWith('added'));

    String party = '';
    if (pm != null) {
      party = pm.group(2)!.split('\n').first;
      party = party
          .replaceAll(RegExp(r'\b(DEBIT|CREDIT)\b.*$'), '')
          .replaceAll(RegExp(r'Transaction ID.*$', caseSensitive: false), '')
          .replaceAll(_amountRe, '')
          .trim();
    }
    if (party.isEmpty && pm != null) party = pm.group(1)!;

    out.add(PhonePeEntry(
      amount: amount,
      isExpense: isExpense,
      party: _titleCase(_tidy(party)),
      date: date,
      txnId: RegExp(r'Transaction ID\s*[:\-]?\s*([A-Z0-9]{8,})', caseSensitive: false).firstMatch(block)?.group(1) ?? '',
      utr: _utrRe.firstMatch(block)?.group(1) ?? '',
      accountDigits: _digitsOf(_accountRe.firstMatch(block)?.group(1)),
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Statement CSV
// ---------------------------------------------------------------------------------------------

List<List<String>> _splitCsv(String text) {
  final String firstLine = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final String delim = firstLine.split('\t').length > firstLine.split(',').length
      ? '\t'
      : (firstLine.split(';').length > firstLine.split(',').length ? ';' : ',');
  final List<List<String>> rows = [];
  List<String> row = [];
  final StringBuffer cell = StringBuffer();
  bool quoted = false;
  final String s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (int i = 0; i < s.length; i++) {
    final String c = s[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == delim) {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n') {
      row.add(cell.toString());
      cell.clear();
      if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
      row = [];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
  return rows;
}

DateTime? _csvDate(String raw) {
  final String s = _tidy(raw);
  RegExpMatch? m;
  int h = 0, mi = 0;
  final RegExpMatch? t = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?').firstMatch(s);
  if (t != null) {
    final tm = _time(t.group(1), t.group(2), t.group(3));
    if (tm != null) {
      h = tm.hour;
      mi = tm.minute;
    }
  }
  m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (m != null) return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), h, mi);
  m = RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})').firstMatch(s);
  if (m != null) {
    int y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!), h, mi); // day first, as in India
  }
  m = RegExp(r'([A-Za-z]{3})[a-z]*\s+(\d{1,2}),?\s+(\d{4})').firstMatch(s);
  if (m != null && _month(m.group(1)!) != null) {
    return DateTime(int.parse(m.group(3)!), _month(m.group(1)!)!, int.parse(m.group(2)!), h, mi);
  }
  m = RegExp(r'(\d{1,2})[\s\-/]+([A-Za-z]{3})[a-z]*[\s\-/,]+(\d{4})').firstMatch(s);
  if (m != null && _month(m.group(2)!) != null) {
    return DateTime(int.parse(m.group(3)!), _month(m.group(2)!)!, int.parse(m.group(1)!), h, mi);
  }
  return null;
}

int _col(List<String> header, List<RegExp> names) {
  for (final RegExp n in names) {
    for (int i = 0; i < header.length; i++) {
      if (n.hasMatch(header[i])) return i;
    }
  }
  return -1;
}

/// Reads a PhonePe statement saved as CSV. The columns are found by their names (date, details, type,
/// amount or debit / credit, transaction id, UTR), because the exact file layout is not fixed.
List<PhonePeEntry> parsePhonePeCsv(String text) {
  final List<List<String>> rows = _splitCsv(text.replaceFirst('﻿', ''));
  if (rows.length < 2) return [];
  // the header is the first row that has a date column and an amount-ish column
  int headerAt = -1;
  for (int i = 0; i < rows.length && i < 15; i++) {
    final String joined = rows[i].join('|').toLowerCase();
    if (joined.contains('date') && (joined.contains('amount') || joined.contains('debit') || joined.contains('credit'))) {
      headerAt = i;
      break;
    }
  }
  if (headerAt < 0) return [];
  final List<String> h = rows[headerAt].map((e) => e.trim().toLowerCase()).toList();

  final int cDate = _col(h, [RegExp(r'^date'), RegExp(r'date')]);
  final int cTime = _col(h, [RegExp(r'^time')]);
  final int cDetails = _col(h, [RegExp(r'details|description|narration|merchant|paid to|particulars|name')]);
  final int cType = _col(h, [RegExp(r'^type$|dr\s*/?\s*cr|debit.?credit|transaction type|cr/dr')]);
  final int cAmount = _col(h, [RegExp(r'^amount|amount \(')]);
  final int cDebit = _col(h, [RegExp(r'^debit|withdraw|paid out|amount debited')]);
  final int cCredit = _col(h, [RegExp(r'^credit|deposit|paid in|amount credited')]);
  final int cTxn = _col(h, [RegExp(r'transaction id|txn id|phonepe')]);
  final int cUtr = _col(h, [RegExp(r'utr|bank reference|reference')]);
  final int cStatus = _col(h, [RegExp(r'status')]);
  final int cAccount = _col(h, [RegExp(r'account|paid by|bank')]);
  if (cDate < 0 || (cAmount < 0 && cDebit < 0 && cCredit < 0)) return [];

  String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

  final List<PhonePeEntry> out = [];
  for (final List<String> r in rows.skip(headerAt + 1)) {
    final String status = at(r, cStatus).toLowerCase();
    if (status.isNotEmpty && !status.contains('success') && !status.contains('complete')) continue;

    DateTime? date = _csvDate(at(r, cDate));
    if (date == null) continue;
    if (cTime >= 0) {
      final RegExpMatch? t = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?').firstMatch(at(r, cTime));
      final tm = t == null ? null : _time(t.group(1), t.group(2), t.group(3));
      if (tm != null) date = DateTime(date.year, date.month, date.day, tm.hour, tm.minute);
    }

    double? amount;
    bool? expense;
    if (cDebit >= 0 || cCredit >= 0) {
      final double? d = _money(at(r, cDebit).replaceAll(RegExp(r'[^\d.,]'), ''));
      final double? c = _money(at(r, cCredit).replaceAll(RegExp(r'[^\d.,]'), ''));
      if (d != null && d > 0) {
        amount = d;
        expense = true;
      } else if (c != null && c > 0) {
        amount = c;
        expense = false;
      }
    }
    if (amount == null && cAmount >= 0) {
      final String raw = at(r, cAmount);
      amount = _money(raw.replaceAll(RegExp(r'[^\d.,]'), ''));
      final String ty = at(r, cType).toLowerCase();
      if (ty.contains('debit') || ty == 'dr' || ty.contains('paid') || ty.contains('sent')) expense = true;
      if (ty.contains('credit') || ty == 'cr' || ty.contains('received')) expense = false;
      if (expense == null && raw.trim().startsWith('-')) expense = true;
    }
    if (amount == null || amount <= 0) continue;

    String details = at(r, cDetails);
    expense ??= !RegExp(r'^(received|refund)', caseSensitive: false).hasMatch(details);
    details = details.replaceFirst(RegExp(r'^(paid to|received from|payment to|sent to|refund from)\s*', caseSensitive: false), '');

    out.add(PhonePeEntry(
      amount: amount,
      isExpense: expense,
      party: _titleCase(_tidy(details)),
      date: date,
      txnId: at(r, cTxn),
      utr: _digitsOf(at(r, cUtr)).length >= 9 ? _digitsOf(at(r, cUtr)) : '',
      accountDigits: _digitsOf(at(r, cAccount)),
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// To the review rows
// ---------------------------------------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');

String _stableHash(String text) {
  int h = 0x811c9dc5;
  for (final int unit in text.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

/// The known account whose ending digits match [digits] (as many as are shown), or null when none or
/// several do (nothing is guessed).
({String key, KnownAccount account})? knownAccountByDigits(String digits) {
  if (digits.length < 3) return null;
  ({String key, KnownAccount account})? found;
  for (final MapEntry<String, KnownAccount> e in kKnownAccounts.entries) {
    final List<String> q = e.key.split(':');
    if (q.length != 3 || q[2].length < 3) continue;
    if (digits.endsWith(q[2]) && RegExp(r'^\d+$').hasMatch(q[2])) {
      if (found != null && found.account.wallet != e.value.wallet) return null;
      found ??= (key: e.key, account: e.value);
    }
  }
  return found;
}

String _noteOf(PhonePeEntry e) {
  final List<String> parts = [e.app];
  if (e.amountUnconfirmed) parts.add('CHECK THE AMOUNT (no ₹ sign was read; a leading 7 is taken to be the ₹ sign)');
  if (e.message.isNotEmpty) parts.add(e.message);
  if (e.utr.isNotEmpty) parts.add('UTR ${e.utr}');
  if (e.txnId.isNotEmpty) parts.add('Txn ${e.txnId}');
  return parts.join(' · ');
}

/// One row for the review screen. The ids are made from the PhonePe transaction id / UTR, so the same
/// payment is recognised when it is imported twice.
PingImportRow phonePeToRow(PhonePeEntry e) {
  final String ref = e.txnId.isNotEmpty
      ? e.txnId
      : (e.utr.isNotEmpty
          ? e.utr
          : '${e.date.year}${_two(e.date.month)}${_two(e.date.day)}${_two(e.date.hour)}${_two(e.date.minute)}-${e.amount}-${_stableHash(e.party)}');
  final known = knownAccountByDigits(e.accountDigits);
  final String merchant = e.party;
  final String label = suggestCategoryLabel(e.isExpense, merchant);
  return PingImportRow(
    smsId: 'pp-$ref',
    contentKey: 'pp-${e.utr.isNotEmpty ? e.utr : ref}',
    sender: e.app,
    date: e.date,
    amount: e.amount,
    isExpense: e.isExpense,
    title: merchant.isEmpty ? (e.isExpense ? 'Payment' : 'Money received') : merchant,
    merchant: merchant,
    categoryLabel: label,
    categoryPk: kDefaultCategoryPkByLabel[label],
    accountName: known?.account.name ?? (e.accountDigits.isEmpty ? null : 'Account ••${e.accountDigits.substring(e.accountDigits.length > 4 ? e.accountDigits.length - 4 : 0)}'),
    walletName: known != null && known.account.wallet.isNotEmpty ? known.account.wallet : 'Unassigned',
    closed: known?.account.closed ?? false,
    tickByDefault: true,
    knownAccount: known != null,
    extraNote: _noteOf(e),
  );
}

/// All payments from a statement as review rows, newest first, the same payment only once.
PingImport phonePeEntriesToImport(List<PhonePeEntry> entries) {
  final Set<String> seen = {};
  final List<PingImportRow> rows = [];
  int skipped = 0;
  for (final PhonePeEntry e in entries) {
    final PingImportRow r = phonePeToRow(e);
    if (!seen.add(r.smsId)) {
      skipped++;
      continue;
    }
    rows.add(r);
  }
  rows.sort((a, b) => b.date.compareTo(a.date));
  return PingImport(rows: rows, skipped: skipped);
}


/// The best of several readings of the same picture (the original and its prepared copies).
/// Readings with a rupee sign in front of the amount beat those without; among those, the amount seen
/// most often wins, and on a tie the earlier reading. null when there is no reading at all.
PhonePeEntry? chooseBestReading(List<PhonePeEntry?> readings) {
  final List<PhonePeEntry> all = [for (final PhonePeEntry? r in readings) if (r != null) r];
  if (all.isEmpty) return null;
  final List<PhonePeEntry> confirmed = [for (final PhonePeEntry r in all) if (!r.amountUnconfirmed) r];
  final List<PhonePeEntry> pool = confirmed.isNotEmpty ? confirmed : all;
  final Map<int, int> votes = {};
  for (final PhonePeEntry r in pool) {
    final int key = (r.amount * 100).round();
    votes[key] = (votes[key] ?? 0) + 1;
  }
  PhonePeEntry best = pool.first;
  int bestVotes = votes[(best.amount * 100).round()]!;
  for (final PhonePeEntry r in pool) {
    final int v = votes[(r.amount * 100).round()]!;
    if (v > bestVotes) {
      best = r;
      bestVotes = v;
    }
  }
  return best;
}
