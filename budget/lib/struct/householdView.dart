// Household view: "Everyone" or "Mine" for transaction lists and totals.
//
//  - Everyone (default in a household): the shared household ledger. Private transactions and
//    transactions that were kept personal when joining ("" owner) are left out, so the totals are
//    the same on every phone.
//  - Mine: everything this person owns, including private and personal ones.
//
// Outside a household nothing is filtered, so single-user mode is untouched.
//
// The pure helpers have no database or Flutter dependencies, so they can be checked with
// `dart run`. The SQL version of the same rule is householdViewFilter() in tables.dart.
// Editing and deleting rules (who may change which transaction) live here too.

import 'package:budget/struct/settings.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String kHouseholdViewKey = "householdView";
const String kHouseholdViewEveryone = "everyone";
const String kHouseholdViewMine = "mine";

/// True when [ownerUid] means "this person": not claimed yet (null), personal (""), or their uid.
bool householdOwnerIsMe(String? ownerUid, String myUid) =>
    ownerUid == null || ownerUid == "" || ownerUid == myUid;

/// The owner a copy of a transaction gets: a copy of a personal one ("") stays personal, every
/// other copy is a new entry of whoever makes it (null = not claimed yet).
String? householdOwnerUidForCopy(String? ownerUid) => ownerUid == "" ? "" : null;

/// Whether a transaction appears in the lists and totals of [view].
bool householdTransactionVisible({
  required bool inHousehold,
  required String view,
  required String? ownerUid,
  required bool isPrivate,
  required String myUid,
}) {
  if (!inHousehold) return true;
  if (view == kHouseholdViewMine) return householdOwnerIsMe(ownerUid, myUid);
  // Everyone: shared transactions only. null = just created and about to be claimed.
  if (isPrivate) return false;
  if (ownerUid == "") return false;
  return true;
}

/// Whether this person may edit a transaction. Members change only their own; the owner
/// of the household may not edit other people's entries either (they can ask for deletion rights).
bool householdCanEdit({
  required bool inHousehold,
  required String? ownerUid,
  required String myUid,
}) {
  if (!inHousehold) return true;
  return householdOwnerIsMe(ownerUid, myUid);
}

/// Whether this person may delete a transaction: their own, or anybody's when the owner
/// of the household granted them `canDelete`.
bool householdCanDelete({
  required bool inHousehold,
  required String? ownerUid,
  required String myUid,
  required bool memberCanDelete,
}) {
  if (!inHousehold) return true;
  return householdOwnerIsMe(ownerUid, myUid) || memberCanDelete;
}

// ---------------------------------------------------------------------------
// settings-backed helpers

bool get _inHousehold =>
    (appStateSettings["householdId"] ?? "").toString() != "";

/// The view chosen on this phone. Anything unknown counts as Everyone.
String get householdView =>
    appStateSettings[kHouseholdViewKey] == kHouseholdViewMine
        ? kHouseholdViewMine
        : kHouseholdViewEveryone;

/// True when lists and totals have to be limited by the household view.
bool get householdViewFilterActive => _inHousehold;

bool get householdViewIsMine =>
    _inHousehold && householdView == kHouseholdViewMine;

const String kHouseholdCanDeleteKey = "householdCanDelete";

/// The owner's "can delete others' transactions" permission for this person, as last seen here.
bool get householdMemberCanDelete =>
    appStateSettings[kHouseholdCanDeleteKey] == true;

String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? "";

/// Whether this person may edit a transaction that belongs to [ownerUid].
bool canEditTransactionOwnedBy(String? ownerUid) => householdCanEdit(
      inHousehold: _inHousehold,
      ownerUid: ownerUid,
      myUid: _myUid,
    );

/// Whether this person may delete a transaction that belongs to [ownerUid].
bool canDeleteTransactionOwnedBy(String? ownerUid) => householdCanDelete(
      inHousehold: _inHousehold,
      ownerUid: ownerUid,
      myUid: _myUid,
      memberCanDelete: householdMemberCanDelete,
    );

const String kCannotEditOthersMessage =
    "Only the person who added this transaction can change it.";
const String kCannotDeleteOthersMessage =
    "Only the person who added this transaction can delete it. "
    "The household owner can allow deleting others' transactions.";

/// Remembers the owner's permission on this phone (not synced between devices).
Future<void> saveHouseholdMemberCanDelete(bool canDelete) async {
  if (householdMemberCanDelete == canDelete) return;
  await updateSettings(kHouseholdCanDeleteKey, canDelete,
      updateGlobalState: false);
}

/// Remembers the view on this phone. Rebuilds the app so lists and totals pick it up.
Future<void> saveHouseholdView(String view) async {
  final String clean =
      view == kHouseholdViewMine ? kHouseholdViewMine : kHouseholdViewEveryone;
  if (householdView == clean) return;
  await updateSettings(kHouseholdViewKey, clean, updateGlobalState: true);
}
