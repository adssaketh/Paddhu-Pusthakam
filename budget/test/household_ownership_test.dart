// Member limit and ownership transfer rules.
// Run with: dart run test/household_ownership_test.dart

import '../lib/struct/householdOwnership.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

String? transfer({
  bool iAmOwner = true,
  String myUid = 'me',
  String newOwnerUid = 'sis',
  Set<String> members = const {'me', 'sis', 'dad'},
}) =>
    householdTransferError(
      iAmOwner: iAmOwner,
      myUid: myUid,
      newOwnerUid: newOwnerUid,
      memberUids: members,
    );

void main() {
  // ---- limit
  check(kMaxHouseholdMembers == 8, 'a household can have 8 people');
  check(!householdMemberLimitReached(1), 'one person: more can join');
  check(!householdMemberLimitReached(7), 'seven people: one more can join');
  check(householdMemberLimitReached(8), 'eight people: the household is full');
  check(householdMemberLimitReached(9), 'more than eight counts as full');

  // ---- transfer
  check(transfer() == null, 'owner can hand over to a member');
  check(transfer(iAmOwner: false) != null, 'a member cannot hand over');
  check(transfer(newOwnerUid: '') != null, 'a member must be picked');
  check(transfer(newOwnerUid: 'me') != null, 'cannot hand over to yourself');
  check(transfer(newOwnerUid: 'gone') != null, 'cannot hand over to someone who left');
  check(transfer(members: const {'sis', 'dad'}) != null, 'cannot hand over when I am not in the household');
  check(transfer(members: const {'me', 'sis'}) == null, 'two-person household can hand over');

  print('household ownership: all checks passed');
}
