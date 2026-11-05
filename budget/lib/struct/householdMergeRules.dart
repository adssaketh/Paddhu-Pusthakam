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
