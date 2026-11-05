// Pure rules for the household view and for who may edit or delete a transaction.
// No imports on purpose, so tests can run this file with plain `dart run`.

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
