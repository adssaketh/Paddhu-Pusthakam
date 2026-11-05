// Rules for the copies of other people's shared loans and deposits that a phone keeps.
// Run with: dart run test/household_sharing_copies_test.dart

import '../lib/struct/fixedDeposit.dart';
import '../lib/struct/householdSharedCopyRules.dart';
import '../lib/struct/householdSharingRules.dart';
import '../lib/struct/loanSchedule.dart';
import '../lib/struct/settingsMerge.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

Map<String, dynamic> doc({
  String kind = kSharedKindFixedDeposit,
  String owner = 'sis',
  String localId = 'fd-1',
  Object? payload = const <String, dynamic>{'bank': 'Axis Bank'},
  int updatedAt = 100,
}) =>
    {
      'kind': kind,
      'ownerUid': owner,
      'localId': localId,
      'visibleTo': ['me'],
      'membersCanEdit': false,
      '_u': updatedAt,
      'payload': payload,
    };

void main() {
  // ---- which server documents can be kept
  check(sharedDocIsUsable('fd-sis-fd-1', doc()), 'a well formed document is kept');
  check(sharedDocIsUsable('loan-sis-abc', doc(kind: kSharedKindLoan, localId: 'abc')),
      'a loan document is kept');
  check(!sharedDocIsUsable('fd-dad-fd-1', doc()),
      'an id that does not start with kind-owner- is skipped');
  check(!sharedDocIsUsable('loan-sis-fd-1', doc()),
      'an id with the wrong kind is skipped');
  check(!sharedDocIsUsable('fd-sis-fd-1', doc(payload: 'not a map')),
      'a document whose payload is not a map is skipped');
  final Map<String, dynamic> noPayload = doc()..remove('payload');
  check(!sharedDocIsUsable('fd-sis-fd-1', noPayload), 'a document without a payload is skipped');
  check(!sharedDocIsUsable('fd-sis-fd-1', doc(kind: 'stock')), 'an unknown kind is skipped');
  check(!sharedDocIsUsable('fd--fd-1', doc(owner: '')), 'a document without an owner is skipped');
  check(!sharedDocIsUsable('fd-sis-fd-1', null), 'nothing is skipped safely');

  // ---- which incoming documents are written
  check(
      sharedDocIdsToWrite(heldUpdatedAt: {}, incomingUpdatedAt: {'a': 5}).contains('a'),
      'a copy this phone does not have yet is written');
  check(
      sharedDocIdsToWrite(heldUpdatedAt: {'a': 5}, incomingUpdatedAt: {'a': 6}).contains('a'),
      'a newer copy replaces the held one');
  check(
      sharedDocIdsToWrite(heldUpdatedAt: {'a': 5}, incomingUpdatedAt: {'a': 5}).isEmpty,
      'the same change coming again is not written twice');
  check(
      sharedDocIdsToWrite(heldUpdatedAt: {'a': 9}, incomingUpdatedAt: {'a': 5}).isEmpty,
      'an older copy never replaces a newer one');
  final Set<String> mixed = sharedDocIdsToWrite(
    heldUpdatedAt: {'a': 5, 'b': 5, 'c': 5},
    incomingUpdatedAt: {'a': 6, 'b': 5, 'd': 1},
  );
  check(mixed.length == 2 && mixed.contains('a') && mixed.contains('d'),
      'only the new and the newer ones are written from a mixed batch');

  // ---- what is shown of a loan
  check(sharedLoanName({'objective': {'name': 'Instant loan'}}) == 'Instant loan', 'the loan name is read');
  check(sharedLoanName({'objective': {'name': '   '}}) == 'Loan', 'a blank loan name falls back');
  check(sharedLoanName({}) == 'Loan', 'a loan without its row falls back');
  check(sharedLoanName({'objective': 'x'}) == 'Loan', 'a loan row of the wrong type falls back');
  check(sharedLoanArchived({'objective': {'archived': true}}), 'an archived loan is recognised');
  check(!sharedLoanArchived({'objective': {'archived': false}}), 'a loan that is not archived');
  check(!sharedLoanArchived({}), 'a loan without its row is not archived');

  final LoanTerms terms = LoanTerms(
    principal: 120000,
    annualRatePct: 15,
    months: 12,
    emi: 10830,
    firstEmiDate: DateTime(2026, 1, 5),
    paidInstalments: {1, 2},
    walletPk: 'owners-account',
  );
  final LoanTerms? read = sharedLoanTerms({'terms': terms.toJson()});
  check(read != null && read.emi == 10830 && read.months == 12, 'the terms of a loan are read');
  check(read != null && read.paidInstalments.length == 2, 'the ticked instalments come along');
  check(sharedLoanTerms({'objective': {'name': 'x'}}) == null, 'a loan without terms has none');
  check(sharedLoanTerms({'terms': {'months': 0}}) == null, 'broken terms are not used');
  final LoanProgress progress = loanProgress(read!, 0);
  check(progress.repaid > 0 && progress.fraction > 0 && progress.fraction < 1,
      'progress counts the ticked instalments only (a viewer has no linked payments)');

  // ---- what is shown of a deposit
  final FixedDeposit fd = FixedDeposit(
    id: 'fd-1',
    bank: 'Axis Bank',
    fdNumber: '123456',
    principal: 100000,
    ratePct: 7,
    startDate: DateTime(2026, 1, 1),
    maturityDate: DateTime(2027, 1, 1),
    walletPk: 'owners-account',
    note: 'for the house',
  );
  final FixedDeposit? shown = sharedDeposit(fd.toJson());
  check(shown != null && shown.bank == 'Axis Bank' && shown.principal == 100000,
      'a deposit is read');
  check(shown != null && shown.walletPk == null,
      "the owner's account is never used on a viewer's phone");
  check(shown != null && shown.note == 'for the house', 'the note comes along');
  check(sharedDeposit({'bank': 'Axis Bank'}) == null, 'a deposit without dates is not shown');
  check(sharedDeposit({}) == null, 'an empty payload is not a deposit');

  // ---- copies stay out of everything that is synced or totalled
  check(!isSyncedSettingKey('householdSharedCopies'),
      "copies of other people's items are not copied to my other phones");
  check(!kSettingsCollections.contains('householdSharedCopies'),
      'copies are not merged item by item like my own loans and deposits');
  check(isSyncedSettingKey('fixedDeposits') && isSyncedSettingKey('loanTerms'),
      'my own loans and deposits are still kept in step between my phones');
  // sharedCopiesToRemove / sharedCopiesToDropOnLeave themselves are checked in household_sharing_test.dart

  print('all good');
}
