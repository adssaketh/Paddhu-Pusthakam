// Household sharing of loans and fixed deposits, owner side: sends this person's shared items to the
// household in Cloud Firestore. The pure rules are in householdSharingRules.dart; the security rules are
// in firestore.rules (collection households/{h}/sharedItems/{docId}).
//
// How it works
//  - The owner decides per item who can see it and whether they may edit it. That choice is kept in the
//    setting `householdSharedOwn` ({docId: {kind, ownerUid, localId, visibleTo, membersCanEdit, _u, _d}}),
//    merged item by item between the person's own phones like loans and deposits are. An item that is not
//    in there is private (the default).
//  - What was last sent is kept on this phone only, in `householdSharedUploaded` ({docId: ms}). An item
//    needs sending while its newest change (the item itself, or its sharing choice) is newer than that,
//    so these rows are the offline queue: nothing is lost while the phone is offline.
//  - Before sending, the server copy is read. If somebody with edit rights changed it later, it is not
//    overwritten (sharedUploadAction). Applying that change to the real loan or deposit comes in a later step.
//  - Making an item private again, or deleting it, removes the server copy on the next sync.
//
// The payload of a fixed deposit is its settings entry without the account it points at (that account
// only exists on the owner's phone). The payload of a loan is its objective row (without the account)
// and its terms.

import 'dart:async';
import 'dart:math';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSharingRules.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/settingsMerge.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

/// The owner's choices about who sees what (merged between the person's own phones).
const String kSharedOwnKey = 'householdSharedOwn';

/// When each shared item was last sent from this phone (kept on this phone only).
const String kSharedUploadedKey = 'householdSharedUploaded';

const Duration _serverTimeout = Duration(seconds: 25);

Map<String, dynamic> _settingsMap(String key) {
  final dynamic stored = appStateSettings[key];
  return stored is Map
      ? {for (final MapEntry e in stored.entries) '${e.key}': e.value}
      : <String, dynamic>{};
}

int _updatedAtOf(dynamic item) =>
    item is Map && item['_u'] is num ? (item['_u'] as num).toInt() : 0;

String _docPath(String hid, String docId) => 'households/$hid/sharedItems/$docId';

// ---------------------------------------------------------------------------
// the owner's choices

/// The items this person shares right now (docId -> choice). Items made private again are left out.
Map<String, SharedItemMeta> ownSharedItems() {
  final Map<String, dynamic> all = _settingsMap(kSharedOwnKey);
  final Map<String, SharedItemMeta> out = {};
  for (final MapEntry<String, dynamic> e in all.entries) {
    if (isDeletedItem(e.value)) continue;
    final SharedItemMeta? meta = SharedItemMeta.fromJson(e.value);
    if (meta != null) out[e.key] = meta;
  }
  return out;
}

/// Who an item is shared with, or null when it is private.
SharedItemMeta? ownSharingOf(String kind, String localId) {
  final String uid = currentHouseholdUserUid;
  if (uid == "") return null;
  return ownSharedItems()[sharedItemDocId(kind, uid, localId)];
}

/// Sets who can see an item of mine and whether they may edit it. An empty [visibleTo] makes it private
/// again (the server copy is removed on the next sync). Returns an error message, or null when it worked.
Future<String?> setItemSharing({
  required String kind,
  required String localId,
  required List<String> visibleTo,
  required bool membersCanEdit,
}) async {
  if (!isInHousehold) return "Join or create a household first.";
  final String uid = currentHouseholdUserUid;
  if (uid == "") return "Sign in first.";
  if (!kSharedKinds.contains(kind) || localId.isEmpty) return "Unknown item.";

  final Set<String> memberUids = {...householdMemberNames.keys, uid};
  final List<String> clean = cleanVisibleTo(
    ownerUid: uid,
    requested: visibleTo,
    memberUids: memberUids,
  );
  final String docId = sharedItemDocId(kind, uid, localId);
  final Map<String, dynamic> all = _settingsMap(kSharedOwnKey);

  if (clean.isEmpty) {
    final dynamic existing = all[docId];
    if (existing == null || isDeletedItem(existing)) return null; // already private
    all[docId] = deletedMarker();
  } else {
    all[docId] = stampItem(SharedItemMeta(
      kind: kind,
      ownerUid: uid,
      localId: localId,
      visibleTo: clean,
      membersCanEdit: membersCanEdit,
    ).toJson());
  }
  await updateSettings(kSharedOwnKey, all, updateGlobalState: false);
  return null;
}

