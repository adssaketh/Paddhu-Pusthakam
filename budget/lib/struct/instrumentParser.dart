// Works out which bank account, credit card, debit card or wallet a transaction SMS is about, so the
// same money source always gets the same key (e.g. "icici:account:2090" or "axis:credit_card:1896").
//
// This is a 1:1 port of Ping's src/utils/instrument.ts. Keep the two in step: if you change a rule
// here, change it there too, and regenerate test/fixtures/instrument_golden.json from Ping.
//
// Pure Dart on purpose (no Flutter or database imports) so it can be tested with `dart run`.

enum InstrumentKind {
  account('account'),
  creditCard('credit_card'),
  debitCard('debit_card'),
  card('card'),
  wallet('wallet'),
  unknown('unknown');

  const InstrumentKind(this.wire);

  /// The name used inside keys, identical to Ping's.
  final String wire;
}

class InstrumentRef {
  const InstrumentRef({
    required this.issuer,
    required this.kind,
    required this.last,
  });

  /// Normalised, lower case: "icici", "axis", "sbi", "zepto"...
  final String issuer;
  final InstrumentKind kind;

  /// Last digits shown in the SMS (3 or 4), or '' when the SMS does not say.
  final String last;

  InstrumentRef copyWith({String? issuer, InstrumentKind? kind, String? last}) =>
      InstrumentRef(
        issuer: issuer ?? this.issuer,
        kind: kind ?? this.kind,
        last: last ?? this.last,
      );
}

/// One SMS to look at: its id, the sender ID as Android shows it ("AX-AXISBK-S") and the text.
class InstrumentMessage {
  const InstrumentMessage({
    required this.id,
    required this.sender,
    required this.text,
  });

  final String id;
  final String sender;
  final String text;
}

// ---------------------------------------------------------------------------------------------
// Sender and body tables
// ---------------------------------------------------------------------------------------------

// Sender-ID business (after the "AX-" prefix) -> issuer. Anything not listed falls back to the
// lower-cased ID.
final List<MapEntry<RegExp, String>> _issuerBySender = [
  MapEntry(RegExp(r'^(SBIUPI|SBIINB|SBIPSG|SBMSG|SBIBNK)$'), 'sbi'),
  MapEntry(RegExp(r'^(SBICRD|SBICARD)$'), 'sbi_card'),
  MapEntry(RegExp(r'^ICICI'), 'icici'),
  MapEntry(RegExp(r'^AXIS'), 'axis'),
  MapEntry(RegExp(r'^(FEDBNK|FEDERL|FEDRAL)$'), 'federal'),
  MapEntry(RegExp(r'^HDFC'), 'hdfc'),
  MapEntry(RegExp(r'^IDFCFB'), 'idfcfb'),
  MapEntry(RegExp(r'^AUBANK$'), 'au'),
  MapEntry(RegExp(r'^YESBNK$'), 'yes'),
  MapEntry(RegExp(r'^(JIOPAY|JIOINF|JIOFIN)$'), 'jiopay'),
  MapEntry(RegExp(r'^ZEPTON$'), 'zepto'),
  MapEntry(RegExp(r'^(PAYTM|PYTM)'), 'paytm'),
  MapEntry(RegExp(r'^(PHONEPE|PHONPE)$'), 'phonepe'),
];

final List<MapEntry<RegExp, String>> _issuerByBody = [
  MapEntry(RegExp(r'\bICICI\b', caseSensitive: false), 'icici'),
  MapEntry(RegExp(r'\bAxis\b', caseSensitive: false), 'axis'),
  MapEntry(RegExp(r'\bFederal Bank\b', caseSensitive: false), 'federal'),
  MapEntry(RegExp(r'\bHDFC\b', caseSensitive: false), 'hdfc'),
  MapEntry(RegExp(r'\bAU Small|AU Bank\b', caseSensitive: false), 'au'),
  MapEntry(RegExp(r'\bYes Bank\b', caseSensitive: false), 'yes'),
  MapEntry(RegExp(r'-\s?SBI\b|\bSBI\b'), 'sbi'),
];

