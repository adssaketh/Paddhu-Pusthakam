// Household sync, inbound half: brings the other members' transactions (and the shared
// categories) from Cloud Firestore onto this phone. The outbound half is householdSync.dart.
//
// How it works
//  - Six live listeners (equality-only queries, so no composite index is needed):
//      households/{h}                                           the owner's "show balances" switch
//      households/{h}/members                                   nicknames, for the account names
//      households/{h}/categories                                shared categories
//      households/{h}/transactions  isPrivate == false          everyone's shared transactions
//      households/{h}/transactions  ownerId == me, isPrivate == true
//                                                               my own private ones (second phone)
//      households/{h}/sharedItems   visibleTo array-contains me  loans and deposits others shared with me
//                                                               (kept as read-only copies, householdSharedCopies.dart)
//  - Accounts are private, so another member's transactions all land in one placeholder
//    account per member (walletPk "hh_<uid>", named after their nickname, ownerUid = their uid).
//    The remote walletFk is ignored for their rows.
//  - Last writer wins by dateTimeModified. Other members' rows are written exactly as the
//    household has them.
//
// Safety rules (this file never breaks these)
//  - A row of this person (ownerUid == my uid) is never deleted here. It is inserted when it is
//    missing on this phone and was not deleted here on purpose. It is updated only when the same
//    row was edited later on another phone of this person (remote dateTimeModified is newer), and
//    then only the fields that are uploaded: what stays on a phone (links to goals and loans,
//    method added, ...) is kept.
//  - Remote deletions (or a member making a transaction private) only remove other members' rows.
//  - Applying remote data never causes an upload: other members' rows are not mine, and my own
//    inserted rows are marked as already uploaded (householdSyncedAt).
//  - Other members' repeating transactions are stored as "already handled" with no reminder, so
//    this phone never pays them automatically or creates the next one: their owner's phone does that.

import 'dart:async';
import 'dart:math';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/firebaseAuthGlobal.dart';
import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdMergeRules.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSharedCopies.dart';
import 'package:budget/struct/householdSync.dart';
import 'package:budget/struct/householdView.dart';
import 'package:budget/struct/householdWallets.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/watchAllWallets.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:drift/drift.dart' hide Column, Query;

export 'package:budget/struct/householdMergeRules.dart';

const int _chunkSize = 300;
const Duration _firstSnapshotWait = Duration(seconds: 10);
const Duration _retryDelay = Duration(minutes: 2);
const String _fallbackMemberName = "Member";

// ---------------------------------------------------------------------------
// small pure helpers (kept free of the database so they can be tested with `dart run`)

// ---------------------------------------------------------------------------
// start / stop

final List<StreamSubscription> _subscriptions = [];
Timer? _retryTimer;
int _generation = 0; // listeners and queued work from an older start are ignored
Future<void> _queue = Future.value();
Map<String, String> _memberNames = {};

/// Starts listening. Safe to call again whenever the household state changes.
void startHouseholdDownload() {
  _retryTimer?.cancel();
  _begin();
}

void _begin() {
  _stopListening();
  if (!isInHousehold || !householdSyncReady) return;
  if (appStateSettings["hasSignedIn"] != true) return;
  final int generation = _generation;
  _start(generation).catchError((Object e) {
    print("Household download: could not start: ${e.toString()}");
    _scheduleRetry(generation);
  });
}

void stopHouseholdDownload() {
  _retryTimer?.cancel();
  _retryTimer = null;
  _stopListening();
}

void _stopListening() {
  _generation++;
  for (final StreamSubscription subscription in _subscriptions) {
    subscription.cancel();
  }
  _subscriptions.clear();
}

/// Completes when the work that was already started has finished (used before removing data).
Future<void> householdDownloadIdle() => _queue;

void _scheduleRetry(int generation) {
  if (generation != _generation) return;
  _retryTimer?.cancel();
  _retryTimer = Timer(_retryDelay, () {
    if (generation != _generation) return;
    _begin();
  });
}

void _enqueue(int generation, Future<void> Function() task) {
  _queue = _queue.then((_) async {
    if (generation != _generation) return;
    try {
      await task();
    } catch (e) {
      print("Household download: ${e.toString()}");
    }
  });
}

