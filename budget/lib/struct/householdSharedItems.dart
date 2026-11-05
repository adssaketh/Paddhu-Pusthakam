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
//    overwritten (sharedUploadAction): that change is applied to the real loan or deposit instead.
//  - The same happens without waiting for an upload: the download side listens to the person's own shared
//    items (`ownerUid == me`) and hands every changed document to applyOwnSharedItemsSnapshot().
//  - What a member sent is somebody else's input. It is checked first (householdSharedEditRules.dart); the
//    account of the owner's phone, the loan's row identity and the loan's amount are never taken from it.
//    If it cannot be used, the server copy is repaired from the real item.
//  - Making an item private again, or deleting it, removes the server copy on the next sync.
//
// The payload of a fixed deposit is its settings entry without the account it points at (that account
// only exists on the owner's phone). The payload of a loan is its objective row (without the account)
// and its terms.

import 'dart:async';
import 'dart:math';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/fixedDepositStore.dart';
import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSharedCopyRules.dart';
import 'package:budget/struct/householdSharedEditRules.dart';
import 'package:budget/struct/householdSharingRules.dart';
import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/loanTerms.dart';
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

// One thing at a time touches the "what was sent" list: an upload and the applying of a member's edit
// must not overwrite each other's bookkeeping. (Choosing who sees an item does not wait for this.)
Future<void> _sharedLock = Future.value();

Future<T> _withSharedLock<T>(Future<T> Function() body) {
  final Completer<T> done = Completer<T>();
  _sharedLock = _sharedLock.then((_) async {
    try {
      done.complete(await body());
    } catch (e, s) {
      done.completeError(e, s);
    }
  });
  return done.future;
}

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

/// Deletes every shared item of mine from the server. Used when I leave: it has to happen BEFORE my
/// membership is deleted, because the rules only let a member delete. Throws when it fails (so leaving
/// can be refused instead of leaving items behind).
Future<void> deleteOwnSharedItemsOnServer(
    FirebaseFirestore db, String hid, String uid) async {
  final QuerySnapshot<Map<String, dynamic>> mine = await db
      .collection('households/$hid/sharedItems')
      .where('ownerUid', isEqualTo: uid)
      .get(const GetOptions(source: Source.server))
      .timeout(_serverTimeout);
  // A batch holds at most 500 writes.
  for (int start = 0; start < mine.docs.length; start += 400) {
    final WriteBatch batch = db.batch();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in mine.docs.skip(start).take(400)) {
      batch.delete(doc.reference);
    }
    await batch.commit().timeout(_serverTimeout);
  }
}

