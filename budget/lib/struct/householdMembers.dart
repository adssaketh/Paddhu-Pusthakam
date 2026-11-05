// Names of the household members, kept on this phone so rows, filters and the spending view
// can say who added a transaction without asking the server.
//
// The names come from households/{h}/members (the members listener in householdDownload.dart
// saves them here). They are stored as setting `householdMemberNames` ({uid: nickname}), which is
// in kSettingsNotSynced, and are cleared when this person leaves the household.
//
// The pure helpers have no database or Flutter dependencies, so they can be checked with `dart run`.

import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/settings.dart';

const String kHouseholdMemberNamesKey = "householdMemberNames";
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

// ---------------------------------------------------------------------------
// settings-backed helpers

/// {uid: nickname} as last seen on this phone.
Map<String, String> get householdMemberNames {
  final dynamic raw = appStateSettings[kHouseholdMemberNamesKey];
  if (raw is! Map) return {};
  return {
    for (final MapEntry entry in raw.entries)
      entry.key.toString(): (entry.value ?? "").toString(),
  };
}

/// The name for [uid]; never empty.
String householdMemberName(String uid) {
  final String name = (householdMemberNames[uid] ?? "").trim();
  return name == "" ? kHouseholdUnknownMemberName : name;
}

/// The label for the person who added a transaction owned by [ownerUid] (see householdOwnerLabelFor).
String? householdOwnerLabel(String? ownerUid) => householdOwnerLabelFor(
      inHousehold: isInHousehold,
      ownerUid: ownerUid,
      myUid: currentHouseholdUserUid,
      names: householdMemberNames,
    );

/// Remembers the member names on this phone. Does nothing when they did not change.
Future<void> saveHouseholdMemberNames(Map<String, String> names) async {
  final Map<String, String> current = householdMemberNames;
  final bool same = current.length == names.length &&
      names.entries.every((entry) => current[entry.key] == entry.value);
  if (same) return;
  await updateSettings(kHouseholdMemberNamesKey, names,
      updateGlobalState: false);
}

Future<void> clearHouseholdMemberNames() async {
  if (householdMemberNames.isEmpty) return;
  await updateSettings(kHouseholdMemberNamesKey, <String, String>{},
      updateGlobalState: false);
}