Future<void> _handleError(int generation, Object error) async {
  if (generation != _generation) return;
  print("Household download: ${error.toString()}");
  if (error is FirebaseException && error.code == 'permission-denied') {
    // Most likely this person was removed from the household.
    await refreshHouseholdState();
    if (generation != _generation) return;
    if (!isInHousehold) {
      await applyHouseholdSyncState();
      return;
    }
  }
  _scheduleRetry(generation);
}

Future<void> _start(int generation) async {
  final FirebaseFirestore? db = await firebaseGetDBInstance();
  final String uid = currentHouseholdUserUid;
  if (generation != _generation) return;
  if (db == null || uid == "") {
    _scheduleRetry(generation);
    return;
  }
  final DocumentReference<Map<String, dynamic>> household =
      db.collection('households').doc(householdId);

  // The owner's balance switch, so other members' accounts are shown or hidden right away.
  _subscriptions.add(household.snapshots().listen(
        (snapshot) => _enqueue(generation, () => _applyHouseholdDocument(snapshot)),
        onError: (Object e) => _handleError(generation, e),
      ));

  // Members and categories first, so accounts get their names and transactions their categories.
  final Completer<void> membersFirst = Completer<void>();
  _subscriptions.add(household.collection('members').snapshots().listen(
    (snapshot) {
      _enqueue(generation, () => _applyMembers(snapshot, uid));
      if (!membersFirst.isCompleted) membersFirst.complete();
    },
    onError: (Object e) {
      if (!membersFirst.isCompleted) membersFirst.complete();
      _handleError(generation, e);
    },
  ));
  await membersFirst.future.timeout(_firstSnapshotWait, onTimeout: () {});
  if (generation != _generation) return;

  final Completer<void> categoriesFirst = Completer<void>();
  _subscriptions.add(household.collection('categories').snapshots().listen(
    (snapshot) {
      _enqueue(generation, () => _applyCategories(snapshot));
      if (!categoriesFirst.isCompleted) categoriesFirst.complete();
    },
    onError: (Object e) {
      if (!categoriesFirst.isCompleted) categoriesFirst.complete();
      _handleError(generation, e);
    },
  ));
  await categoriesFirst.future.timeout(_firstSnapshotWait, onTimeout: () {});
  if (generation != _generation) return;

  final Query<Map<String, dynamic>> transactions =
      household.collection('transactions');
  _subscriptions.add(
      transactions.where('isPrivate', isEqualTo: false).snapshots().listen(
            (snapshot) =>
                _enqueue(generation, () => _applyTransactions(snapshot, uid)),
            onError: (Object e) => _handleError(generation, e),
          ));
  _subscriptions.add(transactions
      .where('ownerId', isEqualTo: uid)
      .where('isPrivate', isEqualTo: true)
      .snapshots()
      .listen(
        (snapshot) =>
            _enqueue(generation, () => _applyTransactions(snapshot, uid)),
        onError: (Object e) => _handleError(generation, e),
      ));

  // Loans and deposits other members chose to share with me: kept as read-only copies on this phone
  // (householdSharedCopies.dart). One equality-style query, which the rules allow.
  _subscriptions.add(household
      .collection('sharedItems')
      .where('visibleTo', arrayContains: uid)
      .snapshots()
      .listen(
        (snapshot) =>
            _enqueue(generation, () => applySharedItemsSnapshot(snapshot, uid)),
        onError: (Object e) => _handleSharedItemsError(generation, e),
      ));
}

/// Errors of the shared items listener are only logged. If the rules for shared items are not published
/// yet, this listener is refused; that must not restart the listeners of the transactions every
/// couple of minutes. A real connection problem restarts everything through the other listeners.
void _handleSharedItemsError(int generation, Object error) {
  if (generation != _generation) return;
  print("Household download: shared items: ${error.toString()}");
}

// ---------------------------------------------------------------------------
// household document: the owner's "show balances" switch

Future<void> _applyHouseholdDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot) async {
  if (!snapshot.exists) return;
  await saveHouseholdBalancesShown(snapshot.data()?['showBalances'] == true);
}