/// After joining (again): removes what I shared in an earlier membership. Best effort; a failure only
/// means those items stay hidden (their owner is not in the household while I am away, and they are not
/// among my choices any more).
Future<void> purgeStaleOwnSharedItems(
    FirebaseFirestore db, String hid, String uid) async {
  try {
    final QuerySnapshot<Map<String, dynamic>> mine = await db
        .collection('households/$hid/sharedItems')
        .where('ownerUid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(_serverTimeout);
    final Set<String> stale = sharedServerDocsToPurge(
      serverDocIds: mine.docs.map((d) => d.id).toSet(),
      activeDocIds: ownSharedItems().keys.toSet(),
    );
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in mine.docs) {
      if (stale.contains(doc.id)) await doc.reference.delete();
    }
  } catch (e) {
    print("Household shared items: could not clear old items: ${e.toString()}");
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
Future<void> uploadSharedItems(FirebaseFirestore db, String hid, String uid) =>
    _withSharedLock(() => _uploadSharedItemsLocked(db, hid, uid));

Future<void> _uploadSharedItemsLocked(
    FirebaseFirestore db, String hid, String uid) async {
  final Map<String, dynamic> own = _settingsMap(kSharedOwnKey);
  final Map<String, dynamic> uploaded = _settingsMap(kSharedUploadedKey);
  if (own.isEmpty && uploaded.isEmpty) return;

  final Set<String> memberUids = householdMemberNames.keys.toSet();
  // The choices as they were when this started, and the ones this run changed. At the end only the
  // changed ones are written, and only where the person did not choose something else meanwhile.
  final Map<String, dynamic> ownAtStart = Map<String, dynamic>.of(own);
  final Map<String, dynamic> ownPatches = {};
  void setOwn(String docId, dynamic value) {
    own[docId] = value;
    ownPatches[docId] = value;
  }

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
          setOwn(docId, deletedMarker());
          uploaded.remove(docId);
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
            setOwn(docId, deletedMarker());
            continue; // becomes private, the server copy goes on the next round
          }
          meta = meta.copyWith(
              visibleTo: pruned,
              updatedAt: DateTime.now().millisecondsSinceEpoch);
          setOwn(docId, stampItem(meta.toJson()));
        }
      }

      final int newest = max(local.updatedAt, meta.updatedAt);
      final dynamic sent = uploaded[docId];
      if (sent is num && newest <= sent) continue; // nothing new

      try {
        final Map<String, dynamic>? serverData =
            await _serverData(db, hid, docId);
        final int? serverU =
            serverData == null ? null : _updatedAtOf(serverData);
        final SharedUploadAction action = sharedUploadAction(
            localUpdatedAt: newest, serverUpdatedAt: serverU);
        if (action == SharedUploadAction.takeRemote &&
            serverData != null &&
            serverU != null) {
          // Somebody with edit rights changed it later: that change goes onto the real item.
          final _ApplyResult result = await _applyRemote(
              meta.kind, meta.localId, serverData,
              uploadedAt: sent is num ? sent.toInt() : 0);
          if (result == _ApplyResult.applied) {
            uploaded[docId] = serverU;
            uploadedChanged = true;
          } else if (result == _ApplyResult.notUsable) {
            // What is on the server cannot be used: the real item replaces it, so nobody keeps seeing it.
            final int repairU = sharedRepairTime(
                localNewest: newest, serverUpdatedAt: serverU);
            await db
                .doc(_docPath(hid, docId))
                .set({
                  ...meta.toJson(),
                  '_u': repairU,
                  'payload': local.payload,
                })
                .timeout(_serverTimeout);
            uploaded[docId] = repairU;
            uploadedChanged = true;
          }
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
    // Keep what was done even when the connection dropped half way. A choice the person made while this
    // ran has a newer time and is left alone.
    if (ownPatches.isNotEmpty) {
      final Map<String, dynamic> fresh = _settingsMap(kSharedOwnKey);
      bool changed = false;
      for (final MapEntry<String, dynamic> e in ownPatches.entries) {
        if (_updatedAtOf(fresh[e.key]) != _updatedAtOf(ownAtStart[e.key])) {
          continue;
        }
        fresh[e.key] = e.value;
        changed = true;
      }
      if (changed) {
        await updateSettings(kSharedOwnKey, fresh, updateGlobalState: false);
      }
    }
    if (uploadedChanged) {
      await updateSettings(kSharedUploadedKey, uploaded,
          updateGlobalState: false);
    }
  }
}

/// The server copy, or null when it is not there (or cannot be read).
Future<Map<String, dynamic>?> _serverData(
    FirebaseFirestore db, String hid, String docId) async {
  try {
    final DocumentSnapshot<Map<String, dynamic>> doc = await db
        .doc(_docPath(hid, docId))
        .get(const GetOptions(source: Source.server))
        .timeout(_serverTimeout);
    return doc.data();
  } on TimeoutException {
    rethrow; // offline: leave everything queued
  } catch (e) {
    return null; // not there
  }
}

// ---------------------------------------------------------------------------
// applying a member's edit to the real loan or deposit

enum _ApplyResult {
  /// The real item now has the member's version.
  applied,

  /// Nothing to do: the real item is as new or newer, or it is gone.
  notNewer,

  /// What is on the server cannot be applied (unreadable, about another item, absurd values).
  notUsable,
}

FixedDeposit? _currentDeposit(String id) {
  for (final FixedDeposit fd in loadFixedDeposits()) {
    if (fd.id == id) return fd;
  }
  return null;
}

