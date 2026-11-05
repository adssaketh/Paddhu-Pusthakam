// Household sharing of loans and fixed deposits, viewer side, editing: a member the owner allowed to edit
// (membersCanEdit) changes a shared loan or deposit. The change is written to the household's copy; the
// owner's phone then applies it to the real loan or deposit (householdSharedItems.dart).
//
// How it works
//  - The write is one Firestore transaction: it reads the server copy, refuses when that changed after the
//    copy this person started from (sharedEditConflicts), and otherwise writes only `payload` and `_u`, which
//    is all the security rules allow a member to change. A transaction needs the server, so a write is
//    either saved or it is not: nothing waits in a queue that the person has been told did not happen.
//  - The payload is checked with the same rules the owner's phone uses before it touches the real item
//    (sharedDepositToApply, sharedLoanToApply), so a change the owner's phone would refuse is never sent.
//  - Only the owner deletes an item or changes who sees it or whether others may edit it.

import 'dart:async';

import 'package:budget/struct/firebaseAuthGlobal.dart';
import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSharedCopies.dart';
import 'package:budget/struct/householdSharedEditRules.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

export 'package:budget/struct/householdSharedEditRules.dart';

const Duration _transactionTimeout = Duration(seconds: 15);
const Duration _overallTimeout = Duration(seconds: 25);

// The outcomes of the transaction (a real edit time is always bigger than these).
const int _gone = -1;
const int _conflict = -2;

SharedCopy? _copyFor(String kind, String docId) {
  for (final SharedCopy copy in visibleSharedCopies(kind)) {
    if (copy.docId == docId) return copy;
  }
  return null;
}

/// Saves [payload] as the new version of the shared item [docId]. Returns a message for the person when it
/// could not be saved, or null when it was.
Future<String?> saveSharedCopyEdit({
  required String kind,
  required String docId,
  required Map<String, dynamic> payload,
}) async {
  if (!isInHousehold) return "You are not in a household.";
  final String me = currentHouseholdUserUid;
  if (me == "") return "Sign in first.";
  final SharedCopy? copy = _copyFor(kind, docId);
  if (copy == null) return "This is not shared with you any more.";

  // The same check the security rules make: only what the owner allowed.
  final Set<String> memberUids = {...householdMemberNames.keys, me};
  final String? notAllowed = sharedItemWriteError(
      existing: copy.meta, incoming: copy.meta, uid: me, memberUids: memberUids);
  if (notAllowed != null) return notAllowed;

  final bool usable = kind == kSharedKindLoan
      ? sharedLoanToApply(payload) != null
      : sharedDepositToApply(payload, copy.meta.localId) != null;
  if (!usable) return "Some of the details are not valid.";

  try {
    final FirebaseFirestore? db = await firebaseGetDBInstance();
    if (db == null) return "Could not sign in.";
    final DocumentReference<Map<String, dynamic>> ref =
        db.doc('households/$householdId/sharedItems/$docId');
    final int heldUpdatedAt = copy.meta.updatedAt;

    final int outcome = await db
        .runTransaction<int>((tx) async {
          final DocumentSnapshot<Map<String, dynamic>> snapshot =
              await tx.get(ref);
          final Map<String, dynamic>? data = snapshot.data();
          if (data == null) return _gone;
          final int serverUpdatedAt =
              data['_u'] is num ? (data['_u'] as num).toInt() : 0;
          if (sharedEditConflicts(
              heldUpdatedAt: heldUpdatedAt, serverUpdatedAt: serverUpdatedAt)) {
            return _conflict;
          }
          final int time = sharedEditTime(
              now: DateTime.now().millisecondsSinceEpoch,
              heldUpdatedAt: serverUpdatedAt);
          tx.update(ref, {'payload': payload, '_u': time});
          return time;
        }, timeout: _transactionTimeout)
        .timeout(_overallTimeout);

    if (outcome == _gone) return "This is not shared with you any more.";
    if (outcome == _conflict) {
      return "Somebody changed this while you were editing it. Their version is shown now; open it again to make your change.";
    }
    await storeSharedCopyEdit(docId, payload, outcome);
    return null;
  } on TimeoutException {
    return "Could not reach the server. Nothing was saved.";
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied') {
      return "The owner has not allowed you to change this.";
    }
    return "Could not reach the server. Nothing was saved.";
  } catch (e) {
    return "Something went wrong. Nothing was saved. ${e.toString()}";
  }
}
