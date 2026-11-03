// Fixed deposits: the model, the interest maths and a reader for bank "FD booked" SMS.
// Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

import 'dart:math';

/// How often interest is added to the deposit. Indian banks mostly compound quarterly.
const Map<int, String> kFdCompoundingNames = {
  4: 'Quarterly',
  12: 'Monthly',
  2: 'Half-yearly',
  1: 'Yearly',
  0: 'Simple interest (paid at maturity)',
};

class FixedDeposit {
  FixedDeposit({
    required this.id,
    required this.bank,
    this.fdNumber = '',
    required this.principal,
    required this.ratePct,
    required this.startDate,
    required this.maturityDate,
    this.compounding = 4,
    this.maturityAmount,
    this.walletPk,
    this.closed = false,
    this.note = '',
    this.fromSms = false,
    this.smsId = '',
  });

  final String id;
  final String bank;
  final String fdNumber;
  final double principal;
  final double ratePct;
  final DateTime startDate;
  final DateTime maturityDate;

  /// Times per year (4 quarterly, 12 monthly, 2, 1) or 0 for simple interest.
  final int compounding;

  /// Maturity amount as the bank states it. When set it is used instead of the calculated value.
  final double? maturityAmount;

  /// Account the money came from / goes back to.
  final String? walletPk;
  final bool closed;
  final String note;

  /// Added automatically from a bank SMS: shown with a "check the details" hint.
  final bool fromSms;
  final String smsId;

  FixedDeposit copyWith({
    String? bank,
    String? fdNumber,
    double? principal,
    double? ratePct,
    DateTime? startDate,
    DateTime? maturityDate,
    int? compounding,
    double? maturityAmount,
    bool clearMaturityAmount = false,
    String? walletPk,
    bool? closed,
    String? note,
    bool? fromSms,
  }) =>
      FixedDeposit(
        id: id,
        bank: bank ?? this.bank,
        fdNumber: fdNumber ?? this.fdNumber,
        principal: principal ?? this.principal,
        ratePct: ratePct ?? this.ratePct,
        startDate: startDate ?? this.startDate,
        maturityDate: maturityDate ?? this.maturityDate,
        compounding: compounding ?? this.compounding,
        maturityAmount:
            clearMaturityAmount ? null : (maturityAmount ?? this.maturityAmount),
        walletPk: walletPk ?? this.walletPk,
        closed: closed ?? this.closed,
        note: note ?? this.note,
        fromSms: fromSms ?? this.fromSms,
        smsId: smsId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bank': bank,
        'no': fdNumber,
        'principal': principal,
        'rate': ratePct,
        'start': startDate.toIso8601String(),
        'maturity': maturityDate.toIso8601String(),
        'comp': compounding,
        'maturityAmount': maturityAmount,
        'wallet': walletPk,
        'closed': closed,
        'note': note,
        'sms': fromSms,
        'smsId': smsId,
      };

