// Household sharing of loans and fixed deposits, viewer side: keeps on this phone the copies of the
// loans and deposits that OTHER members chose to share with this person. The owner side (sending) is
// householdSharedItems.dart; the pure rules are householdSharingRules.dart and householdSharedCopyRules.dart.
//
// How it works
//  - The download side (householdDownload.dart) listens to
//      households/{h}/sharedItems   where visibleTo array-contains me
//    and hands every snapshot to applySharedItemsSnapshot().
//  - The copies are stored as setting `householdSharedCopies` ({docId: document}). That key is in
//    kSettingsNotSynced, so Drive sync between this person's own phones does not copy it. It is NOT the
//    person's own `loanTerms`, `fixedDeposits` or loans table, so shared items never reach their net worth,
//    loan totals, home lines or maturity reminders.
//  - A copy is replaced only by a newer one (`_u`). A document that disappears from the server (the owner
//    deleted it, made it private, took this person off the list, or left the household) is dropped here too:
//    a "removed" change drops it at once, and a snapshot straight from the server also drops anything held
//    that the server no longer shows. A snapshot that only came from the phone's own cache never does that,
//    because an empty cache would look like "everything was taken away".
//  - Copies are read only for now. Editing a copy the owner allowed to edit comes with the editors.
//
// The owner's own items are never stored here: they are the real loan or deposit.

import 'dart:convert';

import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSharedCopyRules.dart';
import 'package:budget/struct/householdSharingRules.dart';
import 'package:budget/struct/settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/foundation.dart';

export 'package:budget/struct/householdSharedCopyRules.dart';
export 'package:budget/struct/householdSharingRules.dart';

/// Other members' shared items, as last seen on this phone (kept on this phone only).
const String kSharedCopiesKey = 'householdSharedCopies';

/// Goes up whenever the copies change, so a list that is open rebuilds itself.
final ValueNotifier<int> sharedCopiesVersion = ValueNotifier<int>(0);

/// One loan or deposit somebody shared with this person.
class SharedCopy {
  const SharedCopy({
    required this.docId,
    required this.meta,
    required this.payload,
    required this.canEdit,
  });

  final String docId;
  final SharedItemMeta meta;

  /// The loan (`objective` and `terms`) or the deposit, as the owner sent it.
  final Map<String, dynamic> payload;

  /// The owner allowed this person to change it (used by the editors, not by the lists).
  final bool canEdit;

  String get kind => meta.kind;
  String get ownerUid => meta.ownerUid;

  /// Who shared it, by the nickname they use in the household.
  String get ownerName => householdMemberName(meta.ownerUid);
}

Map<String, dynamic> _stored() {
  final dynamic raw = appStateSettings[kSharedCopiesKey];
  return raw is Map
      ? {for (final MapEntry e in raw.entries) '${e.key}': e.value}
      : <String, dynamic>{};
}

int _updatedAtOf(dynamic doc) =>
    doc is Map && doc['_u'] is num ? (doc['_u'] as num).toInt() : 0;

/// A plain JSON copy of a server document, or null when it holds something that cannot be saved with the
/// settings (every settings save encodes all settings, so one bad value must never get in).
Map<String, dynamic>? _jsonSafe(Map<String, dynamic> data) {
  try {
    final dynamic copy = jsonDecode(jsonEncode(data));
    return copy is Map<String, dynamic> ? copy : null;
  } catch (e) {
    return null;
  }
}