/// The selected account is always one of this person's own accounts, never another member's
/// placeholder account. Only changes anything when the selected account is a placeholder
/// (or is gone), e.g. after the other member's account was picked in an earlier build.
Future<void> ensureOwnWalletSelected() async {
  final String selected = (appStateSettings["selectedWalletPk"] ?? "").toString();
  final List<TransactionWallet> all = await (database.select(database.wallets)
        ..orderBy([(w) => OrderingTerm.asc(w.order)]))
      .get();
  final List<TransactionWallet> own =
      all.where((w) => !isPlaceholderWalletPk(w.walletPk)).toList();
  if (own.isEmpty) return;
  if (own.any((w) => w.walletPk == selected)) return;
  final String pk = own.first.walletPk;
  await updateSettings("selectedWalletPk", pk, updateGlobalState: true);
  selectedWalletPkController.add(SelectedWalletPk(selectedWalletPk: pk));
}

// ---------------------------------------------------------------------------
// members: names of the placeholder accounts

Future<void> _applyMembers(
    QuerySnapshot<Map<String, dynamic>> snapshot, String myUid) async {
  final Map<String, String> names = {};
  for (final doc in snapshot.docs) {
    names[doc.id] = (doc.data()['displayName'] ?? "").toString().trim();
    if (doc.id == myUid) {
      // The owner's "can delete others' transactions" permission for this person.
      await saveHouseholdMemberCanDelete(doc.data()['canDelete'] == true);
      // Ownership can change while the app is open (hand-over): follow it right away.
      final String role = (doc.data()['role'] ?? "member").toString();
      if ((appStateSettings["householdRole"] ?? "").toString() != role) {
        await updateSettings("householdRole", role, updateGlobalState: false);
      }
    }
  }
  _memberNames = names;
  await saveHouseholdMemberNames(names);

  final List<TransactionWallet> placeholders =
      await (database.select(database.wallets)
            ..where((w) => w.walletPk.like('$kPlaceholderWalletPrefix%')))
          .get();
  for (final TransactionWallet wallet in placeholders) {
    final String? owner = wallet.ownerUid;
    if (!householdIsForeignOwner(owner, myUid)) continue;
    final String name = _walletNameFor(owner!);
    if (name == wallet.name) continue;
    await (database.update(database.wallets)
          ..where((w) => w.walletPk.equals(wallet.walletPk)))
        .write(WalletsCompanion(
      name: Value(name),
      dateTimeModified: Value(DateTime.now()),
    ));
  }
  await ensureOwnWalletSelected();
}

String _walletNameFor(String uid) {
  String name = (_memberNames[uid] ?? "").trim();
  if (name == "") name = _fallbackMemberName;
  return name.length > NAME_LIMIT ? name.substring(0, NAME_LIMIT) : name;
}

// ---------------------------------------------------------------------------
// categories

Future<void> _applyCategories(QuerySnapshot<Map<String, dynamic>> snapshot) async {
  final List<TransactionCategory> local =
      await database.select(database.categories).get();
  final Map<String, TransactionCategory> localByPk = {
    for (final TransactionCategory c in local) c.categoryPk: c,
  };
  // If everything here had already been uploaded, what arrives is not a new local edit,
  // so the stored hash follows along and nothing is uploaded back.
  final bool wasInSync = householdCategoriesHash(local) ==
      (appStateSettings["householdCategoriesHash"] ?? "").toString();

  final List<CategoriesCompanion> writes = [];
  for (final change in snapshot.docChanges) {
    if (change.type == DocumentChangeType.removed) continue; // categories are never removed remotely
    final Map<String, dynamic>? data = change.doc.data();
    if (data == null) continue;
    final TransactionCategory remote;
    try {
      remote = TransactionCategory.fromJson(data);
    } catch (e) {
      print("Household download: skipped a category: ${e.toString()}");
      continue;
    }
    final TransactionCategory? mine = localByPk[remote.categoryPk];
    if (mine != null) {
      if (_sameCategoryContent(mine, remote)) continue;
      if (!householdRemoteIsNewer(remote.dateTimeModified, mine.dateTimeModified)) {
        continue;
      }
    }
    writes.add(remote
        .toCompanion(false)
        .copyWith(methodAdded: Value(mine?.methodAdded)));
  }
  if (writes.isEmpty) return;

  await database.batch((b) {
    for (final CategoriesCompanion companion in writes) {
      b.insert(database.categories, companion, mode: InsertMode.insertOrReplace);
    }
  });

  if (wasInSync) {
    final List<TransactionCategory> now =
        await database.select(database.categories).get();
    await updateSettings("householdCategoriesHash", householdCategoriesHash(now),
        updateGlobalState: false);
  }
}