final RegExp _walletRe = RegExp(
  r'(zepto cash|amazon pay(?: balance)?|paytm wallet|phonepe wallet|mobikwik|freecharge|jio ?pay wallet|airtel money|mi pay|simpl|lazypay|slice)',
  caseSensitive: false,
);

/// Digits after "A/c", "Acct", "ending", "XX", "card" ... as printed in the SMS.
final RegExp _accountRe = RegExp(
  r'(?:a\/?c(?:count)?|acct)\.?\s*(?:no\.?)?\s*(?:ending|ending with)?\s*[:\-]?\s*(?:[Xx*]+|\.{2,})?\s*(\d{3,})',
  caseSensitive: false,
);
final RegExp _cardRe = RegExp(
  r'(?:card|\bcc\b)\s*(?:no\.?)?\s*(?:ending(?: with)?|xx+|x+|\*+)?\s*[:\-]?\s*(?:[Xx*]+)?\s*(\d{4})\b',
  caseSensitive: false,
);
final RegExp _maskRe = RegExp(r'[Xx*]{2,}(\d{3,4})\b');

final RegExp _creditRe = RegExp(
  r'credit\s*card|\bcc\b\s*(?:no|ending|xx|x+|\*+|\d)|sbi card',
  caseSensitive: false,
);
final RegExp _debitRe = RegExp(r'debit\s*card', caseSensitive: false);
final RegExp _cardWordRe =
    RegExp(r'\bcard\b|credit\s*card|debit\s*card', caseSensitive: false);

// ---------------------------------------------------------------------------------------------
// Sender helpers (Ping's phone.ts: isPhoneNumber and businessKey)
// ---------------------------------------------------------------------------------------------

final RegExp _phoneRe = RegExp(r'^\+?[\d\s\-()]{7,}$');
final RegExp _businessRe =
    RegExp(r'^[a-z0-9]{2}-([a-z0-9]{2,12})(?:-[a-z])?$', caseSensitive: false);

bool _isPhoneNumber(String value) => _phoneRe.hasMatch(value.trim());

/// "AX-AXISBK-S", "VM-AXISBK-S" and "JD-AXISBK-T" are all "AXISBK". Phone numbers have none.
String? _businessKey(String sender) {
  final raw = sender.trim();
  if (raw.isEmpty || _isPhoneNumber(raw)) return null;
  final match = _businessRe.firstMatch(raw);
  return (match != null ? match.group(1)! : raw).toUpperCase();
}

bool _knownSender(String name) =>
    _issuerBySender.any((e) => e.key.hasMatch(name));

/// "AX-AXISBK-S" -> "AXISBK"; also "JAJIOPAY" (prefix without a dash) -> "JIOPAY" when the rest is
/// a known sender.
String _senderName(String sender) {
  final raw = sender.trim().toUpperCase();
  final dashed = (_businessKey(raw) ?? raw).toUpperCase();
  if (dashed != raw || raw.contains('-')) return dashed;
  if (!_knownSender(raw) && raw.length > 5 && _knownSender(raw.substring(2))) {
    return raw.substring(2);
  }
  return raw;
}

String _issuerOf(String sender, String body) {
  final biz = _senderName(sender);
  for (final e in _issuerBySender) {
    if (e.key.hasMatch(biz)) return e.value;
  }
  for (final e in _issuerByBody) {
    if (e.key.hasMatch(body)) return e.value;
  }
  return biz.toLowerCase();
}

String _tail(String digits) =>
    digits.length > 4 ? digits.substring(digits.length - 4) : digits;

/// Same as JavaScript's s.slice(-n).
String _lastN(String s, int n) => s.length > n ? s.substring(s.length - n) : s;

// ---------------------------------------------------------------------------------------------
// Parsing one SMS
// ---------------------------------------------------------------------------------------------

final RegExp _scapiaSenderRe = RegExp(r'^FEDSCP');
final RegExp _scapiaRe = RegExp(r'\bscapia\b', caseSensitive: false);
final RegExp _visaRe = RegExp(r'\bvisa\b', caseSensitive: false);
final RegExp _rupayRe = RegExp(r'\brupay\b', caseSensitive: false);

