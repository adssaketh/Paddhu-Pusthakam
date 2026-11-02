// Reads a bank / wallet SMS and works out what happened: how much, in or out, who with, a suggested
// category, a title, and which account / card / wallet it was.
//
// Pure Dart (no Flutter or database imports) so it can be checked with `dart run`. It is rule based:
// patterns for the SMS formats seen in the Ping backup, plus a keyword list that maps merchant
// names to Paddhu's default categories. It does not learn by itself; the learning part is Paddhu's
// own "associated titles" (title -> category you picked before), which smartSmsTransactions.dart
// asks first.
//
// Every pattern here is identical to tool/reference/smsparse.py, which produced the expected answers in
// test/fixtures. Change them together.

import 'instrumentParser.dart';

/// Category label from the rules -> categoryPk of Paddhu's default categories.
/// Labels not listed here (health, transfer) have no default category, so the page opens with the
/// category left empty for you to choose.
const Map<String, String> kDefaultCategoryPkByLabel = {
  'dining': '1',
  'groceries': '2',
  'shopping': '3',
  'transit': '4',
  'entertainment': '5',
  'bills_fees': '6',
  'gifts': '7',
  'beauty': '8',
  'work': '9',
  'travel': '10',
  'income': '11',
};

class ParsedSmsTransaction {
  const ParsedSmsTransaction({
    required this.amount,
    required this.isExpense,
    required this.merchant,
    required this.cardPayment,
    required this.category,
    required this.title,
    required this.instrumentKey,
  });

  /// Always positive.
  final double amount;

  /// true = money out, false = money in.
  final bool isExpense;

  /// Cleaned merchant / person / UPI handle as found in the SMS, '' when the SMS does not say.
  final String merchant;

  /// A credit-card bill payment acknowledgement. The bank-side debit is a separate SMS, so these
  /// should not be added as transactions.
  final bool cardPayment;

  /// Rule-based label ('dining', 'groceries', ... 'income'), '' when unknown.
  final String category;

  /// Suggested transaction title (max 60 characters).
  final String title;

  /// Key like "sbi:account:6919", see instrumentParser.dart. Single-message only: the cross-message
  /// tidying in buildInstrumentResolver is not applied.
  final String instrumentKey;

  String? get categoryPk => kDefaultCategoryPkByLabel[category];

  /// "SBI ••6919" style name, or null when the SMS does not say which account it was.
  String? get instrumentName => instrumentLabel(instrumentKey);
}

// ---------------------------------------------------------------------------------------------
// Patterns
// ---------------------------------------------------------------------------------------------

final RegExp _notTxn = RegExp(
    r"requested money|will be debited|is due|due on|not completed|if debited|passbook|has been initiated|e-mandate|mandate|\botp\b|one.?time password|verification code|balance enquiry|statement|total amt due|min amt due",
    caseSensitive: false);
final RegExp _amtRe =
    RegExp(r"(?:rs\.?|inr|\u20b9)\s*(\d[\d,]*(?:\.\d+)?)", caseSensitive: false);
final RegExp _amtByRe = RegExp(
    r"(?:debited|credited)\s+(?:by|for|with)\s+(\d[\d,]*(?:\.\d+)?)",
    caseSensitive: false);
final RegExp _debitRe = RegExp(
    r"\bdebit(?:ed)?\b(?! card)|spent|\bpaid\b|withdrawn|\bsent\b|purchase|payment of|transaction number \d+ for",
    caseSensitive: false);
final RegExp _creditRe =
    RegExp(r"credited|received|refund|deposited", caseSensitive: false);
final RegExp _cardBillRe = RegExp(
    r"payment of .{0,24}(?:has been|is) received (?:on|towards) your .{0,60}credit card|credit ?card payment|payment .{0,30}towards your .{0,40}credit card|thank you for payment .{0,40}credit card",
    caseSensitive: false);
