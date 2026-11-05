// Household view, edit and delete rules, and which accounts are hidden.
// Run with: dart run test/household_visibility_test.dart

import '../lib/struct/householdViewRules.dart';
import '../lib/struct/householdWalletRules.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

bool visible({
  bool inHousehold = true,
  String view = kHouseholdViewEveryone,
  String? ownerUid = 'me',
  bool isPrivate = false,
}) =>
    householdTransactionVisible(
      inHousehold: inHousehold,
      view: view,
      ownerUid: ownerUid,
      isPrivate: isPrivate,
      myUid: 'me',
    );

void main() {
  // ---- owner is me
  check(householdOwnerIsMe(null, 'me'), 'unclaimed row counts as mine');
  check(householdOwnerIsMe('', 'me'), 'personal row counts as mine');
  check(householdOwnerIsMe('me', 'me'), 'own row counts as mine');
  check(!householdOwnerIsMe('other', 'me'), "another member's row is not mine");

  // ---- single-user mode: nothing is filtered
  check(visible(inHousehold: false, ownerUid: 'other', isPrivate: true),
      'outside a household everything is visible');
  check(visible(inHousehold: false, view: kHouseholdViewMine, ownerUid: 'other'),
      'outside a household the view does not matter');

  // ---- Everyone: shared transactions only
  check(visible(ownerUid: 'me'), 'Everyone shows my shared transaction');
  check(visible(ownerUid: 'other'), "Everyone shows another member's shared transaction");
  check(visible(ownerUid: null), 'Everyone shows a row that is about to be claimed');
  check(!visible(ownerUid: 'me', isPrivate: true), 'Everyone hides my private transaction');
  check(!visible(ownerUid: 'other', isPrivate: true), "Everyone hides another member's private transaction");
  check(!visible(ownerUid: ''), 'Everyone hides transactions kept personal when joining');

  // ---- Mine: everything I own
  check(visible(view: kHouseholdViewMine, ownerUid: 'me'), 'Mine shows my transaction');
  check(visible(view: kHouseholdViewMine, ownerUid: 'me', isPrivate: true), 'Mine shows my private transaction');
  check(visible(view: kHouseholdViewMine, ownerUid: ''), 'Mine shows my personal transaction');
  check(visible(view: kHouseholdViewMine, ownerUid: null), 'Mine shows an unclaimed row');
  check(!visible(view: kHouseholdViewMine, ownerUid: 'other'), "Mine hides another member's transaction");

  // ---- edit
  check(householdCanEdit(inHousehold: false, ownerUid: 'other', myUid: 'me'), 'single user can edit everything');
  check(householdCanEdit(inHousehold: true, ownerUid: 'me', myUid: 'me'), 'I can edit my own');
  check(householdCanEdit(inHousehold: true, ownerUid: null, myUid: 'me'), 'I can edit an unclaimed row');
  check(householdCanEdit(inHousehold: true, ownerUid: '', myUid: 'me'), 'I can edit my personal row');
  check(!householdCanEdit(inHousehold: true, ownerUid: 'other', myUid: 'me'), "I cannot edit another member's");

  // ---- delete
  check(householdCanDelete(inHousehold: false, ownerUid: 'other', myUid: 'me', memberCanDelete: false), 'single user can delete everything');
  check(householdCanDelete(inHousehold: true, ownerUid: 'me', myUid: 'me', memberCanDelete: false), 'I can delete my own');
  check(!householdCanDelete(inHousehold: true, ownerUid: 'other', myUid: 'me', memberCanDelete: false), "I cannot delete another member's by default");
  check(householdCanDelete(inHousehold: true, ownerUid: 'other', myUid: 'me', memberCanDelete: true), "I can delete another member's when the owner allowed it");

  // ---- copies
  check(householdOwnerUidForCopy('other') == null, "a copy of another member's row is claimed by whoever copies");
  check(householdOwnerUidForCopy('me') == null, 'a copy of my row is claimed by me');
  check(householdOwnerUidForCopy(null) == null, 'a copy of an unclaimed row stays unclaimed');
  check(householdOwnerUidForCopy('') == '', 'a copy of a personal row stays personal');

  // ---- placeholder accounts
  check(placeholderWalletPk('abc') == 'hh_abc', 'placeholder account id');
  check(isPlaceholderWalletPk('hh_abc'), 'placeholder account is recognised');
  check(!isPlaceholderWalletPk('0'), 'normal account is not a placeholder');
  check(!isPlaceholderWalletPk('my_hh_wallet'), 'prefix only counts at the start');
  check(householdWalletIsHidden(walletPk: 'hh_abc', balancesShown: false), 'placeholder hidden while balances are off');
  check(!householdWalletIsHidden(walletPk: 'hh_abc', balancesShown: true), 'placeholder shown when the owner switches balances on');
  check(!householdWalletIsHidden(walletPk: '0', balancesShown: false), 'own account is never hidden');

  print('household visibility: all checks passed');
}