/// This phone left the household: nothing is shared any more and nothing waits to be sent.
/// (The loans and deposits themselves stay.)
Future<void> releaseSharedItems() async {
  if (_settingsMap(kSharedOwnKey).isNotEmpty) {
    await updateSettings(kSharedOwnKey, <String, dynamic>{},
        updateGlobalState: false);
  }
  if (_settingsMap(kSharedUploadedKey).isNotEmpty) {
    await updateSettings(kSharedUploadedKey, <String, dynamic>{},
        updateGlobalState: false);
  }
}

// ---------------------------------------------------------------------------
// reading the real item

class _LocalItem {
  const _LocalItem(this.payload, this.updatedAt);
  final Map<String, dynamic> payload;
  final int updatedAt;
}

Map<String, dynamic> _withoutBookkeeping(Map source) => {
      for (final MapEntry e in source.entries)
        if (e.key != '_u' && e.key != '_d') '${e.key}': e.value
    };

/// The item as it is on this phone now, or null when it does not exist any more.
Future<_LocalItem?> _localItem(String kind, String localId) async {
  if (kind == kSharedKindFixedDeposit) {
    final dynamic stored = appStateSettings["fixedDeposits"];
    if (stored is! List) return null;
    for (final dynamic j in stored) {
      if (j is Map && '${j['id']}' == localId && !isDeletedItem(j)) {
        final Map<String, dynamic> payload = _withoutBookkeeping(j)
          ..remove('wallet'); // an account of the owner's phone
        return _LocalItem(payload, _updatedAtOf(j));
      }
    }
    return null;
  }

  final List<Objective> rows = await (database.select(database.objectives)
        ..where((o) => o.objectivePk.equals(localId)))
      .get();
  if (rows.isEmpty) return null;
  final Objective row = rows.first;
  final Map<String, dynamic> objective = row.toJson()..remove('walletFk');
  final dynamic allTerms = appStateSettings["loanTerms"];
  final dynamic terms = allTerms is Map ? allTerms[localId] : null;
  final bool hasTerms = terms is Map && !isDeletedItem(terms);
  return _LocalItem(
    {
      'objective': objective,
      if (hasTerms) 'terms': _withoutBookkeeping(terms),
    },
    max(row.dateTimeModified?.millisecondsSinceEpoch ?? 0,
        hasTerms ? _updatedAtOf(terms) : 0),
  );
}

// ---------------------------------------------------------------------------
// sending

/// How many shared items still wait to be sent (for a status line).
Future<int> countWaitingSharedItems() async {
  try {
    final Map<String, dynamic> uploaded = _settingsMap(kSharedUploadedKey);
    final Map<String, dynamic> all = _settingsMap(kSharedOwnKey);
    int waiting = 0;
    for (final MapEntry<String, dynamic> e in all.entries) {
      if (isDeletedItem(e.value)) {
        if (uploaded.containsKey(e.key)) waiting++;
        continue;
      }
      final SharedItemMeta? meta = SharedItemMeta.fromJson(e.value);
      if (meta == null) continue;
      final _LocalItem? local = await _localItem(meta.kind, meta.localId);
      if (local == null) {
        if (uploaded.containsKey(e.key)) waiting++;
        continue;
      }
      final int newest = max(local.updatedAt, meta.updatedAt);
      final dynamic sent = uploaded[e.key];
      if (sent is! num || newest > sent) waiting++;
    }
    return waiting;
  } catch (e) {
    return 0;
  }
}