final RegExp _debitThenCreditRe =
    RegExp(r";\s*.+? credited\.", caseSensitive: false);
final RegExp _debitedRe = RegExp(r"\bdebited\b", caseSensitive: false);

final RegExp _mAxis =
    RegExp(r"UPI/P2[MA]/\d+/(.+?)\s+Not you", caseSensitive: false);
final RegExp _mSbi =
    RegExp(r"(?:transfer|trf)\s+to\s+(.+?)\s+Ref\s?no", caseSensitive: false);
final RegExp _mFrom =
    RegExp(r"\bfrom\s+([A-Za-z][A-Za-z .&']+?)\.\s*UPI", caseSensitive: false);
final RegExp _mIciciOn = RegExp(
    r"\bon \d{1,2}-[A-Za-z]{3}-\d{2,4} on (.+?)\s*(?:-\s*)?\.",
    caseSensitive: false);
final RegExp _mAtSign = RegExp(
    r"@\s*([A-Za-z0-9 .*&\-]+?)\s+\d{2}-\d{2}-\d{2,4}",
    caseSensitive: false);
final RegExp _mAt = RegExp(
    r"\bat\s+(.+?)(?:\s+on\s+\d|\s*\.\s+(?:Avl|Available))",
    caseSensitive: false);
final RegExp _mIciciSemi =
    RegExp(r";\s*(.+?)\s+credited\.", caseSensitive: false);
final RegExp _mUpiDash = RegExp(
    r"UPI-\d+-([A-Za-z0-9 .&]+?)(?:\.|\s*To dispute|$)",
    caseSensitive: false);
final RegExp _mUsing =
    RegExp(r"using\s+([A-Za-z ]+?)\s+is successful", caseSensitive: false);
final RegExp _mAgainst =
    RegExp(r"against\s+([A-Za-z ]+?)(?:,|\.)", caseSensitive: false);
final RegExp _mInfoDash =
    RegExp(r"\bInfo\s*-\s*([A-Za-z][A-Za-z ]+)", caseSensitive: false);
final RegExp _mVpa =
    RegExp(r"to VPA\s+([A-Za-z0-9._\-]+)@", caseSensitive: false);
final RegExp _mInfo =
    RegExp(r"Info[:\-]?\s*([A-Za-z]+)[*\-]", caseSensitive: false);
final RegExp _mOrder = RegExp(
    r"\b(zepto|swiggy|zomato|blinkit|amazon|flipkart|myntra)\b",
    caseSensitive: false);
final RegExp _atmRe = RegExp(
    r"withdrawn at .{0,40}\bATM\b|\bATM\b.{0,30}withdrawn|cash withdrawal",
    caseSensitive: false);
final RegExp _vpaTailRe = RegExp(
    r"(?:[-.]\d{4,}.*|\.(?:payu|rzp|cc)\b.*)$",
    caseSensitive: false);
final RegExp _vpaDigitsRe = RegExp(r"\d{4,}$");
final RegExp _vpaNoiseRe = RegExp(
    r"^(?:[\d.\-]+|gpay-\d+|paytmqr\d*[a-z0-9]*|q\d+)$",
    caseSensitive: false);
final RegExp _terminalRe = RegExp(r"^(?=.*\d)[A-Za-z0-9]{6,10}$");
final RegExp _spacesRe = RegExp(r"\s+");

final RegExp _creditIncomeRe =
    RegExp(r"salary|interest|dividend|cashback|payout", caseSensitive: false);

