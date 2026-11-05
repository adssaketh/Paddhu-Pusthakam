// Pure rules for the copies of other people's shared loans and fixed deposits that a phone keeps.
// No Flutter or database imports, so tests can run this file with plain `dart run`.
//
// A copy is what the household's server document looked like the last time this phone saw it:
//   {kind, ownerUid, localId, visibleTo, membersCanEdit, _u, payload}
// (see householdSharingRules.dart). Copies are kept apart from the person's own loans and deposits, so
// nothing here can ever end up in their net worth, loan totals or reminders.

import 'fixedDeposit.dart';
import 'householdSharingRules.dart';
import 'loanSchedule.dart';

/// True when [data] (a server document with id [docId]) can be kept as a copy. This mirrors what the
/// Firestore rules enforce when it is written (kind, an owner, a payload, an id that starts with
/// `kind-ownerUid-`), so a malformed document is skipped instead of breaking the list.
bool sharedDocIsUsable(String docId, dynamic data) {
  final SharedItemMeta? meta = SharedItemMeta.fromJson(data);
  if (meta == null) return false;
  if (data is! Map || data['payload'] is! Map) return false;
  return docId.startsWith('${meta.kind}-${meta.ownerUid}-');
}

/// Which of the incoming documents are written to this phone: the ones it does not have yet, and the ones
/// whose time (`_u`) is newer than the copy it has. An equal time is the same change coming again.
/// Both maps are docId -> `_u` in milliseconds.
Set<String> sharedDocIdsToWrite({
  required Map<String, int> heldUpdatedAt,
  required Map<String, int> incomingUpdatedAt,
}) {
  final Set<String> out = {};
  for (final MapEntry<String, int> e in incomingUpdatedAt.entries) {
    final int? held = heldUpdatedAt[e.key];
    if (held == null ||
        sharedRemoteIsNewer(localUpdatedAt: held, remoteUpdatedAt: e.value)) {
      out.add(e.key);
    }
  }
  return out;
}

/// What a viewer sees of a loan: its name, whether it is archived on the owner's phone, and its terms.
/// Anything missing falls back to something harmless instead of throwing.
String sharedLoanName(Map payload) {
  final dynamic o = payload['objective'];
  final String name = o is Map ? '${o['name'] ?? ''}'.trim() : '';
  return name.isEmpty ? 'Loan' : name;
}

bool sharedLoanArchived(Map payload) {
  final dynamic o = payload['objective'];
  return o is Map && o['archived'] == true;
}

/// The loan's terms, or null when the owner has not set any (an ordinary loan without a schedule).
/// The account the terms point at lives on the owner's phone and is ignored here.
LoanTerms? sharedLoanTerms(Map payload) => LoanTerms.fromJson(payload['terms']);

/// What the owner's phone says has been paid so far (ticked instalments plus payments recorded as
/// transactions), or null when the payload has no usable figure (an older version of the app sent it).
double? sharedLoanPaidSoFar(Map payload) {
  final dynamic v = payload['paidSoFar'];
  if (v is! num || !v.isFinite || v < 0 || v > 1e12) return null;
  return v.toDouble();
}

/// How far a shared loan is paid. Uses the owner's own figure when there is one; otherwise only the
/// ticked instalments are known (the payments the owner recorded as transactions are not on this phone).
LoanProgress sharedLoanProgress(Map payload, LoanTerms terms) {
  final double? paid = sharedLoanPaidSoFar(payload);
  return paid == null
      ? loanProgress(terms, 0)
      : LoanProgress(summarize(terms).totalPayable, paid);
}

/// The deposit in a copy, or null when it cannot be read. The account it points at lives on the owner's
/// phone, so it is dropped.
FixedDeposit? sharedDeposit(Map payload) {
  final FixedDeposit? fd = FixedDeposit.fromJson(payload);
  if (fd == null) return null;
  // copyWith cannot clear walletPk, so the deposit is rebuilt without it.
  return FixedDeposit(
    id: fd.id,
    bank: fd.bank,
    fdNumber: fd.fdNumber,
    principal: fd.principal,
    ratePct: fd.ratePct,
    startDate: fd.startDate,
    maturityDate: fd.maturityDate,
    compounding: fd.compounding,
    maturityAmount: fd.maturityAmount,
    closed: fd.closed,
    note: fd.note,
    fromSms: fd.fromSms,
    smsId: fd.smsId,
  );
}
