// Pure helpers for merging household data that arrives from the server.
// No imports on purpose, so tests can run this file with plain `dart run`.

/// True when [remote] is a later edit than [local]. A missing time counts as the oldest.
bool householdRemoteIsNewer(DateTime? remote, DateTime? local) {
  if (remote == null) return false;
  if (local == null) return true;
  return remote.isAfter(local);
}

/// True when [ownerUid] belongs to somebody else in the household (not this person, not "personal").
bool householdIsForeignOwner(String? ownerUid, String myUid) =>
    ownerUid != null && ownerUid != "" && ownerUid != myUid;

// ---------------------------------------------------------------------------
// Reconciling this phone with the server (state based, not event based)
//
// A live listener only reports changes it sees. A document deleted while the listener was off
// (app closed, offline, signed out) never produces a "removed" event, so a ghost row would stay
// on this phone for ever, and an own row that is missing on the server would never go back up.
// So after every full (non-cache) snapshot the phone compares what it holds with the ids the
// server returned and corrects both sides.

/// What the reconcile step needs to know about one local row.
class HouseholdLocalRow {
  final String pk;
  final String? ownerUid; // null new, "" personal, uid shared by that person
  final DateTime? syncedAt;
  const HouseholdLocalRow(this.pk, this.ownerUid, this.syncedAt);
}

class HouseholdReconcilePlan {
  /// Other members' rows that are no longer on the server: remove them here.
  final List<String> deletePks;

  /// My own rows that are missing on the server (and were not deleted here): upload them again.
  final List<String> reuploadPks;
  const HouseholdReconcilePlan(this.deletePks, this.reuploadPks);
}

/// [serverIds] is everything this person can read on the server (shared rows plus own private
/// rows). [deletedHere] are rows deleted on this phone whose deletion may not have gone out yet.
/// A row uploaded less than [grace] ago is left alone: the snapshot may simply be older than the upload.
HouseholdReconcilePlan householdReconcilePlan({
  required List<HouseholdLocalRow> local,
  required Set<String> serverIds,
  required Set<String> deletedHere,
  required String myUid,
  required DateTime now,
  Duration grace = const Duration(minutes: 2),
}) {
  final List<String> deletePks = [];
  final List<String> reuploadPks = [];
  for (final HouseholdLocalRow row in local) {
    if (serverIds.contains(row.pk)) continue;
    if (householdIsForeignOwner(row.ownerUid, myUid)) {
      deletePks.add(row.pk);
    } else if (row.ownerUid == myUid &&
        row.syncedAt != null &&
        !deletedHere.contains(row.pk) &&
        now.difference(row.syncedAt!) > grace) {
      reuploadPks.add(row.pk);
    }
  }
  return HouseholdReconcilePlan(deletePks, reuploadPks);
}

/// Who owns a row after a server document arrives: the server always decides.
/// True when the local row must be replaced by the document, whatever its sync state.
bool householdServerOwnerWins({
  required String? localOwnerUid,
  required String serverOwnerId,
}) =>
    localOwnerUid != serverOwnerId;