// First match wins, so the order matters.
final List<MapEntry<String, RegExp>> _categoryRules = [
  MapEntry(
      'transfer',
      RegExp(r"bank account|own account|self transfer|\bidfc first bank\b",
          caseSensitive: false)),
  MapEntry(
      'travel',
      RegExp(
          r"irctc|redbus|abhibus|makemytrip|goibibo|cleartrip|yatra|indigo|air ?india|vistara|akasa|oyo\b|lodge|resort|airbnb|trainman|ixigo",
          caseSensitive: false)),
  MapEntry(
      'transit',
      RegExp(
          r"\buber\b|\bola\b|rapido|metro|fuel|petrol|diesel|hpcl|bpcl|iocl|fastag|tsrtc|apsrtc|parking|\btoll\b|namma yatri",
          caseSensitive: false)),
  MapEntry(
      'entertainment',
      RegExp(
          r"netflix|hotstar|spotify|prime video|bookmyshow|\bpvr\b|\binox\b|youtube|jiocinema|sonyliv|zee5|steam|playstation|play ?store|google play|cinema|movie",
          caseSensitive: false)),
  MapEntry(
      'bills_fees',
      RegExp(
          r"\bjio\b|airtel|vodafone|\bvi\b|bsnl|tata ?sky|tata ?play|\bdth\b|electric|bescom|tsspdcl|tgspdcl|apspdcl|water board|broadband|fibernet|insurance|\blic\b|premium|\bemi\b|\bfees?\b|charges|bil\*|billdesk|\bbill\b|recharge|\bloan\b|\brent\b",
          caseSensitive: false)),
  MapEntry(
      'beauty',
      RegExp(
          r"nykaa|salon|parlou?r|\bspa\b|beauty|cosmetic|barber|grooming|lakme|urban company",
          caseSensitive: false)),
  MapEntry(
      'gifts',
      RegExp(r"\bgifts?\b|florist|flowers|archies", caseSensitive: false)),
  MapEntry(
      'work',
      RegExp(
          r"github|\baws\b|amazon web|google cloud|digitalocean|notion|linkedin|openai|anthropic|godaddy|hosting|coworking|\bzoom\b",
          caseSensitive: false)),
  MapEntry(
      'groceries',
      RegExp(
          r"zepto|blinkit|instamart|bigbasket|d-?mart|reliance smart|smart bazaar|supermarket|fruits?|vegetable|kirana|provision|grocer|ksheera|dairy|\bmilk\b|ratnadeep|spencer|more retail|\bsmart \d+",
          caseSensitive: false)),
  MapEntry(
      'dining',
      RegExp(
          r"swiggy|zomato|food|restaurant|cafe|chai|\btea\b|bakery|biryani|pizza|\bkfc\b|mcdonald|domino|burger|momo|frankie|sweets|juice|ice ?cream|kitchen|dhaba|tiffin|canteen|\bmess\b|coffee|\bccd\b|starbucks|eatery|brew|hotel",
          caseSensitive: false)),
  MapEntry(
      'shopping',
      RegExp(
          r"amazon|flipkart|myntra|ajio|meesho|tanishq|fancy|bangles|\bstores?\b|shoe|mobiles?|poorvika|ikea|lenskart|croma|decathlon|jewel|textile|clothing|fashion|boutique|saravana|pothys|trends|ecommerce|fsn|\bshop\b",
          caseSensitive: false)),
  MapEntry(
      'health',
      RegExp(
          r"pharmacy|medplus|apollo|medical|hospital|clinic|diagnostic|pharma|1mg|netmeds|dental",
          caseSensitive: false)),
];

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

// Same as Python's s.strip(chars).
String _stripChars(String s, String chars) {
  var start = 0;
  var end = s.length;
  while (start < end && chars.contains(s[start])) {
    start++;
  }
  while (end > start && chars.contains(s[end - 1])) {
    end--;
  }
  return s.substring(start, end);
}

String _clean(String s) => _stripChars(s.replaceAll(_spacesRe, ' '), ' .-*');

