// Pure rules about who may be in a household and who may hand it over.
// No imports on purpose, so tests can run this file with plain `dart test`.

/// Soft limit. Firestore rules cannot count members, so it is checked when the owner
/// creates an invite code.
const int kMaxHouseholdMembers = 8;

/// True when no more people may be invited ([memberCount] includes the owner).
bool householdMemberLimitReached(int memberCount) =>
    memberCount >= kMaxHouseholdMembers;

/// Why [newOwnerUid] cannot become the owner, or null when the hand-over is fine.
/// [memberUids] are the ids of everyone in the household right now.
String? householdTransferError({
  required bool iAmOwner,
  required String myUid,
  required String newOwnerUid,
  required Set<String> memberUids,
}) {
  if (!iAmOwner) return "Only the owner can hand over the household.";
  if (newOwnerUid == "") return "Pick a member.";
  if (newOwnerUid == myUid) return "You are already the owner.";
  if (!memberUids.contains(newOwnerUid)) {
    return "That person is no longer in the household.";
  }
  if (!memberUids.contains(myUid)) return "You are not in this household.";
  return null;
}
