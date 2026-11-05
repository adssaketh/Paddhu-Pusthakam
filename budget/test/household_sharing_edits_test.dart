// Rules for editing shared loans and deposits: what a viewer may write, and what the owner's phone
// accepts from the server. Run with: dart run test/household_sharing_edits_test.dart

import '../lib/struct/fixedDeposit.dart';
import '../lib/struct/householdSharedEditRules.dart';
import '../lib/struct/householdSharingRules.dart';
import '../lib/struct/loanSchedule.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

FixedDeposit deposit({String id = 'fd-1', String? wallet = 'owners-account'}) =>
    FixedDeposit(
      id: id,
      bank: 'Axis Bank',
      fdNumber: '123456',
      principal: 100000,
      ratePct: 7,
      startDate: DateTime(2026, 1, 1),
      maturityDate: DateTime(2027, 1, 1),
      walletPk: wallet,
      note: 'for the house',
    );

LoanTerms terms({Set<int>? paid, String? wallet = 'owners-account'}) => LoanTerms(
      principal: 120000,
      annualRatePct: 15,
      months: 12,
      emi: 10830,
      firstEmiDate: DateTime(2026, 1, 5),
      paidInstalments: paid ?? {1, 2},
      walletPk: wallet,
      note: 'owner note',
    );

Map<String, dynamic> loanPayload({String name = 'Instant loan', Object? t}) => {
      'objective': {'objectivePk': 'abc', 'name': name, 'amount': 1.0, 'walletFk': 'x'},
      'terms': t ?? terms().toJson(),
    };

