// Household sync, outbound half: sends this person's transactions and the categories to the
// household in Cloud Firestore. The inbound half (other members' transactions, shared
// categories) is householdDownload.dart; this file only starts and stops it.
// Apart from that, this file only marks which transactions belong to this person.
//
// How it works
//  - A transaction has an owner (transactions.ownerUid).
//      null = new, not claimed yet     "" = personal, stays on this phone     uid = shared by that person
//  - Once the person has chosen what to share (householdSyncReady), every new transaction
//    (ownerUid null) is claimed by them and uploaded.
//  - A transaction needs uploading while householdSyncedAt is null or older than dateTimeModified,
//    so the "queue" is simply those rows: nothing is lost while the phone is offline, and it goes
//    out the next time the connection is back.
//  - Deletions come from the existing delete log (only deletions made after sharing started).
//
// Documents: households/{h}/transactions/{transactionPk} and households/{h}/categories/{categoryPk}
// (see firestore.rules).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/firebaseAuthGlobal.dart';
import 'package:budget/struct/householdDownload.dart';
import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSharedCopies.dart';
import 'package:budget/struct/householdSharedItems.dart';
import 'package:budget/struct/settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:drift/drift.dart' hide Column;

bool get householdSyncReady => appStateSettings["householdSyncReady"] == true;

// Kept on this phone only, or rebuilt from other documents.
const List<String> _transactionKeysNotUploaded = [
  'ownerUid',
  'householdSyncedAt',
  'sharedKey',
  'sharedOldKey',
  'sharedStatus',
  'sharedDateUpdated',
  'sharedReferenceBudgetPk',
  'transactionOwnerEmail',
  'transactionOriginalOwnerEmail',
  'methodAdded',
  'objectiveFk',
  'objectiveLoanFk',
  'budgetFksExclude',
  'pairedTransactionFk',
];

const int _batchSize = 300;
const Duration _serverTimeout = Duration(seconds: 25);

bool _syncing = false;
bool _syncAgain = false;
Timer? _debounce;
Timer? _periodic;
StreamSubscription? _watch;

// ---------------------------------------------------------------------------
// start / stop

/// Starts watching for changes. Safe to call again whenever the household state changes.
void startHouseholdSync() {
  stopHouseholdSync();
  if (!isInHousehold || !householdSyncReady) return;
  // A cheap query that fires whenever one of these tables changes.
  _watch = database
      .customSelect('SELECT 1', readsFrom: {
        database.transactions,
        database.deleteLogs,
        database.categories,
        database.objectives,
      })
      .watch()
      .listen((_) => _scheduleSync());
  _periodic =
      Timer.periodic(const Duration(minutes: 3), (_) => syncHouseholdNow());
  _scheduleSync();
  startHouseholdDownload();
}

void stopHouseholdSync() {
  stopHouseholdDownload();
  _debounce?.cancel();
  _periodic?.cancel();
  _watch?.cancel();
  _debounce = null;
  _periodic = null;
  _watch = null;
}

/// Asks for a sync soon (a few seconds from now). Used after a loan or fixed deposit was changed or
/// its sharing was set, because those live in settings, which the table watcher does not see.
void requestHouseholdSync() {
  if (!isInHousehold || !householdSyncReady) return;
  _scheduleSync();
}

void _scheduleSync() {
  _debounce?.cancel();
  _debounce = Timer(const Duration(seconds: 3), () {
    syncHouseholdNow();
  });
}

// ---------------------------------------------------------------------------
// choosing what to share

/// [share] true: the transactions already on this phone are added to the household.
/// [share] false: they stay on this phone only; only new transactions are shared.
Future<String?> adoptExistingTransactions({required bool share}) async {
  final String uid = currentHouseholdUserUid;
  if (uid == "") return "Sign in first.";
  if (!isInHousehold) return "Join or create a household first.";
  try {
    if (share) {
      await (database.update(database.transactions)
            ..where((t) => t.ownerUid.isNull() | t.ownerUid.equals('')))
          .write(TransactionsCompanion(
        ownerUid: Value(uid),
        householdSyncedAt: const Value<DateTime?>(null),
      ));
    } else {
      await (database.update(database.transactions)
            ..where((t) => t.ownerUid.isNull()))
          .write(const TransactionsCompanion(ownerUid: Value('')));
    }
    // Only deletions from now on are uploaded.
    await updateSettings(
        "householdDeleteCursor", DateTime.now().millisecondsSinceEpoch,
        updateGlobalState: false);
    await updateSettings("householdSyncReady", true, updateGlobalState: false);
    startHouseholdSync();
    return null;
  } catch (e) {
    return "Something went wrong. ${e.toString()}";
  }
}