InstrumentRef parseInstrument(String sender, String body) {
  final issuer = _issuerOf(sender, body);
  final text = body;

  // Scapia (Federal Bank) SMS never print the card digits, the card network is the only clue.
  if (_scapiaSenderRe.hasMatch(_senderName(sender)) || _scapiaRe.hasMatch(text)) {
    return InstrumentRef(
      issuer: 'scapia',
      kind: InstrumentKind.creditCard,
      last: _visaRe.hasMatch(text)
          ? 'visa'
          : _rupayRe.hasMatch(text)
              ? 'rupay'
              : '',
    );
  }

  final isCredit = _creditRe.hasMatch(text) || issuer == 'sbi_card';
  final isDebit = _debitRe.hasMatch(text);
  final wallet = _walletRe.firstMatch(text);

  final acct = _accountRe.firstMatch(text);
  final cardWord = _cardWordRe.firstMatch(text);
  // "Axis Bank A/c XX6372 ... CreditCard Payment": the money left the account, so whichever comes
  // first wins.
  final accountFirst =
      acct != null && (cardWord == null || acct.start < cardWord.start);
  if (!accountFirst && (isCredit || isDebit || cardWord != null)) {
    final m = _cardRe.firstMatch(text) ??
        ((isCredit || isDebit) ? _maskRe.firstMatch(text) : null);
    if (m != null) {
      return InstrumentRef(
        issuer: issuer,
        kind: isCredit
            ? InstrumentKind.creditCard
            : isDebit
                ? InstrumentKind.debitCard
                : InstrumentKind.card,
        last: _tail(m.group(1)!),
      );
    }
  }
  if (wallet != null && !_accountRe.hasMatch(text)) {
    return InstrumentRef(
      issuer: wallet.group(1)!.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      kind: InstrumentKind.wallet,
      last: '',
    );
  }
  final a = acct ?? _maskRe.firstMatch(text);
  if (a != null) {
    return InstrumentRef(
      issuer: issuer,
      kind: InstrumentKind.account,
      last: _tail(a.group(1)!),
    );
  }
  if (isCredit) {
    return InstrumentRef(
        issuer: issuer, kind: InstrumentKind.creditCard, last: '');
  }
  return InstrumentRef(issuer: issuer, kind: InstrumentKind.unknown, last: '');
}

String instrumentKey(InstrumentRef r) => '${r.issuer}:${r.kind.wire}:${r.last}';

// ---------------------------------------------------------------------------------------------
// Tidying all parsed SMS together
// ---------------------------------------------------------------------------------------------

const Set<String> _banks = {
  'sbi', 'icici', 'axis', 'federal', 'au', 'yes', 'hdfc', 'idfc', 'idfcfb'
};

/// Looks at every parsed SMS together and tidies the result:
///  - "XX090" and "XX2090" are the same account (3 vs 4 printed digits);
///  - "Card 1000" and "Credit Card 1000" from the same bank are the same credit card;
///  - an SMS with no digits (e.g. a UPI debit) goes to that bank's only account, if there is
///    exactly one.
/// Returns a function that gives the final key for each parsed SMS.
String Function(InstrumentRef) buildInstrumentResolver(List<InstrumentRef> refs) {
  final withDigits = refs.where((r) => r.last.isNotEmpty).toList();

  InstrumentRef canon(InstrumentRef r) {
    if (r.last.isEmpty) return r;
    var out = r;
    if (r.kind == InstrumentKind.card) {
      final cc = withDigits
          .where((x) =>
              x.issuer == r.issuer &&
              x.kind == InstrumentKind.creditCard &&
              x.last.endsWith(_lastN(r.last, 3)))
          .firstOrNull;
      if (cc != null) {
        out = out.copyWith(
          kind: InstrumentKind.creditCard,
          last: cc.last.length >= out.last.length ? cc.last : out.last,
        );
      }
    }
    // third-party senders (EPFO, a shop refund...) that name one of your accounts by its last
    // digits belong to that bank
    if (out.kind == InstrumentKind.account && !_banks.contains(out.issuer)) {
      final cur = out;
      final owner = withDigits
          .where((x) =>
              x.kind == InstrumentKind.account &&
              _banks.contains(x.issuer) &&
              x.last == cur.last)
          .map((x) => x.issuer)
          .toSet()
          .toList();
      if (owner.length == 1) out = out.copyWith(issuer: owner[0]);
    }
    final current = out;
    final longer = withDigits
        .where((x) =>
            x.issuer == current.issuer &&
            x.kind == current.kind &&
            x.last.length > current.last.length &&
            x.last.endsWith(current.last))
        .firstOrNull;
    return longer != null ? out.copyWith(last: longer.last) : out;
  }

  final known = <String, InstrumentRef>{};
  for (final r in withDigits) {
    final c = canon(r);
    known['${c.issuer}:${c.kind.wire}:${c.last}'] = c;
  }
  List<InstrumentRef> accountsOf(String issuer) => known.values
      .where((x) => x.issuer == issuer && x.kind == InstrumentKind.account)
      .toList();

  return (InstrumentRef r) {
    if (r.last.isNotEmpty) return instrumentKey(canon(r));
    if (r.kind == InstrumentKind.unknown) {
      final only = accountsOf(r.issuer);
      if (only.length == 1) return instrumentKey(only[0]);
    }
    return instrumentKey(r);
  };
}