/// dateTimeModified also changes when a transaction merely uses the category, and methodAdded
/// is never uploaded, so neither counts as a difference.
bool _sameCategoryContent(TransactionCategory a, TransactionCategory b) =>
    a.name == b.name &&
    a.colour == b.colour &&
    a.iconName == b.iconName &&
    a.emojiIconName == b.emojiIconName &&
    a.order == b.order &&
    a.income == b.income &&
    a.mainCategoryPk == b.mainCategoryPk;

// ---------------------------------------------------------------------------
// transactions

Future<void> _applyTransactions(
    QuerySnapshot<Map<String, dynamic>> snapshot, String myUid) async {
  final generation = _generation;
  final changes = snapshot.docChanges;
  for (int start = 0; start < changes.length; start += _chunkSize) {
    if (generation != _generation) return; // stopped or left the household meanwhile
    await _applyTransactionChunk(
        changes.sublist(start, min(start + _chunkSize, changes.length)), myUid);
  }
}

Future<void> _applyTransactionChunk(
    List<DocumentChange<Map<String, dynamic>>> chunk, String myUid) async {
  final List<String> pks = chunk.map((c) => c.doc.id).toList();
  final Map<String, Transaction> localByPk = {
    for (final Transaction t in await (database.select(database.transactions)
          ..where((t) => t.transactionPk.isIn(pks)))
        .get())
      t.transactionPk: t,
  };
  // Transactions this person deleted on this phone and whose deletion has not reached the household yet.
  final Set<String> deletedHere = (await (database.select(database.deleteLogs)
            ..where((l) =>
                l.type.equalsValue(DeleteLogType.Transaction) &
                l.entryPk.isIn(pks)))
          .get())
      .map((l) => l.entryPk)
      .toSet();
  final List<TransactionWallet> wallets =
      await database.select(database.wallets).get();
  final Set<String> walletPks = wallets.map((w) => w.walletPk).toSet();
  final String? fallbackWalletPk = _fallbackWalletPk(wallets);

  final List<String> removePks = [];
  final List<TransactionsCompanion> writes = [];
  final Map<String, TransactionsCompanion> ownRowUpdates = {};
  final Set<String> membersNeedingWallet = {};

  for (final change in chunk) {
    final String pk = change.doc.id;
    final Transaction? mine = localByPk[pk];

    if (change.type == DocumentChangeType.removed) {
      // Deleted by someone, or made private by its owner: only other members' rows go.
      if (mine != null && householdIsForeignOwner(mine.ownerUid, myUid)) {
        removePks.add(pk);
      }
      continue;
    }

    final Map<String, dynamic>? data = change.doc.data();
    if (data == null) continue;
    final String ownerId = (data['ownerId'] ?? "").toString();
    if (ownerId == "") continue;
    final Transaction remote;
    try {
      remote = Transaction.fromJson(data);
    } catch (e) {
      print("Household download: skipped a transaction: ${e.toString()}");
      continue;
    }

    if (ownerId == myUid) {
      if (deletedHere.contains(pk)) continue;
      if (mine == null) {
        // My own transaction is missing here: restore it.
        final String? walletFk = walletPks.contains(remote.walletFk)
            ? remote.walletFk
            : fallbackWalletPk;
        if (walletFk == null) continue;
        writes.add(remote.toCompanion(false).copyWith(
              ownerUid: Value(myUid),
              walletFk: Value(walletFk),
              householdSyncedAt: Value(remote.dateTimeModified),
            ));
        continue;
      }
      // I edited it on another phone and that edit is newer than mine: take it. An edit made
      // here that is newer (or the same) is kept and goes out with the next upload.
      if (!householdOwnerIsMe(mine.ownerUid, myUid)) continue;
      if (!householdRemoteIsNewer(remote.dateTimeModified, mine.dateTimeModified)) {
        continue;
      }
      ownRowUpdates[pk] = remote.toCompanion(false).copyWith(
            // Kept as they are on this phone: what is never uploaded, and my account choice.
            transactionPk: const Value.absent(),
            ownerUid: const Value.absent(),
            walletFk: walletPks.contains(remote.walletFk) &&
                    !isPlaceholderWalletPk(remote.walletFk)
                ? Value(remote.walletFk)
                : const Value.absent(),
            sharedKey: const Value.absent(),
            sharedOldKey: const Value.absent(),
            sharedStatus: const Value.absent(),
            sharedDateUpdated: const Value.absent(),
            sharedReferenceBudgetPk: const Value.absent(),
            transactionOwnerEmail: const Value.absent(),
            transactionOriginalOwnerEmail: const Value.absent(),
            methodAdded: const Value.absent(),
            objectiveFk: const Value.absent(),
            objectiveLoanFk: const Value.absent(),
            budgetFksExclude: const Value.absent(),
            pairedTransactionFk: const Value.absent(),
            householdSyncedAt: Value(remote.dateTimeModified),
          );
      continue;
    }

    // Somebody else's transaction.
    if (data['isPrivate'] != false) continue; // the rules do not allow this; be safe anyway
    if (mine != null) {
      if (mine.ownerUid != ownerId) continue; // never touch a row that is not theirs
      if (!householdRemoteIsNewer(remote.dateTimeModified, mine.dateTimeModified)) {
        continue;
      }
    }
    membersNeedingWallet.add(ownerId);
    writes.add(remote.toCompanion(false).copyWith(
          ownerUid: Value(ownerId),
          walletFk: Value(placeholderWalletPk(ownerId)),
          householdSyncedAt: Value(remote.dateTimeModified),
          // Their owner's phone handles repeating transactions and reminders, not this one.
          createdAnotherFutureTransaction: const Value(true),
          upcomingTransactionNotification: const Value(false),
        ));
  }

  await _ensurePlaceholderWallets(membersNeedingWallet, wallets);

  if (writes.isEmpty && removePks.isEmpty && ownRowUpdates.isEmpty) return;
  await database.batch((b) {
    for (final TransactionsCompanion companion in writes) {
      b.insert(database.transactions, companion,
          mode: InsertMode.insertOrReplace);
    }
    ownRowUpdates.forEach((String pk, TransactionsCompanion companion) {
      b.update(database.transactions, companion,
          where: (t) => t.transactionPk.equals(pk));
    });
    if (removePks.isNotEmpty) {
      b.deleteWhere(database.transactions,
          (t) => t.transactionPk.isIn(removePks));
    }
  });
}

