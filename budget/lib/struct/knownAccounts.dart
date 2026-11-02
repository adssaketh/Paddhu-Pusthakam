// Your names for the accounts, cards and schemes that instrumentParser.dart detects, and the Paddhu
// wallet each one is imported into (one wallet per bank, cards combined).
// Keys are "issuer:kind:last digits", as produced by instrumentKey().
// The names are the same list as in Ping (src/utils/instrument.ts, KNOWN_ACCOUNTS): change both together.

class KnownAccount {
  const KnownAccount(
    this.name, {
    this.closed = false,
    this.wallet = '',
    this.tickByDefault = true,
  });

  final String name;
  final bool closed;

  /// Paddhu wallet the transactions of this account go into when imported from Ping.
  final String wallet;

  /// false for pension / provident fund schemes: shown in the import list but not ticked.
  final bool tickByDefault;
}

const Map<String, KnownAccount> kKnownAccounts = {
  'axis:account:6372': KnownAccount('Saketh - Axis Savings Bank Account', wallet: 'Saketh - Axis'),
  'sbi:account:1327': KnownAccount('Saketh - SBI Savings Bank Account', wallet: 'Saketh - SBI'),
  'axis:credit_card:4498': KnownAccount('Saketh - Axis Bank Privilege Credit Card', wallet: 'Saketh - Axis'),
  'icici:credit_card:1000': KnownAccount('Saketh - ICICI Amazon Pay Credit Card', wallet: 'Saketh - ICICI'),
  'sbi_card:credit_card:3764': KnownAccount('Saketh - SBI IRCTC Platinum Credit Card', wallet: 'Saketh - SBI'),
  'yes:credit_card:3689': KnownAccount('Saketh - Kiwi Yes Bank Credit Card', wallet: 'Saketh - Yes Bank'),
  'yes:credit_card:': KnownAccount('Saketh - Kiwi Yes Bank Credit Card', wallet: 'Saketh - Yes Bank'),
  'hdfc:credit_card:0886': KnownAccount('Saketh - HDFC Indian Oil Credit Card', wallet: 'Saketh - HDFC'),
  'scapia:credit_card:visa': KnownAccount('Saketh - Federal Bank Scapia Visa Credit Card', wallet: 'Saketh - Federal'),
  'scapia:credit_card:rupay': KnownAccount('Federal Bank Scapia Rupay Credit Card (Saketh add-on or Mansa add-on)', wallet: 'Saketh - Federal'),
  'scapia:credit_card:': KnownAccount('Federal Bank Scapia Credit Card (Saketh Visa or Rupay, or Mansa add-on)', wallet: 'Saketh - Federal'),
  'federal:credit_card:1736': KnownAccount('Saketh - Federal Bank Scapia Visa Credit Card', wallet: 'Saketh - Federal'),
  'federal:credit_card:4278': KnownAccount('Saketh - Federal Bank Scapia Rupay Credit Card (add-on)', wallet: 'Saketh - Federal'),
  'bajaj:credit_card:0688': KnownAccount('Saketh - Bajaj Finserv EMI Card', wallet: 'Saketh - Bajaj Finserv'),
  'kfncra:account:0840': KnownAccount('Saketh - National Pension Scheme (NPS) Tier 1', wallet: 'Saketh - Pension & PF', tickByDefault: false),
  'ptnnps:account:7819': KnownAccount('Saketh - Atal Pension Yojana (APY)', wallet: 'Saketh - Pension & PF', tickByDefault: false),
  'epfoho:account:4895': KnownAccount('Saketh - Employee Provident Fund (EPF)', wallet: 'Saketh - Pension & PF', tickByDefault: false),
  'sbi:account:6919': KnownAccount('Mansa - SBI Savings Bank Account', wallet: 'Mansa - SBI'),
  'federal:account:7855': KnownAccount('Mansa - Federal Bank (Jupiter) Savings Account', wallet: 'Mansa - Federal'),
  'dopbnk:account:7718': KnownAccount('Mansa - India Post Payments Bank Savings Account (APY)', wallet: 'Mansa - India Post'),
  'ipbmsg:account:7716': KnownAccount('Mansa - India Post Payments Bank Digital Savings Account (PLI)', wallet: 'Mansa - India Post'),
  'icici:credit_card:5002': KnownAccount('Mansa - ICICI Coral Rupay Credit Card', wallet: 'Mansa - ICICI'),
  'federal:credit_card:3777': KnownAccount('Mansa - Federal Bank Scapia Rupay Credit Card (add-on)', wallet: 'Mansa - Federal'),
  'ptnnps:account:0727': KnownAccount('Mansa - Atal Pension Yojana (APY)', wallet: 'Mansa - Pension & PF', tickByDefault: false),
  'epfoho:account:4774': KnownAccount('Mansa - Employee Provident Fund (EPF)', wallet: 'Mansa - Pension & PF', tickByDefault: false),
  'icici:account:2090': KnownAccount('Saketh - ICICI Savings Account', wallet: 'Saketh - ICICI', closed: true),
  'au:account:1858': KnownAccount('Saketh - AU Small Finance Bank Savings Account', wallet: 'Saketh - AU', closed: true),
  'au:account:7280': KnownAccount('FD Account', wallet: 'Saketh - AU', closed: true),
  'federal:account:3269': KnownAccount('Federal Bank Account', wallet: 'Federal (closed)', closed: true),
  'federal:account:4365': KnownAccount('Federal Bank Account', wallet: 'Federal (closed)', closed: true),
  'federal:account:6299': KnownAccount('Federal Bank Account', wallet: 'Federal (closed)', closed: true),
  'icici:credit_card:8006': KnownAccount('ICICI Coral Rupay Credit Card', wallet: 'ICICI (closed)', closed: true),
  'federal:credit_card:9368': KnownAccount('Federal Signet Rupay Card', wallet: 'Federal (closed)', closed: true),
  'hdfc:credit_card:1170': KnownAccount('HDFC Swiggy Credit Card', wallet: 'Saketh - HDFC', closed: true),
  'axis:credit_card:1896': KnownAccount('Axis Indian Oil Credit Card', wallet: 'Saketh - Axis', closed: true),
  'axis:credit_card:2099': KnownAccount('Axis Myzone Credit Card', wallet: 'Saketh - Axis', closed: true),
  'idfcfb:credit_card:0932': KnownAccount('IDFC First Bank Millennia Credit Card', wallet: 'IDFC First (closed)', closed: true),
  'sbi_card:credit_card:3367': KnownAccount('SBI Credit Card', wallet: 'SBI Card (closed)', closed: true),
  'sbi_card:credit_card:6511': KnownAccount('SBI Credit Card', wallet: 'SBI Card (closed)', closed: true),
  'sbi_card:credit_card:3054': KnownAccount('SBI Credit Card', wallet: 'SBI Card (closed)', closed: true),
  'sbi:debit_card:3811': KnownAccount('Mansa - SBI Debit Card', wallet: 'Mansa - SBI', closed: true),
  'sbi:debit_card:2617': KnownAccount('Mansa - SBI Debit Card', wallet: 'Mansa - SBI'),
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