void main() {
  // ---- times
  check(sharedEditTime(now: 500, heldUpdatedAt: 100) == 500, 'an edit gets the current time');
  check(sharedEditTime(now: 100, heldUpdatedAt: 100) == 101,
      'an edit is always later than the copy it started from');
  check(sharedEditTime(now: 50, heldUpdatedAt: 100) == 101,
      'a phone clock that is behind still makes the edit win');
  check(sharedEditConflicts(heldUpdatedAt: 100, serverUpdatedAt: 150),
      'a server copy changed meanwhile is a conflict');
  check(!sharedEditConflicts(heldUpdatedAt: 100, serverUpdatedAt: 100),
      'an unchanged server copy is no conflict');
  check(!sharedEditConflicts(heldUpdatedAt: 100, serverUpdatedAt: 90),
      'an older server copy is no conflict');

  check(sharedOwnerShouldApply(serverUpdatedAt: 200, localUpdatedAt: 100, uploadedAt: 100),
      "a member's newer edit is applied to the real item");
  check(!sharedOwnerShouldApply(serverUpdatedAt: 100, localUpdatedAt: 100, uploadedAt: 100),
      "the owner's own change coming back is not applied again");
  check(!sharedOwnerShouldApply(serverUpdatedAt: 200, localUpdatedAt: 300, uploadedAt: 100),
      'a newer edit made on the owner phone wins over a member edit');
  check(!sharedOwnerShouldApply(serverUpdatedAt: 200, localUpdatedAt: 100, uploadedAt: 200),
      'a change that was already applied is not applied twice');
  check(sharedOwnerShouldApply(serverUpdatedAt: 5, localUpdatedAt: 0, uploadedAt: 0),
      'a first change on a never sent item is applied');
  check(sharedRepairTime(localNewest: 100, serverUpdatedAt: 300) == 301,
      'a repair upload is later than the broken server copy');
  check(sharedRepairTime(localNewest: 500, serverUpdatedAt: 300) == 500,
      'a repair upload keeps a later local time');

  // ---- deposits
  final Map<String, dynamic> sent = sharedDepositPayload(deposit());
  check(!sent.containsKey('wallet'), "the owner's account is never sent");
  check(sent['bank'] == 'Axis Bank' && sent['principal'] == 100000, 'the rest of the deposit is sent');

  final FixedDeposit? ok = sharedDepositToApply(sent, 'fd-1');
  check(ok != null && ok.bank == 'Axis Bank', 'a good payload is accepted');
  check(sharedDepositToApply(sent, 'fd-2') == null, 'a payload about another deposit is refused');
  check(sharedDepositToApply('text', 'fd-1') == null, 'a payload that is not a map is refused');
  check(sharedDepositToApply({'id': 'fd-1'}, 'fd-1') == null, 'a payload without dates is refused');
  check(sharedDepositToApply({...sent, 'bank': '   '}, 'fd-1') == null, 'a blank bank is refused');
  check(sharedDepositToApply({...sent, 'principal': 0}, 'fd-1') == null, 'a zero amount is refused');
  check(sharedDepositToApply({...sent, 'principal': -5}, 'fd-1') == null, 'a negative amount is refused');
  check(sharedDepositToApply({...sent, 'rate': 250}, 'fd-1') == null, 'an absurd rate is refused');
  check(sharedDepositToApply({...sent, 'rate': -1}, 'fd-1') == null, 'a negative rate is refused');
  check(sharedDepositToApply({...sent, 'maturity': '2025-01-01T00:00:00.000'}, 'fd-1') == null,
      'a maturity before the start is refused');
  check(sharedDepositToApply({...sent, 'comp': 7}, 'fd-1') == null, 'an unknown compounding is refused');
  check(sharedDepositToApply({...sent, 'maturityAmount': 0}, 'fd-1') == null,
      'a zero bank maturity amount is refused');
  check(sharedDepositToApply({...sent, 'maturityAmount': 107500}, 'fd-1') != null,
      'a bank maturity amount is accepted');
  check(sharedDepositToApply({...sent, 'bank': 'B' * 300}, 'fd-1') == null, 'a very long bank name is refused');

  final FixedDeposit edited = FixedDeposit(
    id: 'fd-1',
    bank: ' HDFC ',
    principal: 150000,
    ratePct: 7.5,
    startDate: DateTime(2026, 1, 1),
    maturityDate: DateTime(2027, 6, 1),
    walletPk: 'a-wallet-the-viewer-sent',
    closed: true,
  );
  final FixedDeposit merged = sharedDepositForOwner(deposit(), edited);
  check(merged.bank == 'HDFC' && merged.principal == 150000 && merged.closed,
      "the viewer's changes are applied");
  check(merged.walletPk == 'owners-account', "the owner's account is kept, not taken from the server");
  check(sharedDepositForOwner(deposit(wallet: null), edited).walletPk == null,
      'a deposit without an account stays without one');
  check(sharedDepositForOwner(null, edited).walletPk == null, 'no account is invented');

  // ---- loans
  final SharedLoanEdit? loan = sharedLoanToApply(loanPayload());
  check(loan != null && loan.name == 'Instant loan' && loan.terms.months == 12, 'a good loan payload is accepted');
  check(loan != null && loan.terms.paidInstalments.length == 2, 'the ticked instalments come along');
  check(sharedLoanToApply(null) == null, 'nothing is refused safely');
  check(sharedLoanToApply({'terms': terms().toJson()}) == null, 'a loan without its row is refused');
  check(sharedLoanToApply({'objective': {'name': 'x'}}) == null, 'a loan without terms is refused');
  check(sharedLoanToApply(loanPayload(name: '  ')) == null, 'a blank loan name is refused');
  check(sharedLoanToApply(loanPayload(name: 'N' * 300)) == null, 'a very long loan name is refused');
  check(sharedLoanToApply(loanPayload(t: {...terms().toJson(), 'principal': 0})) == null,
      'a zero loan amount is refused');
  check(sharedLoanToApply(loanPayload(t: {...terms().toJson(), 'months': 0})) == null,
      'zero months is refused');
  check(sharedLoanToApply(loanPayload(t: {...terms().toJson(), 'months': 1000})) == null,
      'an absurd number of months is refused');
  check(sharedLoanToApply(loanPayload(t: {...terms().toJson(), 'rate': -3})) == null,
      'a negative rate is refused');
  check(sharedLoanToApply(loanPayload(t: {...terms().toJson(), 'gst': 500})) == null,
      'an absurd GST is refused');
  check(sharedLoanToApply(loanPayload(t: {...terms().toJson(), 'fee': -1})) == null,
      'a negative fee is refused');
  final SharedLoanEdit? trimmed =
      sharedLoanToApply(loanPayload(t: terms(paid: {0, 1, 5, 13, 99}).toJson()));
  check(trimmed != null && trimmed.terms.paidInstalments.length == 2 &&
          trimmed.terms.paidInstalments.containsAll({1, 5}),
      'ticked instalments outside 1..months are dropped');

  final LoanTerms ownersTerms = terms(wallet: 'owners-account');
  final LoanTerms fromViewer = ownersTerms.copyWith(principal: 100000, emi: 9000, walletPk: 'other', note: 'viewer note', paidInstalments: {1, 2, 3});
  final LoanTerms forOwner = sharedLoanTermsForOwner(ownersTerms, fromViewer);
  check(forOwner.principal == 100000 && forOwner.emi == 9000 && forOwner.paidInstalments.length == 3,
      "the viewer's changes are applied to the owner's loan terms");
  check(forOwner.walletPk == 'owners-account' && forOwner.note == 'owner note',
      "the owner's account and note are kept");
  check(sharedLoanAmount(ownersTerms) == summarize(ownersTerms).totalPayable,
      'the loan amount is worked out from the terms');

  // ---- what a viewer sends
  final Map<String, dynamic> out = sharedLoanPayloadFrom(
    oldPayload: loanPayload(),
    name: '  Car loan ',
    terms: fromViewer,
  );
  check((out['objective'] as Map)['name'] == 'Car loan', 'the new name goes out, trimmed');
  check((out['objective'] as Map)['objectivePk'] == 'abc', "the loan's own row fields stay as they were");
  check((out['objective'] as Map)['amount'] == sharedLoanAmount(fromViewer),
      'the amount is the total of the new terms');
  check((out['terms'] as Map)['principal'] == 100000, 'the new terms go out');
  final SharedLoanEdit? back = sharedLoanToApply(out);
  check(back != null && back.name == 'Car loan', 'what a viewer sends is accepted by the owner phone');
  check(sharedLoanPayloadFrom(oldPayload: {}, name: 'x', terms: fromViewer).containsKey('objective'),
      'a copy without a row still produces a payload');

  // ---- what has been paid: worked out on the owner's phone, kept when a viewer edits
  final Map<String, dynamic> withPaid = {...loanPayload(), 'paidSoFar': 45000.5};
  final Map<String, dynamic> editedWithPaid =
      sharedLoanPayloadFrom(oldPayload: withPaid, name: 'Car loan', terms: fromViewer);
  check(editedWithPaid['paidSoFar'] == 45000.5, "a viewer's edit keeps the owner's figure until a new one comes");
  check(!out.containsKey('paidSoFar'), 'a copy without a figure stays without one');
  check(sharedLoanToApply(editedWithPaid) != null, 'the extra figure does not make an edit unusable');
  check(sharedPaidChanged(sentPaid: null, paid: 0), 'a figure that was never sent counts as changed');
  check(!sharedPaidChanged(sentPaid: 100.0, paid: 100.004), 'a difference of less than a cent is not a change');
  check(sharedPaidChanged(sentPaid: 100.0, paid: 110), 'a new payment is a change');
  check(sharedPaidPushTime(localNewest: 100, serverUpdatedAt: 100, sentAt: 100, now: 500) == 500,
      'a changed figure is sent with the time of now');
  check(sharedPaidPushTime(localNewest: 900, serverUpdatedAt: 900, sentAt: 900, now: 500) == 900,
      'never earlier than the item\'s own newest change, even with a clock that is behind');
  check(sharedPaidPushTime(localNewest: 100, serverUpdatedAt: null, sentAt: 100, now: 500) == 500,
      'a server copy that is gone is sent again');
  check(sharedPaidPushTime(localNewest: 100, serverUpdatedAt: 300, sentAt: 100, now: 500) == null,
      "a member's edit that is waiting goes first, the figure does not overwrite it");

  // ---- the viewer may only write what the owner allowed (the same check the server rules make)
  final Set<String> members = {'owner', 'me', 'dad'};
  final SharedItemMeta allowed = SharedItemMeta(
      kind: kSharedKindFixedDeposit, ownerUid: 'owner', localId: 'fd-1', visibleTo: ['me'], membersCanEdit: true);
  final SharedItemMeta notAllowed = allowed.copyWith(membersCanEdit: false);
  check(
      sharedItemWriteError(existing: allowed, incoming: allowed, uid: 'me', memberUids: members) == null,
      'a viewer may write when the owner allowed edits');
  check(
      sharedItemWriteError(existing: notAllowed, incoming: notAllowed, uid: 'me', memberUids: members) != null,
      'a viewer may not write when the owner did not allow edits');
  check(
      sharedItemWriteError(existing: allowed, incoming: allowed.copyWith(visibleTo: ['me', 'dad']), uid: 'me', memberUids: members) != null,
      'a viewer may not change who can see the item');
  check(
      sharedItemWriteError(existing: allowed, incoming: allowed.copyWith(membersCanEdit: false), uid: 'me', memberUids: members) != null,
      'a viewer may not switch editing off for everybody');
  check(
      sharedItemWriteError(existing: allowed, incoming: allowed, uid: 'dad', memberUids: members) != null,
      'somebody the item is not shared with may not write');

  // ---- the owner's choice
  check(!sharedChoiceChanged(beforeVisibleTo: ['a', 'b'], beforeCanEdit: true, afterVisibleTo: ['b', 'a'], afterCanEdit: true),
      'the same people in another order is no change');
  check(sharedChoiceChanged(beforeVisibleTo: ['a'], beforeCanEdit: false, afterVisibleTo: ['a', 'b'], afterCanEdit: false),
      'adding a person is a change');
  check(sharedChoiceChanged(beforeVisibleTo: ['a', 'b'], beforeCanEdit: false, afterVisibleTo: ['a'], afterCanEdit: false),
      'removing a person is a change');
  check(sharedChoiceChanged(beforeVisibleTo: ['a'], beforeCanEdit: false, afterVisibleTo: ['a'], afterCanEdit: true),
      'allowing edits is a change');
  check(!sharedChoiceChanged(beforeVisibleTo: [], beforeCanEdit: false, afterVisibleTo: [], afterCanEdit: true),
      'the edit switch means nothing while nobody can see the item');
  check(sharedChoiceChanged(beforeVisibleTo: [], beforeCanEdit: false, afterVisibleTo: ['a'], afterCanEdit: false),
      'sharing something that was private is a change');
  check(sharedChoiceChanged(beforeVisibleTo: ['a'], beforeCanEdit: true, afterVisibleTo: [], afterCanEdit: true),
      'making something private again is a change');

  check(sharedWithLabel([]) == '', 'nobody gives no label');
  check(sharedWithLabel(['Asha']) == 'Shared with Asha', 'one person');
  check(sharedWithLabel(['Asha', 'Ravi']) == 'Shared with Asha and Ravi', 'two people');
  check(sharedWithLabel(['Asha', 'Ravi', 'Sam']) == 'Shared with Asha, Ravi and Sam', 'three people');
  check(sharedWithLabel(['Asha', 'Ravi', 'Sam', 'Lee', 'Kim']) == 'Shared with Asha, Ravi and 3 more',
      'more than three people are counted');

  print('all good');
}
