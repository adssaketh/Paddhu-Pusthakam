// A plain-words report of what this phone and the household server each hold, so that
// "it says synced but I see nothing" can be told apart: not uploaded, refused by the rules,
// downloaded but hidden, or simply not there.

import 'dart:async';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/firebaseAuthGlobal.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSync.dart';
import 'package:budget/struct/householdView.dart';
import 'package:budget/struct/settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

/// Errors the download listeners met since the app started (newest last). Filled by householdDownload.dart.
final List<String> householdDownloadNotes = [];

void noteHouseholdDownloadProblem(String where, Object error) {
  final String text = "$where: ${error is FirebaseException ? '${error.code}' : error.toString()}";
  householdDownloadNotes.add(text);
  if (householdDownloadNotes.length > 8) householdDownloadNotes.removeAt(0);
}

Future<String> _serverCount(Query<Map<String, dynamic>> query) async {
  try {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await query
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    return "${snapshot.docs.length}";
  } catch (e) {
    return "REFUSED (${e is FirebaseException ? e.code : e.toString()})";
  }
}

Future<String> householdDiagnostics() async {
  final StringBuffer out = StringBuffer();
  out.writeln("Signed in: ${appStateSettings["hasSignedIn"] == true ? 'yes' : 'NO'}");
  out.writeln("In household: ${isInHousehold ? 'yes' : 'NO'}   sharing chosen: ${householdSyncReady ? 'yes' : 'NO'}");
  out.writeln("View: $householdView");
  out.writeln("Last upload: ${appStateSettings["householdLastSync"] == "" ? 'never' : appStateSettings["householdLastSync"]}");

  final String uid = currentHouseholdUserUid;
  int mine = 0, others = 0, personal = 0, fresh = 0, priv = 0, waiting = 0;
  final List<Transaction> local = await database.select(database.transactions).get();
  for (final Transaction t in local) {
    if (t.ownerUid == null) {
      fresh++;
    } else if (t.ownerUid == '') {
      personal++;
    } else if (t.ownerUid == uid) {
      mine++;
    } else {
      others++;
    }
    if (t.isPrivate) priv++;
    if (t.ownerUid == uid &&
        (t.householdSyncedAt == null ||
            (t.dateTimeModified != null && t.dateTimeModified!.isAfter(t.householdSyncedAt!)))) {
      waiting++;
    }
  }
  out.writeln("\nOn this phone: ${local.length} transactions");
  out.writeln("  mine $mine, from others $others, kept personal $personal, not yet claimed $fresh, private $priv, waiting to upload $waiting");

  // Accounts and a few rows from other people: shows which account those rows sit in and its currency.
  final List<TransactionWallet> wallets = await database.select(database.wallets).get();
  final String selected = (appStateSettings["selectedWalletPk"] ?? "").toString();
  out.writeln("\nAccounts on this phone (selected: ${selected.length > 8 ? selected.substring(0, 8) : selected}):");
  for (final TransactionWallet w in wallets) {
    final String pk = w.walletPk.length > 8 ? w.walletPk.substring(0, 8) : w.walletPk;
    out.writeln("  ${w.name} | $pk | currency ${w.currency ?? 'none'} | owner ${w.ownerUid == null ? '-' : (w.ownerUid!.length > 6 ? w.ownerUid!.substring(0, 6) : w.ownerUid)}");
  }
  int shown = 0;
  out.writeln("Rows from others:");
  for (final Transaction t in local) {
    if (t.ownerUid == null || t.ownerUid == '' || t.ownerUid == uid) continue;
    if (shown++ >= 3) break;
    final String pk = t.walletFk.length > 8 ? t.walletFk.substring(0, 8) : t.walletFk;
    out.writeln("  ${t.name} | amount ${t.amount} | account $pk");
  }

  if (!isInHousehold) return out.toString();
  final FirebaseFirestore? db = await firebaseGetDBInstance();
  final String uid2 = currentHouseholdUserUid;
  if (db == null || uid2 == "") {
    out.writeln("\nServer: could not sign in to Firebase");
    return out.toString();
  }
  final DocumentReference<Map<String, dynamic>> h = db.collection('households').doc(householdId);
  final CollectionReference<Map<String, dynamic>> tx = h.collection('transactions');
  out.writeln("\nOn the server (read just now):");
  out.writeln("  members: ${await _serverCount(h.collection('members'))}");
  out.writeln("  shared transactions: ${await _serverCount(tx.where('isPrivate', isEqualTo: false))}");
  out.writeln("  my private transactions: ${await _serverCount(tx.where('ownerId', isEqualTo: uid2).where('isPrivate', isEqualTo: true))}");
  out.writeln("  loans/deposits shared with me: ${await _serverCount(h.collection('sharedItems').where('visibleTo', arrayContains: uid2))}");
  out.writeln("  loans/deposits I shared: ${await _serverCount(h.collection('sharedItems').where('ownerUid', isEqualTo: uid2))}");

  // Per person: how many rows the server has and how many this phone has. They must be equal.
  try {
    final QuerySnapshot<Map<String, dynamic>> shared = await tx
        .where('isPrivate', isEqualTo: false)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    final Map<String, int> serverBy = {};
    for (final d in shared.docs) {
      final String o = (d.data()['ownerId'] ?? '?').toString();
      serverBy[o] = (serverBy[o] ?? 0) + 1;
    }
    final Set<String> serverIds = shared.docs.map((d) => d.id).toSet();
    final Map<String, int> localBy = {};
    int ghosts = 0, notUp = 0;
    for (final Transaction t in local) {
      final String? o = t.ownerUid;
      if (o == null || o == '') continue;
      localBy[o] = (localBy[o] ?? 0) + 1;
      if (!serverIds.contains(t.transactionPk)) {
        if (o == uid2) {
          if (!t.isPrivate) notUp++;
        } else {
          ghosts++;
        }
      }
    }
    out.writeln("\nPer person (server | this phone):");
    for (final String o in {...serverBy.keys, ...localBy.keys}) {
      final String who = o == uid2 ? 'me' : (o.length > 6 ? o.substring(0, 6) : o);
      out.writeln("  $who: ${serverBy[o] ?? 0} | ${localBy[o] ?? 0}");
    }
    out.writeln("Rows here that the server does not have: mine $notUp (will upload), others' $ghosts (will be removed)");
  } catch (e) {
    out.writeln("\nPer person: unreadable (${e is FirebaseException ? e.code : e.toString()})");
  }

  // The biggest rows here next to the same rows on the server: shows where a wrong amount comes from.
  final List<Transaction> biggest = [...local]
    ..sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
  out.writeln("\nBiggest rows, here vs server:");
  for (final Transaction t in biggest.take(4)) {
    String serverAmount;
    try {
      final doc = await tx.doc(t.transactionPk).get(const GetOptions(source: Source.server));
      serverAmount = doc.exists ? "${doc.data()?['amount']}" : "not there";
    } catch (e) {
      serverAmount = "unreadable";
    }
    final String who = t.ownerUid == uid2 ? 'mine' : (t.ownerUid == null || t.ownerUid == '') ? 'personal' : 'other';
    out.writeln("  ${t.name} ($who) | here ${t.amount} | server $serverAmount | account ${t.walletFk.length > 8 ? t.walletFk.substring(0, 8) : t.walletFk}");
  }

  out.writeln("\nDownload problems since the app started:");
  if (householdDownloadNotes.isEmpty) {
    out.writeln("  none");
  } else {
    for (final String note in householdDownloadNotes) {
      out.writeln("  $note");
    }
  }
  return out.toString();
}
