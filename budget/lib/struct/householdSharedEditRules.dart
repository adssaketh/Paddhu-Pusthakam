// Pure rules for editing shared loans and fixed deposits inside a household.
// No Flutter or database imports, so tests can run this file with plain `dart run`.
//
// Two people can change the same item:
//   - a viewer the owner allowed to edit (membersCanEdit) writes a new payload to the server copy;
//   - the owner's phone then applies that payload to the real loan or deposit.
// What comes from the server is somebody else's input, so before it touches a real loan or deposit it is
// checked here: it must be readable, it must be about the same item, and the account of the owner's phone
// is never taken from it.

import 'dart:math';

import 'fixedDeposit.dart';
import 'loanSchedule.dart';

/// The longest name or bank name that is accepted (the same limit the database has for names).
const int kSharedNameLimit = 250;

// ---------------------------------------------------------------------------
// times

/// The time put on an edit: now, but always later than the copy that was edited, even when the two
/// phones' clocks differ, so the edit wins over the copy it started from.
int sharedEditTime({required int now, required int heldUpdatedAt}) =>
    max(now, heldUpdatedAt + 1);

/// True when the server copy changed after the one the viewer started editing from. The edit is then
/// refused instead of overwriting somebody else's change.
bool sharedEditConflicts(
        {required int heldUpdatedAt, required int serverUpdatedAt}) =>
    serverUpdatedAt > heldUpdatedAt;

/// True when the owner's phone should apply the server copy to the real item: it is newer than the real
/// item, and newer than what this phone itself last sent or applied (an equal time is its own change
/// coming back). A newer edit made on this phone wins.
bool sharedOwnerShouldApply({
  required int serverUpdatedAt,
  required int localUpdatedAt,
  required int uploadedAt,
}) =>
    serverUpdatedAt > localUpdatedAt && serverUpdatedAt > uploadedAt;

/// The time for an upload that repairs the server copy (its payload could not be used): it must be
/// later than what the server holds, or the viewers would keep the broken copy.
int sharedRepairTime({required int localNewest, required int serverUpdatedAt}) =>
    max(localNewest, serverUpdatedAt + 1);

// ---------------------------------------------------------------------------
// fixed deposits

/// A deposit as it goes to the household: without the account (that only exists on the owner's phone).
Map<String, dynamic> sharedDepositPayload(FixedDeposit fd) =>
    fd.toJson()..remove('wallet');

/// The deposit in a server payload, or null when it must not be applied: it cannot be read, it is about
/// another deposit than [localId], or its values make no sense.
FixedDeposit? sharedDepositToApply(dynamic payload, String localId) {
  if (payload is! Map) return null;
  final FixedDeposit? fd = FixedDeposit.fromJson(payload);
  if (fd == null || fd.id != localId) return null;
  if (fd.bank.trim().isEmpty || fd.bank.length > kSharedNameLimit) return null;
  if (!fd.principal.isFinite || fd.principal <= 0) return null;
  if (!(fd.ratePct >= 0 && fd.ratePct <= 100)) return null;
  if (!fd.maturityDate.isAfter(fd.startDate)) return null;
  if (!kFdCompoundingNames.containsKey(fd.compounding)) return null;
  final double? stated = fd.maturityAmount;
  if (stated != null && !(stated > 0 && stated.isFinite)) return null;
  return fd;
}

/// The deposit to save on the owner's phone: everything from [remote] except the account, which stays
/// the one the owner chose ([local] is the deposit as it is on this phone now).
FixedDeposit sharedDepositForOwner(FixedDeposit? local, FixedDeposit remote) =>
    FixedDeposit(
      id: remote.id,
      bank: remote.bank.trim(),
      fdNumber: remote.fdNumber,
      principal: remote.principal,
      ratePct: remote.ratePct,
      startDate: remote.startDate,
      maturityDate: remote.maturityDate,
      compounding: remote.compounding,
      maturityAmount: remote.maturityAmount,
      walletPk: local?.walletPk,
      closed: remote.closed,
      note: remote.note,
      fromSms: remote.fromSms,
      smsId: remote.smsId,
    );