/// The copies of [kind] ('loan' or 'fd') that this person may see right now. Items of somebody who is no
/// longer in the household are left out (sharedItemVisible), and so is anything of this person's own.
List<SharedCopy> visibleSharedCopies(String kind) {
  if (!isInHousehold) return [];
  final String me = currentHouseholdUserUid;
  if (me == "") return [];
  final Set<String> memberUids = {...householdMemberNames.keys, me};
  final List<SharedCopy> out = [];
  for (final MapEntry<String, dynamic> e in _stored().entries) {
    final SharedItemMeta? meta = SharedItemMeta.fromJson(e.value);
    if (meta == null || meta.kind != kind || meta.ownerUid == me) continue;
    final dynamic payload = (e.value as Map)['payload'];
    if (payload is! Map) continue;
    if (!sharedItemVisible(item: meta, uid: me, memberUids: memberUids)) {
      continue;
    }
    out.add(SharedCopy(
      docId: e.key,
      meta: meta,
      payload: {for (final MapEntry p in payload.entries) '${p.key}': p.value},
      canEdit: sharedItemCanEdit(item: meta, uid: me, memberUids: memberUids),
    ));
  }
  return out;
}

/// True when this person has at least one shared item of [kind] to look at.
bool hasVisibleSharedCopies(String kind) => visibleSharedCopies(kind).isNotEmpty;

/// Applies one snapshot of `sharedItems where visibleTo array-contains me`.
Future<void> applySharedItemsSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, String myUid) async {
  if (myUid == "") return;
  final Map<String, dynamic> stored = _stored();
  bool changed = false;

  final Map<String, int> incomingUpdatedAt = {};
  final Map<String, Map<String, dynamic>> incoming = {};

  for (final DocumentChange<Map<String, dynamic>> change
      in snapshot.docChanges) {
    final String docId = change.doc.id;
    if (change.type == DocumentChangeType.removed) {
      // Deleted, made private, or this person was taken off the list.
      if (stored.remove(docId) != null) changed = true;
      continue;
    }
    final Map<String, dynamic>? data = change.doc.data();
    if (data == null || !sharedDocIsUsable(docId, data)) continue;
    final SharedItemMeta? meta = SharedItemMeta.fromJson(data);
    if (meta == null || meta.ownerUid == myUid) continue; // my own are the real items
    final Map<String, dynamic>? safe = _jsonSafe(data);
    if (safe == null) {
      print("Household shared items: skipped $docId, it cannot be saved");
      continue;
    }
    incoming[docId] = safe;
    incomingUpdatedAt[docId] = _updatedAtOf(safe);
  }

  final Set<String> toWrite = sharedDocIdsToWrite(
    heldUpdatedAt: {
      for (final MapEntry<String, dynamic> e in stored.entries)
        e.key: _updatedAtOf(e.value)
    },
    incomingUpdatedAt: incomingUpdatedAt,
  );
  for (final String docId in toWrite) {
    stored[docId] = incoming[docId];
    changed = true;
  }

  // A snapshot straight from the server is the whole truth about what this person can see now.
  if (!snapshot.metadata.isFromCache) {
    final Set<String> gone = sharedCopiesToRemove(
      heldDocIds: stored.keys.toSet(),
      visibleDocIds: {for (final doc in snapshot.docs) doc.id},
    );
    for (final String docId in gone) {
      stored.remove(docId);
      changed = true;
    }
  }

  if (!changed) return;
  await _save(stored);
}

Future<void> _save(Map<String, dynamic> stored) async {
  await updateSettings(kSharedCopiesKey, stored, updateGlobalState: false);
  sharedCopiesVersion.value++;
}

/// This person left the household or was removed: every copy of somebody else's item goes.
/// (Their own loans and deposits are not copies and stay.)
Future<void> releaseSharedCopies() async {
  final Map<String, dynamic> stored = _stored();
  if (stored.isEmpty) return;
  final Set<String> drop = sharedCopiesToDropOnLeave(
    heldOwnerByDocId: {
      for (final MapEntry<String, dynamic> e in stored.entries)
        e.key: e.value is Map ? '${(e.value as Map)['ownerUid'] ?? ''}' : ''
    },
    myUid: currentHouseholdUserUid,
  );
  for (final String docId in drop) {
    stored.remove(docId);
  }
  await _save(stored);
}