String _merchantOf(String body) {
  if (_atmRe.hasMatch(body)) return 'ATM withdrawal';
  final first = <RegExp>[
    _mAxis,
    _mSbi,
    _mFrom,
    _mIciciOn,
    _mAtSign,
    _mAt,
    _mIciciSemi,
    _mUpiDash,
    _mUsing,
    _mAgainst,
    _mInfoDash,
  ];
  for (final rx in first) {
    final m = rx.firstMatch(body);
    if (m != null) {
      final v = _clean(m.group(1)!);
      if (v.isNotEmpty && !_terminalRe.hasMatch(v)) return v;
    }
  }
  var m = _mVpa.firstMatch(body);
  if (m != null) {
    final h = m.group(1)!;
    if (_vpaNoiseRe.hasMatch(h)) return '';
    return _clean(
        h.replaceFirst(_vpaTailRe, '').replaceFirst(_vpaDigitsRe, ''));
  }
  m = _mInfo.firstMatch(body);
  if (m != null) {
    final v = _clean(m.group(1)!);
    return v.toUpperCase() == 'BIL' ? 'BillDesk' : v;
  }
  m = _mOrder.firstMatch(body);
  if (m != null) return _clean(m.group(1)!);
  return '';
}

String _categorize(bool isExpense, String merchant, String body) {
  if (!isExpense) {
    return _creditIncomeRe.hasMatch(body) ? 'income' : '';
  }
  for (final rule in _categoryRules) {
    if (rule.value.hasMatch(merchant)) return rule.key;
  }
  return '';
}

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

double _toAmount(String digits) => double.parse(digits.replaceAll(',', ''));

// ---------------------------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------------------------

final RegExp _senderIdRe =
    RegExp(r"^[A-Za-z]{2}-[A-Za-z0-9]{3,12}(?:-[A-Za-z])?$");
final RegExp _bareSenderRe = RegExp(r"^[A-Za-z][A-Za-z0-9]{4,11}$");

/// True for sender IDs the way Android shows them for bank SMS ("AX-AXISBK-S", "VM-SBIUPI",
/// "JAJIOPAY"), false for phone numbers and normal contact names with spaces. Used to avoid
/// parsing chat notifications.
bool looksLikeSenderId(String sender) {
  final s = sender.trim();
  return _senderIdRe.hasMatch(s) || _bareSenderRe.hasMatch(s);
}

/// Returns null when the SMS is not a completed money movement (OTPs, requests, reminders,
/// statements, marketing...).
ParsedSmsTransaction? parseSmsTransaction(String sender, String body) {
  final instrument = instrumentKey(parseInstrument(sender, body));

  if (_cardBillRe.hasMatch(body)) {
    final a0 = _amtRe.firstMatch(body);
    return ParsedSmsTransaction(
      amount: a0 != null ? _toAmount(a0.group(1)!) : 0.0,
      isExpense: true,
      merchant: '',
      cardPayment: true,
      category: '',
      title: 'Card bill payment',
      instrumentKey: instrument,
    );
  }
  if (_notTxn.hasMatch(body)) return null;

  final am = _amtByRe.firstMatch(body) ?? _amtRe.firstMatch(body);
  if (am == null) return null;
  final amount = _toAmount(am.group(1)!);

  final d = _debitRe.firstMatch(body);
  final c = _creditRe.firstMatch(body);
  if (d == null && c == null) return null;

  bool isExpense;
  if (d != null && c != null) {
    isExpense = d.start < c.start;
  } else {
    isExpense = d != null;
  }
  // "... debited for Rs 25.00 ...; Hyderabad Metro credited." is still a debit
  if (_debitedRe.hasMatch(body) && _debitThenCreditRe.hasMatch(body)) {
    isExpense = true;
  }

  final merchant = _merchantOf(body);
  final category = _categorize(isExpense, merchant, body);

  var title = merchant.isNotEmpty
      ? _titleCase(merchant)
      : (isExpense ? 'Payment' : 'Money received');
  if (title.length > 60) title = title.substring(0, 60);
  title = title.trim();

  return ParsedSmsTransaction(
    amount: amount,
    isExpense: isExpense,
    merchant: merchant,
    cardPayment: false,
    category: category,
    title: title,
    instrumentKey: instrument,
  );
}