/// Puts the server copy [serverData] of one of this person's items onto the real loan or deposit, when it is
/// newer than the real item and than what this phone sent or applied last ([uploadedAt]). Only the details a
/// member may change are taken; the account of this phone, the loan's row and its amount stay this phone's own.
Future<_ApplyResult> _applyRemote(
  String kind,
  String localId,
  Map<String, dynamic> serverData, {
  required int uploadedAt,
}) async {
  final int serverU = _updatedAtOf(serverData);
  final _LocalItem? local = await _localItem(kind, localId);
  if (local == null) return _ApplyResult.notNewer; // gone: the next sync removes the server copy
  if (!sharedOwnerShouldApply(
      serverUpdatedAt: serverU,
      localUpdatedAt: local.updatedAt,
      uploadedAt: uploadedAt)) {
    return _ApplyResult.notNewer;
  }
  final dynamic payload = serverData['payload'];

  if (kind == kSharedKindFixedDeposit) {
    final FixedDeposit? remote = sharedDepositToApply(payload, localId);
    if (remote == null) return _ApplyResult.notUsable;
    final FixedDeposit? current = _currentDeposit(localId);
    if (current == null) return _ApplyResult.notNewer;
    final bool saved = await applyFixedDepositFromHousehold(
        sharedDepositForOwner(current, remote), serverU);
    return saved ? _ApplyResult.applied : _ApplyResult.notNewer;
  }

  final SharedLoanEdit? edit = sharedLoanToApply(payload);
  if (edit == null) return _ApplyResult.notUsable;
  final LoanTerms? currentTerms = loanTermsFor(localId);
  if (currentTerms == null) return _ApplyResult.notUsable; // this loan has no terms any more
  final List<Objective> rows = await (database.select(database.objectives)
        ..where((o) => o.objectivePk.equals(localId)))
      .get();
  if (rows.isEmpty) return _ApplyResult.notNewer;
  final Objective row = rows.first;
  final bool saved = await applyLoanTermsFromHousehold(
      localId, sharedLoanTermsForOwner(currentTerms, edit.terms), serverU);
  if (!saved) return _ApplyResult.notNewer;
  // The loan's amount is its total to pay, worked out here from the terms.
  final double amount = sharedLoanAmount(edit.terms);
  if (row.name != edit.name || (row.amount - amount).abs() > 0.005) {
    await database
        .createOrUpdateObjective(row.copyWith(name: edit.name, amount: amount));
  }
  return _ApplyResult.applied;
}

/// Applies one snapshot of `sharedItems where ownerUid == me`: a member the owner allowed to edit changed
/// one of this person's shared items. Returns true when a sync should be asked for (a document that could not
/// be used is to be replaced by the real item).
Future<bool> applyOwnSharedItemsSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, String myUid) {
  return _withSharedLock<bool>(() async {
    if (myUid == "" || !isInHousehold) return false;
    final Map<String, dynamic> own = _settingsMap(kSharedOwnKey);
    final Map<String, dynamic> uploaded = _settingsMap(kSharedUploadedKey);
    bool uploadedChanged = false;
    bool needsSync = false;

    for (final DocumentChange<Map<String, dynamic>> change
        in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) continue;
      // This phone's own write that the server has not confirmed yet is not somebody else's edit.
      if (change.doc.metadata.hasPendingWrites) continue;
      final String docId = change.doc.id;
      final Map<String, dynamic>? data = change.doc.data();
      if (data == null || !sharedDocIsUsable(docId, data)) continue;
      final SharedItemMeta? meta = SharedItemMeta.fromJson(data);
      if (meta == null || meta.ownerUid != myUid) continue;
      // Only what this person still shares: the rest is taken off the server by the next sync.
      final dynamic choice = own[docId];
      if (choice == null || isDeletedItem(choice)) continue;

      final dynamic sent = uploaded[docId];
      final _ApplyResult result = await _applyRemote(
          meta.kind, meta.localId, data,
          uploadedAt: sent is num ? sent.toInt() : 0);
      if (result == _ApplyResult.applied) {
        uploaded[docId] = _updatedAtOf(data);
        uploadedChanged = true;
      } else if (result == _ApplyResult.notUsable) {
        // Forgetting what was sent makes the item wait again, and the next sync replaces the server copy.
        if (uploaded.remove(docId) != null) uploadedChanged = true;
        needsSync = true;
      }
    }

    if (uploadedChanged) {
      await updateSettings(kSharedUploadedKey, uploaded,
          updateGlobalState: false);
    }
    return needsSync;
  });
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