  static FixedDeposit? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      double d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
      final DateTime? start = DateTime.tryParse('${j['start']}');
      final DateTime? mat = DateTime.tryParse('${j['maturity']}');
      if (start == null || mat == null) return null;
      return FixedDeposit(
        id: '${j['id']}',
        bank: '${j['bank'] ?? ''}',
        fdNumber: '${j['no'] ?? ''}',
        principal: d(j['principal']),
        ratePct: d(j['rate']),
        startDate: start,
        maturityDate: mat,
        compounding: j['comp'] is num ? (j['comp'] as num).toInt() : 4,
        maturityAmount: j['maturityAmount'] is num ? (j['maturityAmount'] as num).toDouble() : null,
        walletPk: j['wallet']?.toString(),
        closed: j['closed'] == true,
        note: '${j['note'] ?? ''}',
        fromSms: j['sms'] == true,
        smsId: '${j['smsId'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _days(DateTime a, DateTime b) => _day(b).difference(_day(a)).inDays;

/// Interest on the principal after [days], by the deposit's compounding.
double _interestAfter(FixedDeposit fd, int days) {
  if (days <= 0) return 0;
  final double t = days / 365;
  final double r = fd.ratePct / 100;
  if (fd.compounding <= 0) return fd.principal * r * t;
  final int n = fd.compounding;
  return fd.principal * (pow(1 + r / n, n * t) - 1);
}

/// What you get at maturity: the bank's figure when it was entered, otherwise the calculated one.
double maturityValue(FixedDeposit fd) {
  if (fd.maturityAmount != null && fd.maturityAmount! > 0) {
    return _round2(fd.maturityAmount!);
  }
  return _round2(fd.principal + _interestAfter(fd, _days(fd.startDate, fd.maturityDate)));
}

double interestAtMaturity(FixedDeposit fd) => _round2(maturityValue(fd) - fd.principal);

/// Interest earned up to [today] (all of it once matured).
double accruedInterest(FixedDeposit fd, DateTime today) {
  final int total = _days(fd.startDate, fd.maturityDate);
  final int gone = _days(fd.startDate, today);
  if (gone <= 0 || total <= 0) return 0;
  if (gone >= total) return interestAtMaturity(fd);
  if (fd.maturityAmount != null && fd.maturityAmount! > 0) {
    return _round2(interestAtMaturity(fd) * gone / total);
  }
  return _round2(_interestAfter(fd, gone));
}

double currentValue(FixedDeposit fd, DateTime today) =>
    _round2(fd.principal + accruedInterest(fd, today));

/// Days until maturity (negative once past).
int daysToMaturity(FixedDeposit fd, DateTime today) => _days(today, fd.maturityDate);

bool hasMatured(FixedDeposit fd, DateTime today) => daysToMaturity(fd, today) <= 0;

// ---------------------------------------------------------------- SMS

class FdSmsParse {
  const FdSmsParse(this.deposit);
  final FixedDeposit deposit;
}

const Map<String, String> _bankKeywords = {
  'axis': 'Axis Bank',
  'hdfc': 'HDFC Bank',
  'icici': 'ICICI Bank',
  'sbi': 'State Bank of India',
  'kotak': 'Kotak Mahindra Bank',
  'idfc': 'IDFC FIRST Bank',
  'yes bank': 'YES Bank',
  'yesbnk': 'YES Bank',
  'indusind': 'IndusInd Bank',
  'federal': 'Federal Bank',
  'canara': 'Canara Bank',
  'pnb': 'Punjab National Bank',
  'bob': 'Bank of Baroda',
  'union bank': 'Union Bank of India',
  'au small': 'AU Small Finance Bank',
  'aubank': 'AU Small Finance Bank',
  'ausfb': 'AU Small Finance Bank',
  'bajaj': 'Bajaj Finance',
  'equitas': 'Equitas Small Finance Bank',
  'ujjivan': 'Ujjivan Small Finance Bank',
};

String _bankFrom(String sender, String body) {
  final String hay = '${sender.toLowerCase()} ${body.toLowerCase()}';
  for (final MapEntry<String, String> e in _bankKeywords.entries) {
    if (hay.contains(e.key)) return e.value;
  }
  final String tag = sender.replaceFirst(RegExp(r'^[A-Za-z]{2}-'), '').trim();
  return tag.isEmpty ? 'Bank' : tag.toUpperCase();
}

const List<String> _monthAbbr = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
];

DateTime? _parseDate(String s) {
  s = s.trim();
  int year(String y) {
    final int v = int.parse(y);
    return y.length <= 2 ? 2000 + v : v;
  }

  RegExpMatch? m = RegExp(r'^(\d{1,2})[-/. ]([A-Za-z]{3})[a-z]*[-/., ]+(\d{2,4})$').firstMatch(s);
  if (m != null) {
    final int mi = _monthAbbr.indexOf(m.group(2)!.toLowerCase());
    if (mi >= 0) return DateTime(year(m.group(3)!), mi + 1, int.parse(m.group(1)!));
  }
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final int mo = int.parse(m.group(2)!);
    final int da = int.parse(m.group(1)!);
    if (mo >= 1 && mo <= 12 && da >= 1 && da <= 31) return DateTime(year(m.group(3)!), mo, da);
  }
  m = RegExp(r'^([A-Za-z]{3})[a-z]*\s+(\d{1,2}),?\s+(\d{4})$').firstMatch(s);
  if (m != null) {
    final int mi = _monthAbbr.indexOf(m.group(1)!.toLowerCase());
    if (mi >= 0) return DateTime(int.parse(m.group(3)!), mi + 1, int.parse(m.group(2)!));
  }
  return null;
}

const String _datePattern =
    r'(\d{1,2}[-/. ][A-Za-z]{3}[a-z]*[-/., ]+\d{2,4}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|[A-Za-z]{3}[a-z]*\s+\d{1,2},?\s+\d{4})';

double? _money(String? s) => s == null ? null : double.tryParse(s.replaceAll(',', ''));

DateTime _addMonths(DateTime d, int months) {
  final int total = d.month - 1 + months;
  final int y = d.year + total ~/ 12;
  final int m = total % 12 + 1;
  final int last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > last ? last : d.day);
}

final RegExp _fdWord = RegExp(r'fixed\s*deposit|term\s*deposit|\bF\.?D\.?R?\b|\bT\.?D\.?R?\b', caseSensitive: false);
final RegExp _bookedWord = RegExp(r'\b(book(?:ed|ing)?|open(?:ed)?|creat(?:ed|ion)|renew(?:ed|al)?|placed|constitut(?:ed)?|established|set up)\b', caseSensitive: false);
final RegExp _notBooking = RegExp(r'\b(matured|closed|closure|premature|broken|liquidat|interest (?:has been )?credited|proceeds)\b|\botp\b|will mature|is maturing|due for', caseSensitive: false);