// ---------------------------------------------------------------------------------------------
// Labels, closed accounts, and the all-messages entry point
// ---------------------------------------------------------------------------------------------

const Map<String, String> _issuerLabel = {
  'sbi': 'SBI',
  'sbi_card': 'SBI Card',
  'icici': 'ICICI',
  'axis': 'Axis',
  'federal': 'Federal',
  'hdfc': 'HDFC',
  'au': 'AU',
  'yes': 'Yes Bank',
  'idfc': 'IDFC First',
  'idfcfb': 'IDFC First',
  'scapia': 'Scapia',
  'jiopay': 'Jio Pay',
  'zepto': 'Zepto',
  'zepto_cash': 'Zepto Cash',
  'phonepe': 'PhonePe',
  'phonepe_wallet': 'PhonePe wallet',
  'mi_pay': 'Mi Pay',
  'amazon_pay_balance': 'Amazon Pay',
  'paytm': 'Paytm',
};

/// Short name shown for an instrument: "SBI ••6919", "ICICI card ••1000", "Zepto Cash".
/// Null when the SMS does not say which one.
String? instrumentLabel(String key) {
  final parts = key.split(':');
  final issuer = parts[0];
  final kind = parts.length > 1 ? parts[1] : '';
  final last = parts.length > 2 ? parts[2] : '';
  final name = _issuerLabel[issuer] ?? issuer.toUpperCase();
  if (kind == 'wallet') return name;
  if (last.isEmpty) return null;
  final tag = (kind == 'credit_card' || kind == 'card')
      ? ' card'
      : kind == 'debit_card'
          ? ' debit'
          : '';
  return '$name$tag \u2022\u2022$last';
}

/// Accounts that no longer exist (the two Federal Bank accounts). Their old messages stay, marked
/// "closed".
bool isClosedInstrument(String key) =>
    key.startsWith('federal:account:') || key == 'federal:unknown:';

final RegExp _txnRe = RegExp(
  r'debited|credited|spent|paid|payment|received|withdrawn|refund|transfer|balance',
  caseSensitive: false,
);
final RegExp _otpRe = RegExp(
  r'\botp\b|one.?time password|verification code',
  caseSensitive: false,
);

/// Message id -> instrument key for every transaction-looking message in the list. Messages that
/// are OTPs or do not look like transactions are left out of the result.
Map<String, String> indexInstruments(List<InstrumentMessage> msgs) {
  final parsed = <MapEntry<String, InstrumentRef>>[];
  for (final m in msgs) {
    if (_otpRe.hasMatch(m.text) || !_txnRe.hasMatch(m.text)) continue;
    parsed.add(MapEntry(m.id, parseInstrument(m.sender, m.text)));
  }
  final resolve = buildInstrumentResolver(parsed.map((x) => x.value).toList());
  final out = <String, String>{};
  for (final x in parsed) {
    out[x.key] = resolve(x.value);
  }
  return out;
}