/// Sends what is waiting. Called from syncHouseholdNow() after the server was reached, so an exception
/// from the network simply leaves everything queued for the next time. One item the rules refuse does not
/// hold back the others.
Future<void> uploadSharedItems(
    FirebaseFirestore db, String hid, String uid) async {
  final Map<String, dynamic> own = _settingsMap(kSharedOwnKey);
  final Map<String, dynamic> uploaded = _settingsMap(kSharedUploadedKey);
  if (own.isEmpty && uploaded.isEmpty) return;

  final Set<String> memberUids = householdMemberNames.keys.toSet();
  bool ownChanged = false;
  bool uploadedChanged = false;

  try {
    for (final String docId in List<String>.of(own.keys)) {
      final dynamic item = own[docId];

      // Made private again: take the server copy away.
      if (isDeletedItem(item)) {
        if (uploaded.containsKey(docId)) {
          if (await _deleteServerCopy(db, hid, docId)) {
            uploaded.remove(docId);
            uploadedChanged = true;
          }
        }
        continue;
      }

      SharedItemMeta? meta = SharedItemMeta.fromJson(item);
      if (meta == null || meta.ownerUid != uid) continue;

      // The real loan or deposit was deleted: stop sharing it.
      final _LocalItem? local = await _localItem(meta.kind, meta.localId);
      if (local == null) {
        if (await _deleteServerCopy(db, hid, docId)) {
          own[docId] = deletedMarker();
          uploaded.remove(docId);
          ownChanged = true;
          uploadedChanged = true;
        }
        continue;
      }

      // Somebody who left the household is taken out of the list (the rules would refuse it).
      if (memberUids.isNotEmpty) {
        final List<String> pruned = cleanVisibleTo(
            ownerUid: uid, requested: meta.visibleTo, memberUids: memberUids);
        if (pruned.length != meta.visibleTo.length) {
          if (pruned.isEmpty) {
            own[docId] = deletedMarker();
            ownChanged = true;
            continue; // becomes private, the server copy goes on the next round
          }
          meta = meta.copyWith(
              visibleTo: pruned,
              updatedAt: DateTime.now().millisecondsSinceEpoch);
          own[docId] = stampItem(meta.toJson());
          ownChanged = true;
        }
      }

      final int newest = max(local.updatedAt, meta.updatedAt);
      final dynamic sent = uploaded[docId];
      if (sent is num && newest <= sent) continue; // nothing new

      try {
        final int? serverU = await _serverUpdatedAt(db, hid, docId);
        final SharedUploadAction action = sharedUploadAction(
            localUpdatedAt: newest, serverUpdatedAt: serverU);
        if (action == SharedUploadAction.takeRemote) {
          // Somebody with edit rights changed it later. It is kept as it is on the server;
          // applying it to the real item on this phone is done by a later step.
          continue;
        }
        if (action == SharedUploadAction.upload) {
          await db
              .doc(_docPath(hid, docId))
              .set({
                ...meta.toJson(),
                '_u': newest,
                'payload': local.payload,
              })
              .timeout(_serverTimeout);
        }
        uploaded[docId] = newest;
        uploadedChanged = true;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          print("Household shared items: refused ${meta.kind} $docId");
          continue;
        }
        rethrow;
      }
    }
  } finally {
    // Keep what was done even when the connection dropped half way.
    if (ownChanged) {
      await updateSettings(kSharedOwnKey, own, updateGlobalState: false);
    }
    if (uploadedChanged) {
      await updateSettings(kSharedUploadedKey, uploaded,
          updateGlobalState: false);
    }
  }
}

/// The `_u` of the server copy, or null when it is not there (or cannot be read).
Future<int?> _serverUpdatedAt(
    FirebaseFirestore db, String hid, String docId) async {
  try {
    final DocumentSnapshot<Map<String, dynamic>> doc = await db
        .doc(_docPath(hid, docId))
        .get(const GetOptions(source: Source.server))
        .timeout(_serverTimeout);
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    return data['_u'] is num ? (data['_u'] as num).toInt() : 0;
  } on TimeoutException {
    rethrow; // offline: leave everything queued
  } catch (e) {
    return null; // not there
  }
}

/// Deletes the server copy. true when it is gone (or was never there or is not mine to delete).
Future<bool> _deleteServerCopy(
    FirebaseFirestore db, String hid, String docId) async {
  try {
    await db.doc(_docPath(hid, docId)).delete().timeout(_serverTimeout);
    return true;
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied' || e.code == 'not-found') return true;
    rethrow;
  }
}
