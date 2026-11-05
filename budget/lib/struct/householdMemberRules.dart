// Pure rules for showing who added a transaction.
// No imports on purpose, so tests can run this file with plain `dart run`.

const String kHouseholdUnknownMemberName = "Member";

/// First letter of a name, upper case ("?" when there is none).
String householdInitial(String name) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) return "?";
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// A stable number below [count] for a member, used to pick the colour of their tag.
/// It is the same on every phone and every run.
int householdMemberColorIndex(String uid, int count) {
  if (count <= 0) return 0;
  int hash = 0;
  for (final int unit in uid.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash % count;
}

/// The name shown for the person who added a transaction.
/// Null (no label) when not in a household, for personal transactions (owner ""), and when
/// nobody else is in the household, so a single person never sees labels.
/// A transaction nobody owns yet (null) is this person's own.
String? householdOwnerLabelFor({
  required bool inHousehold,
  required String? ownerUid,
  required String myUid,
  required Map<String, String> names,
}) {
  if (!inHousehold) return null;
  if (ownerUid == "") return null;
  if (names.length <= 1) return null;
  final String uid = ownerUid ?? myUid;
  if (uid == "") return null;
  final String name = (names[uid] ?? "").trim();
  return name == "" ? kHouseholdUnknownMemberName : name;
}