/// The account that a restored transaction of this person falls back to when its own account
/// does not exist on this phone: the selected one, else the first.
String? _fallbackWalletPk(List<TransactionWallet> wallets) {
  final List<TransactionWallet> own =
      wallets.where((w) => !isPlaceholderWalletPk(w.walletPk)).toList();
  if (own.isEmpty) return null;
  final String selected = (appStateSettings["selectedWalletPk"] ?? "").toString();
  if (own.any((w) => w.walletPk == selected)) return selected;
  own.sort((a, b) => a.order.compareTo(b.order));
  return own.first.walletPk;
}

Future<void> _ensurePlaceholderWallets(
    Set<String> memberUids, List<TransactionWallet> wallets) async {
  if (memberUids.isEmpty) return;
  final Set<String> existing = wallets.map((w) => w.walletPk).toSet();
  int nextOrder = wallets.isEmpty ? 0 : wallets.map((w) => w.order).reduce(max) + 1;
  for (final String uid in memberUids) {
    final String pk = placeholderWalletPk(uid);
    if (existing.contains(pk)) continue;
    await database.into(database.wallets).insert(
          WalletsCompanion.insert(
            walletPk: Value(pk),
            name: _walletNameFor(uid),
            order: nextOrder++,
            ownerUid: Value(uid),
            dateTimeModified: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

// ---------------------------------------------------------------------------
// leaving or being removed

/// Removes what came from other members: their transactions and their placeholder accounts.
/// This person's own transactions and accounts are never touched.
Future<void> removeOtherMembersData() async {
  final String uid = currentHouseholdUserUid;
  // Everything in a placeholder account is somebody else's.
  await (database.delete(database.transactions)
        ..where((t) => t.walletFk.like('$kPlaceholderWalletPrefix%')))
      .go();
  if (uid != "") {
    await (database.delete(database.transactions)
          ..where((t) =>
              t.ownerUid.isNotNull() &
              t.ownerUid.equals('').not() &
              t.ownerUid.equals(uid).not()))
        .go();
  }
  await (database.delete(database.wallets)
        ..where((w) => w.walletPk.like('$kPlaceholderWalletPrefix%')))
      .go();
  // The selected account must not point at a placeholder account that is now gone.
  await ensureOwnWalletSelected();
}
