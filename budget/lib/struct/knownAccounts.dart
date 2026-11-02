// Your names for the accounts, cards and wallets that instrumentParser.dart detects.
// Keys are "issuer:kind:last digits", exactly as produced by instrumentKey().
// The same list lives in Ping (src/utils/instrument.ts, KNOWN_ACCOUNTS): change both together.

class KnownAccount {
  const KnownAccount(this.name, {this.closed = false});

  final String name;
  final bool closed;
}

const Map<String, KnownAccount> kKnownAccounts = {
  'sbi:account:6919': KnownAccount('Mansa - SBI Savings Account'),
  'axis:account:6372': KnownAccount('Saketh - Axis Savings Account'),
  'icici:account:2090': KnownAccount('Saketh - ICICI Savings Account', closed: true),
  'au:account:1858': KnownAccount('Saketh - AU Small Finance Bank Savings Account', closed: true),
  'au:account:7280': KnownAccount('FD Account', closed: true),
  'adipbmsg:account:7716': KnownAccount('Mansa - Post Office Digital Account (PLI)'),
  'addopbnk:account:7718': KnownAccount('Mansa - Post Office Savings Account (APY)'),
  'btdopbnk:account:7718': KnownAccount('Mansa - Post Office Savings Account (APY)'),
  'axdopbnk:account:7718': KnownAccount('Mansa - Post Office Savings Account (APY)'),
  'dopbnk:account:7718': KnownAccount('Mansa - Post Office Savings Account (APY)'),
  'federal:account:3269': KnownAccount('Federal Bank Account', closed: true),
  'federal:account:4365': KnownAccount('Federal Bank Account', closed: true),
  'federal:account:6299': KnownAccount('Federal Bank Account', closed: true),
  'federal:unknown:': KnownAccount('Federal Bank Account', closed: true),
  'icici:credit_card:1000': KnownAccount('ICICI Amazon Pay Credit Card'),
  'icici:credit_card:8006': KnownAccount('ICICI Coral Rupay Credit Card', closed: true),
  'federal:credit_card:9368': KnownAccount('Federal Signet Rupay Card', closed: true),
  'federal:credit_card:': KnownAccount('Federal Signet Rupay Card', closed: true),
  'yes:credit_card:3689': KnownAccount('Kiwi Yes Bank Credit Card'),
  'yes:credit_card:': KnownAccount('Kiwi Yes Bank Credit Card'),
  'hdfc:credit_card:1170': KnownAccount('HDFC Swiggy Credit Card', closed: true),
  'hdfc:credit_card:0886': KnownAccount('HDFC Indian Oil Credit Card'),
  'axis:credit_card:1896': KnownAccount('Axis Indian Oil Credit Card', closed: true),
  'axis:credit_card:2099': KnownAccount('Axis Myzone Credit Card', closed: true),
  'idfcfb:credit_card:0932': KnownAccount('IDFC First Bank Millennia Credit Card', closed: true),
  'sbi_card:credit_card:3367': KnownAccount('SBI Credit Card', closed: true),
  'sbi_card:credit_card:6511': KnownAccount('SBI Credit Card', closed: true),
  'sbi_card:credit_card:3054': KnownAccount('SBI Credit Card', closed: true),
  'sbi_card:credit_card:3764': KnownAccount('SBI IRCTC Platinum Credit Card'),
  'sbi:debit_card:3811': KnownAccount('Mansa - SBI Debit Card', closed: true),
  'sbi:debit_card:2617': KnownAccount('Mansa - SBI Debit Card'),
};

/// Looks up the name for an instrument key. A single SMS sometimes prints fewer digits than the
/// full key ("XX090" instead of 2090) or just says "card" instead of "credit card"; Ping tidies
/// that by looking at all messages together, here we match on the ending of the digits instead.
KnownAccount? knownAccountFor(String instrumentKey) {
  final exact = kKnownAccounts[instrumentKey];
  if (exact != null) return exact;
  final p = instrumentKey.split(':');
  if (p.length != 3 || p[2].length < 3) return null;
  final kind = p[1] == 'card' ? 'credit_card' : p[1];
  for (final e in kKnownAccounts.entries) {
    final q = e.key.split(':');
    if (q.length == 3 && q[0] == p[0] && q[1] == kind && q[2].endsWith(p[2])) {
      return e.value;
    }
  }
  return null;
}