/// Called when this phone leaves a household (or was removed from it). The transactions stay
/// here as personal ones and nothing more is uploaded.
Future<void> releaseHouseholdTransactions() async {
  stopHouseholdSync();
  try {
    // Let a download that was already running finish first, then drop other members' data.
    await householdDownloadIdle();
    await removeOtherMembersData();
    await (database.update(database.transactions)
          ..where((t) => t.ownerUid.isNotNull() & t.ownerUid.equals('').not()))
        .write(const TransactionsCompanion(
      ownerUid: Value(''),
      householdSyncedAt: Value<DateTime?>(null),
    ));
  } catch (e) {
    print("Household: could not release transactions: ${e.toString()}");
  }
  await updateSettings("householdSyncReady", false, updateGlobalState: false);
  await updateSettings("householdDeleteCursor", 0, updateGlobalState: false);
  await updateSettings("householdCategoriesHash", "",
      updateGlobalState: false);
  await clearHouseholdMemberNames();
  await releaseSharedItems();
  await releaseSharedCopies();
}

/// Matches this phone's sync to the household state (call after the household was re-checked).
Future<void> applyHouseholdSyncState() async {
  if (!isInHousehold) {
    if (householdSyncReady) await releaseHouseholdTransactions();
    return;
  }
  if (householdSyncReady) startHouseholdSync();
}

// ---------------------------------------------------------------------------
// status

/// How many of this person's transactions are waiting to be uploaded.
Future<int> countWaitingTransactions() async {
  final String uid = currentHouseholdUserUid;
  if (uid == "") return 0;
  try {
    final rows = await (database.select(database.transactions)
          ..where((t) =>
              t.ownerUid.equals(uid) &
              (t.householdSyncedAt.isNull() |
                  t.dateTimeModified.isBiggerThan(t.householdSyncedAt))))
        .get();
    return rows.length;
  } catch (e) {
    return 0;
  }
}

// ---------------------------------------------------------------------------
// the sync itself

/// Uploads whatever is waiting. Returns an error message, or null if it worked (or there was nothing to do).
Future<String?> syncHouseholdNow() async {
  if (!isInHousehold || !householdSyncReady) return null;
  if (appStateSettings["hasSignedIn"] != true) return null;
  if (_syncing) {
    _syncAgain = true;
    return null;
  }
  _syncing = true;
  try {
    final FirebaseFirestore? db = await firebaseGetDBInstance();
    final String uid = currentHouseholdUserUid;
    if (db == null || uid == "") return "Could not sign in.";
    final String hid = householdId;

    // Is the server reachable? Without this, writes would wait in Firestore's own queue
    // while we think they are on their way.
    await db
        .doc('households/$hid')
        .get(const GetOptions(source: Source.server))
        .timeout(_serverTimeout);

    await _claimNewTransactions(uid);
    await _uploadCategories(db, hid);
    await _uploadTransactions(db, hid, uid);
    await _uploadDeletions(db, hid);

    // Shared loans and deposits. Network trouble queues them for the next round; anything else is
    // logged and does not count as a failed sync of the transactions.
    try {
      await uploadSharedItems(db, hid, uid);
    } catch (e) {
      print("Household shared items: ${e.toString()}");
      if (e is TimeoutException) rethrow;
    }

    await updateSettings("householdLastSync", DateTime.now().toIso8601String(),
        updateGlobalState: false);
    return null;
  } catch (e) {
    print("Household sync: ${e.toString()}");
    return e is TimeoutException
        ? "Could not reach the server."
        : "Sync problem: ${e.toString()}";
  } finally {
    _syncing = false;
    if (_syncAgain) {
      _syncAgain = false;
      _scheduleSync();
    }
  }
}

/// New transactions (nobody owns them yet) belong to this person.
Future<void> _claimNewTransactions(String uid) async {
  await (database.update(database.transactions)
        ..where((t) => t.ownerUid.isNull()))
      .write(TransactionsCompanion(ownerUid: Value(uid)));
}

Map<String, dynamic> _transactionDocument(Transaction transaction, String uid) {
  final Map<String, dynamic> json = transaction.toJson();
  for (final String key in _transactionKeysNotUploaded) {
    json.remove(key);
  }
  json['ownerId'] = uid; // the name the Firestore rules look at
  return json;
}

Future<void> _uploadTransactions(
    FirebaseFirestore db, String hid, String uid) async {
  for (int round = 0; round < 100; round++) {
    final List<Transaction> waiting = await (database.select(database.transactions)
          ..where((t) =>
              t.ownerUid.equals(uid) &
              (t.householdSyncedAt.isNull() |
                  t.dateTimeModified.isBiggerThan(t.householdSyncedAt)))
          ..limit(_batchSize))
        .get();
    if (waiting.isEmpty) return;

    // A row that was edited again after it was uploaded may have been edited later on another
    // phone of this person meanwhile. Its newer version is not overwritten: it comes in through
    // the download side, which takes the newer edit.
    final Set<String> newerOnServer =
        await _rowsEditedLaterOnServer(db, hid, waiting);

    final WriteBatch batch = db.batch();
    for (final Transaction transaction in waiting) {
      if (newerOnServer.contains(transaction.transactionPk)) continue;
      batch.set(
        db.doc('households/$hid/transactions/${transaction.transactionPk}'),
        _transactionDocument(transaction, uid),
      );
    }
    await batch.commit().timeout(_serverTimeout);

    // Remember what was uploaded (and which rows were left to the download side, so they are not
    // picked up again and again). If a transaction was edited meanwhile it is simply uploaded again.
    await database.batch((b) {
      for (final Transaction transaction in waiting) {
        b.update(
          database.transactions,
          TransactionsCompanion(
            householdSyncedAt:
                Value(transaction.dateTimeModified ?? DateTime.now()),
          ),
          where: (t) => t.transactionPk.equals(transaction.transactionPk),
        );
      }
    });
  }
}

