// Your names for the accounts, cards and schemes that instrumentParser.dart detects.
// Keys are "issuer:kind:last digits", as produced by instrumentKey().
// The same list lives in Ping (src/utils/instrument.ts, KNOWN_ACCOUNTS): change both together.

class KnownAccount {
  const KnownAccount(this.name, {this.closed = false});

  final String name;
  final bool closed;
}

const Map<String, KnownAccount> kKnownAccounts = {
  'axis:account:6372': KnownAccount('Saketh - Axis Savings Bank Account'),
  'sbi:account:1327': KnownAccount('Saketh - SBI Savings Bank Account'),
  'axis:credit_card:4498': KnownAccount('Saketh - Axis Bank Privilege Credit Card'),
  'icici:credit_card:1000': KnownAccount('Saketh - ICICI Amazon Pay Credit Card'),
  'sbi_card:credit_card:3764': KnownAccount('Saketh - SBI IRCTC Platinum Credit Card'),
  'yes:credit_card:3689': KnownAccount('Saketh - Kiwi Yes Bank Credit Card'),
  'yes:credit_card:': KnownAccount('Saketh - Kiwi Yes Bank Credit Card'),
  'hdfc:credit_card:0886': KnownAccount('Saketh - HDFC Indian Oil Credit Card'),
  'scapia:credit_card:visa': KnownAccount('Saketh - Federal Bank Scapia Visa Credit Card'),
  'scapia:credit_card:rupay': KnownAccount('Federal Bank Scapia Rupay Credit Card (Saketh add-on or Mansa add-on)'),
  'scapia:credit_card:': KnownAccount('Federal Bank Scapia Credit Card (Saketh Visa or Rupay, or Mansa add-on)'),
  'federal:credit_card:1736': KnownAccount('Saketh - Federal Bank Scapia Visa Credit Card'),
  'federal:credit_card:4278': KnownAccount('Saketh - Federal Bank Scapia Rupay Credit Card (add-on)'),
  'bajaj:credit_card:0688': KnownAccount('Saketh - Bajaj Finserv EMI Card'),
  'kfncra:account:0840': KnownAccount('Saketh - National Pension Scheme (NPS) Tier 1'),
  'ptnnps:account:7819': KnownAccount('Saketh - Atal Pension Yojana (APY)'),
  'epfoho:account:4895': KnownAccount('Saketh - Employee Provident Fund (EPF)'),
  'sbi:account:6919': KnownAccount('Mansa - SBI Savings Bank Account'),
  'federal:account:7855': KnownAccount('Mansa - Federal Bank (Jupiter) Savings Account'),
  'dopbnk:account:7718': KnownAccount('Mansa - India Post Payments Bank Savings Account (APY)'),
  'ipbmsg:account:7716': KnownAccount('Mansa - India Post Payments Bank Digital Savings Account (PLI)'),
  'icici:credit_card:5002': KnownAccount('Mansa - ICICI Coral Rupay Credit Card'),
  'federal:credit_card:3777': KnownAccount('Mansa - Federal Bank Scapia Rupay Credit Card (add-on)'),
  'ptnnps:account:0727': KnownAccount('Mansa - Atal Pension Yojana (APY)'),
  'epfoho:account:4774': KnownAccount('Mansa - Employee Provident Fund (EPF)'),
  'icici:account:2090': KnownAccount('Saketh - ICICI Savings Account', closed: true),
  'au:account:1858': KnownAccount('Saketh - AU Small Finance Bank Savings Account', closed: true),
  'au:account:7280': KnownAccount('FD Account', closed: true),
  'federal:account:3269': KnownAccount('Federal Bank Account', closed: true),
  'federal:account:4365': KnownAccount('Federal Bank Account', closed: true),
  'federal:account:6299': KnownAccount('Federal Bank Account', closed: true),
  'icici:credit_card:8006': KnownAccount('ICICI Coral Rupay Credit Card', closed: true),
  'federal:credit_card:9368': KnownAccount('Federal Signet Rupay Card', closed: true),
  'hdfc:credit_card:1170': KnownAccount('HDFC Swiggy Credit Card', closed: true),
  'axis:credit_card:1896': KnownAccount('Axis Indian Oil Credit Card', closed: true),
  'axis:credit_card:2099': KnownAccount('Axis Myzone Credit Card', closed: true),
  'idfcfb:credit_card:0932': KnownAccount('IDFC First Bank Millennia Credit Card', closed: true),
  'sbi_card:credit_card:3367': KnownAccount('SBI Credit Card', closed: true),
  'sbi_card:credit_card:6511': KnownAccount('SBI Credit Card', closed: true),
  'sbi_card:credit_card:3054': KnownAccount('SBI Credit Card', closed: true),
  'sbi:debit_card:3811': KnownAccount('Mansa - SBI Debit Card', closed: true),
  'sbi:debit_card:2617': KnownAccount('Mansa - SBI Debit Card'),
};

/// Looks up the name for an instrument key. An exact key wins. Otherwise it matches on the ending
/// digits (a single SMS may print "XX090" for 2090) and on the issuer, where a longer sender name
/// such as "cpptnnps" or "adipbmsg" counts as the registered "ptnnps" or "ipbmsg".
KnownAccount? knownAccountFor(String instrumentKey) {
  final exact = kKnownAccounts[instrumentKey];
  if (exact != null) return exact;
  final p = instrumentKey.split(':');
  if (p.length != 3 || p[2].length < 3) return null;
  for (final e in kKnownAccounts.entries) {
    final q = e.key.split(':');
    if (q.length != 3 || q[2].isEmpty || !q[2].endsWith(p[2])) continue;
    if (q[0] == p[0] || (q[0].length >= 5 && p[0].contains(q[0]))) {
      return e.value;
    }
  }
  return null;
}