// ---------------------------------------------------------------------------
// loans

/// What a viewer's edit changes on a loan: its name and its terms.
class SharedLoanEdit {
  const SharedLoanEdit(this.name, this.terms);
  final String name;
  final LoanTerms terms;
}

/// The name and terms in a server payload of a loan, or null when it must not be applied (unreadable,
/// no name, no terms, or values that make no sense). Ticked instalments outside 1..months are dropped.
SharedLoanEdit? sharedLoanToApply(dynamic payload) {
  if (payload is! Map) return null;
  final dynamic objective = payload['objective'];
  if (objective is! Map) return null;
  final String name = '${objective['name'] ?? ''}'.trim();
  if (name.isEmpty || name.length > kSharedNameLimit) return null;
  final LoanTerms? t = LoanTerms.fromJson(payload['terms']);
  if (t == null) return null;
  if (!t.principal.isFinite || t.principal <= 0) return null;
  if (t.months < 1 || t.months > 600) return null;
  if (!(t.annualRatePct >= 0 && t.annualRatePct <= 200)) return null;
  if (!(t.emi >= 0 && t.emi.isFinite)) return null;
  if (!(t.feeAmount >= 0 && t.feeAmount.isFinite)) return null;
  if (!(t.gstPct >= 0 && t.gstPct <= 100)) return null;
  final Set<int> paid = {
    for (final int n in t.paidInstalments)
      if (n >= 1 && n <= t.months) n
  };
  return SharedLoanEdit(name, t.copyWith(paidInstalments: paid));
}

/// The terms to save on the owner's phone: everything from [remote] except the account and the note,
/// which stay as the owner has them.
LoanTerms sharedLoanTermsForOwner(LoanTerms local, LoanTerms remote) =>
    LoanTerms(
      principal: remote.principal,
      annualRatePct: remote.annualRatePct,
      months: remote.months,
      emi: remote.emi,
      firstEmiDate: remote.firstEmiDate,
      feeAmount: remote.feeAmount,
      gstPct: remote.gstPct,
      feePaid: remote.feePaid,
      paidInstalments: remote.paidInstalments,
      walletPk: local.walletPk,
      note: local.note,
    );

/// The loan's total to pay, which is what its row keeps as the amount (the owner's phone works it out
/// itself and never takes an amount from the server).
double sharedLoanAmount(LoanTerms terms) => summarize(terms).totalPayable;

/// A viewer's edited loan as it goes to the household: the copy's own row with the new name and amount,
/// and the new terms.
Map<String, dynamic> sharedLoanPayloadFrom({
  required Map oldPayload,
  required String name,
  required LoanTerms terms,
}) {
  final dynamic old = oldPayload['objective'];
  final Map<String, dynamic> objective = {
    if (old is Map)
      for (final MapEntry e in old.entries) '${e.key}': e.value
  };
  objective['name'] = name.trim();
  objective['amount'] = sharedLoanAmount(terms);
  return {'objective': objective, 'terms': terms.toJson()};
}

// ---------------------------------------------------------------------------
// the owner's choice

/// True when the choice differs from what it was. The order of people does not matter, and while nobody
/// can see the item the edit switch does not matter either.
bool sharedChoiceChanged({
  required Iterable<String> beforeVisibleTo,
  required bool beforeCanEdit,
  required Iterable<String> afterVisibleTo,
  required bool afterCanEdit,
}) {
  final Set<String> before = beforeVisibleTo.toSet();
  final Set<String> after = afterVisibleTo.toSet();
  if (before.length != after.length || !before.containsAll(after)) return true;
  if (after.isEmpty) return false;
  return beforeCanEdit != afterCanEdit;
}

/// "Shared with Asha and Ravi", or an empty string when nobody can see it.
String sharedWithLabel(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return 'Shared with ${names[0]}';
  if (names.length == 2) return 'Shared with ${names[0]} and ${names[1]}';
  if (names.length == 3) {
    return 'Shared with ${names[0]}, ${names[1]} and ${names[2]}';
  }
  return 'Shared with ${names[0]}, ${names[1]} and ${names.length - 2} more';
}
