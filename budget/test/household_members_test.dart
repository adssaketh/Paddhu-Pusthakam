// Who-added-it labels, tag colours, spending per member, merge rules.
// Run with: dart run test/household_members_test.dart

import '../lib/struct/householdMemberRules.dart';
import '../lib/struct/householdMergeRules.dart';
import '../lib/struct/householdSpendingRules.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

String? label({
  bool inHousehold = true,
  String? ownerUid,
  Map<String, String> names = const {'me': 'Saketh', 'sis': 'Anu'},
}) =>
    householdOwnerLabelFor(
      inHousehold: inHousehold,
      ownerUid: ownerUid,
      myUid: 'me',
      names: names,
    );

void main() {
  // ---- initial
  check(householdInitial('anu') == 'A', 'initial is upper case');
  check(householdInitial('  saketh') == 'S', 'initial ignores leading spaces');
  check(householdInitial('') == '?', 'empty name gives ?');
  check(householdInitial('   ') == '?', 'blank name gives ?');
  check(householdInitial('కర') == 'క', 'initial works for non-Latin names');

  // ---- colour index
  check(householdMemberColorIndex('abc', 6) == householdMemberColorIndex('abc', 6), 'colour is stable');
  check(householdMemberColorIndex('abc', 6) >= 0 && householdMemberColorIndex('abc', 6) < 6, 'colour is within range');
  check(householdMemberColorIndex('abc', 0) == 0, 'no colours gives 0');
  check(householdMemberColorIndex('', 5) == 0, 'empty uid gives 0');
  final Set<int> seen = {
    for (final String uid in ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8'])
      householdMemberColorIndex(uid, 8),
  };
  check(seen.length > 1, 'different members do not all get the same colour');

  // ---- owner label
  check(label(inHousehold: false, ownerUid: 'sis') == null, 'no label outside a household');
  check(label(ownerUid: '') == null, 'no label for personal rows');
  check(label(ownerUid: 'sis') == 'Anu', "label is the member's nickname");
  check(label(ownerUid: 'me') == 'Saketh', 'label for my own rows');
  check(label(ownerUid: null) == 'Saketh', 'an unclaimed row is mine');
  check(label(ownerUid: 'sis', names: const {'me': 'Saketh'}) == null, 'a household of one shows no labels');
  check(label(ownerUid: 'sis', names: const {}) == null, 'no names known gives no label');
  check(label(ownerUid: 'gone') == kHouseholdUnknownMemberName, 'a removed member shows the fallback name');
  check(label(ownerUid: 'sis', names: const {'me': 'Saketh', 'sis': '  '}) == kHouseholdUnknownMemberName, 'blank nickname shows the fallback name');

  // ---- spending per member
  final rows = <({String? ownerUid, double amount})>[
    (ownerUid: 'me', amount: -100),
    (ownerUid: 'sis', amount: 250),
    (ownerUid: null, amount: 50), // unclaimed counts as mine
    (ownerUid: '', amount: 999), // personal is never counted
    (ownerUid: 'sis', amount: -50),
  ];
  final grouped = groupSpendingByOwner(rows, myUid: 'me');
  check(grouped.length == 2, 'two members have spending');
  check(grouped.first.uid == 'sis' && grouped.first.total == 300 && grouped.first.count == 2, 'biggest spender first, amounts added without sign');
  check(grouped.last.uid == 'me' && grouped.last.total == 150 && grouped.last.count == 2, 'unclaimed rows are added to me');
  check(groupSpendingByOwner(const [], myUid: 'me').isEmpty, 'no rows gives an empty list');
  check(groupSpendingByOwner([(ownerUid: null, amount: 10)], myUid: '').isEmpty, 'nobody signed in counts nothing');

  // ---- merge: last writer wins
  final DateTime t1 = DateTime(2026, 11, 1, 10);
  final DateTime t2 = DateTime(2026, 11, 1, 11);
  check(householdRemoteIsNewer(t2, t1), 'later remote edit wins');
  check(!householdRemoteIsNewer(t1, t2), 'older remote edit does not overwrite');
  check(!householdRemoteIsNewer(t1, t1), 'same time does not overwrite');
  check(householdRemoteIsNewer(t1, null), 'a local row without a time counts as oldest');
  check(!householdRemoteIsNewer(null, t1), 'a remote row without a time never wins');
  check(!householdRemoteIsNewer(null, null), 'nothing to compare means no change');

  // ---- merge: whose row is it
  check(householdIsForeignOwner('sis', 'me'), "another member's row is foreign");
  check(!householdIsForeignOwner('me', 'me'), 'my row is not foreign');
  check(!householdIsForeignOwner('', 'me'), 'personal row is not foreign');
  check(!householdIsForeignOwner(null, 'me'), 'unclaimed row is not foreign');

  print('household members and merge: all checks passed');
}