/// True when the text looks like a fixed deposit being opened or renewed (used by Ping to forward it).
bool looksLikeFixedDepositBooking(String body) =>
    _fdWord.hasMatch(body) && _bookedWord.hasMatch(body) && !_notBooking.hasMatch(body);

/// Reads an "FD booked / renewed" SMS. Returns null when it is not one, or when the amount or the maturity
/// cannot be found (those are not guessed). Deposits made here never create a transaction: the debit SMS
/// from the bank does that.
FdSmsParse? parseFixedDepositSms({
  required String body,
  required String sender,
  required DateTime smsDate,
  String smsId = '',
}) {
  if (!looksLikeFixedDepositBooking(body)) return null;

  // amount: prefer the one written as "deposit of Rs..." / "amount Rs...", else the first rupee amount
  final RegExp rupee = RegExp(r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false);
  final RegExpMatch? named = RegExp(
          r'(?:deposit|fd|fdr|td|amount|principal)[^\d]{0,30}?(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d+)?)',
          caseSensitive: false)
      .firstMatch(body);
  final double? principal = _money(named?.group(1)) ?? _money(rupee.firstMatch(body)?.group(1));
  if (principal == null || principal <= 0) return null;

  // maturity amount (if stated)
  final RegExpMatch? matAmt = RegExp(
          r'matur\w*\s*(?:amount|value|proceeds|amt)[^\d]{0,20}?(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d+)?)',
          caseSensitive: false)
      .firstMatch(body);
  final double? maturityAmount = _money(matAmt?.group(1));

  // rate
  final RegExpMatch? rateM = RegExp(r'(\d{1,2}(?:\.\d+)?)\s*%', caseSensitive: false).firstMatch(body) ??
      RegExp(r'(?:roi|rate(?: of interest)?|interest rate)[^\d]{0,12}(\d{1,2}(?:\.\d+)?)', caseSensitive: false)
          .firstMatch(body);
  final double rate = double.tryParse(rateM?.group(1) ?? '') ?? 0;

  // dates
  final RegExpMatch? matDateM =
      RegExp(r'matur\w*\s*(?:on|date|dt|:|-)?\s*[:\-]?\s*' + _datePattern, caseSensitive: false).firstMatch(body);
  DateTime? maturity = matDateM == null ? null : _parseDate(matDateM.group(1)!);
  final RegExpMatch? startM = RegExp(
          r'(?:booked|opened|created|placed|start\w*|value date|deposit date)\s*(?:on|date|dt|:|-)?\s*[:\-]?\s*' + _datePattern,
          caseSensitive: false)
      .firstMatch(body);
  final DateTime start = _day((startM == null ? null : _parseDate(startM.group(1)!)) ?? smsDate);

  if (maturity == null) {
    final RegExpMatch? ten = RegExp(r'(?:tenure|period|term|for)\s*(?:of|:)?\s*(\d{1,3})\s*(month|day|year|yr)', caseSensitive: false).firstMatch(body);
    if (ten != null) {
      final int n = int.parse(ten.group(1)!);
      final String u = ten.group(2)!.toLowerCase();
      maturity = u.startsWith('month')
          ? _addMonths(start, n)
          : u.startsWith('day')
              ? start.add(Duration(days: n))
              : _addMonths(start, 12 * n);
    }
  }
  if (maturity == null || !maturity.isAfter(start)) return null;

  final RegExpMatch? noM = RegExp(
          r'(?:fd|fdr|td|deposit|receipt|a/?c|account)\s*(?:no\.?|number|#)?\s*[:\-]?\s*(?:x+|\*+)?(\d{4,})',
          caseSensitive: false)
      .firstMatch(body);

  return FdSmsParse(FixedDeposit(
    id: 'sms-${smsId.isEmpty ? start.millisecondsSinceEpoch : smsId}',
    bank: _bankFrom(sender, body),
    fdNumber: noM?.group(1) ?? '',
    principal: principal,
    ratePct: rate,
    startDate: start,
    maturityDate: _day(maturity),
    compounding: 4,
    maturityAmount: maturityAmount,
    fromSms: true,
    smsId: smsId,
  ));
}

/// True when [a] and [b] are the same deposit (same SMS, same FD number at the same bank, or the same
/// amount and dates at the same bank).
bool sameDeposit(FixedDeposit a, FixedDeposit b) {
  if (a.smsId.isNotEmpty && a.smsId == b.smsId) return true;
  final bool sameBank = a.bank.toLowerCase() == b.bank.toLowerCase();
  if (!sameBank) return false;
  if (a.fdNumber.isNotEmpty && a.fdNumber == b.fdNumber) return true;
  return a.principal == b.principal &&
      _day(a.startDate) == _day(b.startDate) &&
      _day(a.maturityDate) == _day(b.maturityDate);
}