/// Which of the [waiting] rows (that were uploaded before) have a later edit in the household.
/// Looked up one document at a time, so only the rules for reading one's own document apply.
/// If a lookup fails the row is simply uploaded as before.
Future<Set<String>> _rowsEditedLaterOnServer(
    FirebaseFirestore db, String hid, List<Transaction> waiting) async {
  final List<Transaction> toCheck =
      waiting.where((t) => t.householdSyncedAt != null).toList();
  final Set<String> newer = {};
  for (int start = 0; start < toCheck.length; start += 20) {
    final List<Transaction> chunk =
        toCheck.sublist(start, min(start + 20, toCheck.length));
    await Future.wait(chunk.map((Transaction transaction) async {
      try {
        final DocumentSnapshot<Map<String, dynamic>> doc = await db
            .doc('households/$hid/transactions/${transaction.transactionPk}')
            .get(const GetOptions(source: Source.server))
            .timeout(_serverTimeout);
        final Map<String, dynamic>? data = doc.data();
        if (data == null) return;
        final Transaction remote = Transaction.fromJson(data);
        if (householdRemoteIsNewer(
            remote.dateTimeModified, transaction.dateTimeModified)) {
          newer.add(transaction.transactionPk);
        }
      } catch (e) {
        // Not readable or not there: nothing to protect.
      }
    }));
  }
  return newer;
}

Map<String, dynamic> _categoryDocument(TransactionCategory category) {
  final Map<String, dynamic> json = category.toJson();
  json.remove('methodAdded');
  return json;
}

/// A fingerprint of the categories as they would be uploaded. dateTimeModified changes
/// whenever a transaction uses the category, which is not a real edit, so it is left out.
String householdCategoriesHash(List<TransactionCategory> categories) {
  final List<TransactionCategory> sorted = List.of(categories)
    ..sort((a, b) => a.categoryPk.compareTo(b.categoryPk));
  final String signature = jsonEncode(sorted.map((c) {
    final Map<String, dynamic> document = _categoryDocument(c);
    document.remove('dateTimeModified');
    return document;
  }).toList());
  return signature.hashCode.toString();
}

Future<void> _uploadCategories(FirebaseFirestore db, String hid) async {
  final List<TransactionCategory> categories =
      await database.select(database.categories).get();
  categories.sort((a, b) => a.categoryPk.compareTo(b.categoryPk));

  final String hash = householdCategoriesHash(categories);
  if (hash == (appStateSettings["householdCategoriesHash"] ?? "").toString()) {
    return;
  }

  for (int start = 0; start < categories.length; start += _batchSize) {
    final WriteBatch batch = db.batch();
    for (int i = start; i < min(start + _batchSize, categories.length); i++) {
      batch.set(
        db.doc('households/$hid/categories/${categories[i].categoryPk}'),
        _categoryDocument(categories[i]),
      );
    }
    await batch.commit().timeout(_serverTimeout);
  }
  await updateSettings("householdCategoriesHash", hash,
      updateGlobalState: false);
}

Future<void> _uploadDeletions(FirebaseFirestore db, String hid) async {
  final int cursor = (appStateSettings["householdDeleteCursor"] ?? 0) is num
      ? (appStateSettings["householdDeleteCursor"] as num).toInt()
      : 0;
  if (cursor <= 0) {
    await updateSettings(
        "householdDeleteCursor", DateTime.now().millisecondsSinceEpoch,
        updateGlobalState: false);
    return;
  }
  final List<DeleteLog> logs = await (database.select(database.deleteLogs)
        ..where((l) =>
            l.type.equalsValue(DeleteLogType.Transaction) &
            l.dateTimeModified.isBiggerOrEqualValue(
                DateTime.fromMillisecondsSinceEpoch(cursor)))
        ..orderBy([(l) => OrderingTerm.asc(l.dateTimeModified)]))
      .get();
  if (logs.isEmpty) return;

  int newCursor = cursor;
  for (final DeleteLog log in logs) {
    try {
      await db
          .doc('households/$hid/transactions/${log.entryPk}')
          .delete()
          .timeout(_serverTimeout);
    } on FirebaseException catch (e) {
      // Not uploaded before, or not allowed to delete it: nothing to do.
      if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
    }
    newCursor = max(newCursor, log.dateTimeModified.millisecondsSinceEpoch);
  }
  if (newCursor != cursor) {
    await updateSettings("householdDeleteCursor", newCursor,
        updateGlobalState: false);
  }
}
