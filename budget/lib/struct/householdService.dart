// Household login: create a household, invite people with a code, join, leave.
//
// Everything lives in Cloud Firestore and is protected by firestore.rules:
//   users/{uid}                     householdId, displayName, inviteCode (this person only)
//   invites/{code}                  householdId, ownerId (read by exact code only)
//   households/{h}                  ownerId, name, showBalances
//   households/{h}/members/{uid}    role, canDelete, displayName
//
// Only a few things are kept on this phone (see the household* settings), so the
// household is re-checked against Firestore whenever the Household page opens.
// Joining, leaving and removing never touch the transactions and accounts that are
// already stored on this phone.

import 'dart:math';

import 'package:budget/struct/firebaseAuthGlobal.dart';
import 'package:budget/struct/householdView.dart';
import 'package:budget/struct/householdWallets.dart';
import 'package:budget/struct/settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';

/// Soft limit. Firestore rules cannot count members, so it is checked when the owner
/// creates an invite code.
const int kMaxHouseholdMembers = 6;

// Characters without look-alikes (no 0/O, 1/I).
const String _inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int _inviteLength = 8;

String get householdId => (appStateSettings["householdId"] ?? "").toString();
String get householdName => (appStateSettings["householdName"] ?? "").toString();
String get householdNickname =>
    (appStateSettings["householdNickname"] ?? "").toString();
bool get isInHousehold => householdId != "";
bool get isHouseholdOwner =>
    isInHousehold && appStateSettings["householdRole"] == "owner";

class HouseholdMember {
  const HouseholdMember({
    required this.uid,
    required this.nickname,
    required this.role,
    required this.canDelete,
  });

  final String uid;
  final String nickname;
  final String role;
  final bool canDelete;

  bool get isOwner => role == "owner";
}

class HouseholdSnapshot {
  const HouseholdSnapshot({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.showBalances,
    required this.members,
  });

  final String id;
  final String name;
  final String ownerId;
  final bool showBalances;
  final List<HouseholdMember> members;
}

/// Result of an action that returns a value: either [value] or an [error] message.
class HouseholdResult<T> {
  const HouseholdResult.ok([this.value]) : error = null;
  const HouseholdResult.fail(String this.error) : value = null;

  final T? value;
  final String? error;

  bool get isOk => error == null;
}

// ---------------------------------------------------------------------------
// helpers

const String _offlineMessage =
    "Could not reach the server. Check your connection and try again.";

Future<FirebaseFirestore?> _db() async {
  final FirebaseFirestore? db = await firebaseGetDBInstance();
  if (db == null || FirebaseAuth.instance.currentUser == null) return null;
  return db;
}

String get _uid => FirebaseAuth.instance.currentUser!.uid;

/// The signed-in person's id, or "" when nobody is signed in.
String get currentHouseholdUserUid =>
    FirebaseAuth.instance.currentUser?.uid ?? "";

String _friendlyError(Object e) {
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return "You don't have permission to do that.";
      case 'unavailable':
      case 'deadline-exceeded':
        return _offlineMessage;
    }
  }
  return "Something went wrong. ${e.toString()}";
}

/// Cleans up what someone typed or pasted: letters and numbers only, upper case.
String normalizeInviteCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// "ABCD2345" -> "ABCD-2345"
String formatInviteCode(String code) => code.length == _inviteLength
    ? "${code.substring(0, 4)}-${code.substring(4)}"
    : code;

String _newInviteCode() {
  final Random random = Random.secure();
  return List.generate(_inviteLength,
      (_) => _inviteAlphabet[random.nextInt(_inviteAlphabet.length)]).join();
}

Future<void> _saveLocal({
  required String id,
  required String name,
  required String role,
  required String nickname,
}) async {
  await updateSettings("householdId", id, updateGlobalState: false);
  await updateSettings("householdName", name, updateGlobalState: false);
  await updateSettings("householdRole", role, updateGlobalState: false);
  await updateSettings("householdNickname", nickname, updateGlobalState: false);
}

Future<void> _clearLocal() async {
  await _saveLocal(id: "", name: "", role: "", nickname: "");
  // Without a household there are no other members' accounts left to show.
  await updateSettings(kHouseholdShowBalancesKey, false,
      updateGlobalState: false);
  await updateSettings(kHouseholdCanDeleteKey, false, updateGlobalState: false);
}

String defaultNickname() {
  final User? user = FirebaseAuth.instance.currentUser;
  final String? name = user?.displayName;
  if (name != null && name.trim() != "") return name.trim().split(" ").first;
  final String email = (user?.email ?? appStateSettings["currentUserEmail"] ?? "")
      .toString();
  return email.contains("@") ? email.split("@").first : "";
}

// ---------------------------------------------------------------------------
// state

/// Re-checks this account's household against Firestore and updates the settings kept on
/// this phone. Returns an error message if it could not be checked (nothing is changed).
Future<String?> refreshHouseholdState() async {
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    final String uid = _uid;
    final userDoc = await db.doc('users/$uid').get();
    final String hid = (userDoc.data()?['householdId'] ?? "").toString();
    if (hid == "") {
      if (isInHousehold) await _clearLocal();
      return null;
    }
    try {
      final member = await db.doc('households/$hid/members/$uid').get();
      if (!member.exists) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      final household = await db.doc('households/$hid').get();
      await _saveLocal(
        id: hid,
        name: (household.data()?['name'] ?? "").toString(),
        role: (member.data()?['role'] ?? "member").toString(),
        nickname: (member.data()?['displayName'] ?? defaultNickname()).toString(),
      );
      await saveHouseholdBalancesShown(household.data()?['showBalances'] == true);
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      // Removed from the household (or it was deleted): drop it here.
      await db.doc('users/$uid').set(
          {'householdId': FieldValue.delete()}, SetOptions(merge: true));
      await _clearLocal();
    }
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

/// The household and its members. Returns null (with an error) if it cannot be read.
Future<HouseholdResult<HouseholdSnapshot>> loadHousehold() async {
  if (!isInHousehold) return const HouseholdResult.fail("Not in a household.");
  final FirebaseFirestore? db = await _db();
  if (db == null) return const HouseholdResult.fail(_offlineMessage);
  try {
    final String hid = householdId;
    final household = await db.doc('households/$hid').get();
    if (!household.exists) {
      await _clearLocal();
      return const HouseholdResult.fail("This household no longer exists.");
    }
    final membersQuery = await db.collection('households/$hid/members').get();
    final List<HouseholdMember> members = membersQuery.docs.map((d) {
      final data = d.data();
      return HouseholdMember(
        uid: d.id,
        nickname: (data['displayName'] ?? "").toString(),
        role: (data['role'] ?? "member").toString(),
        canDelete: data['canDelete'] == true,
      );
    }).toList()
      ..sort((a, b) {
        if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
        return a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase());
      });
    final data = household.data() ?? {};
    return HouseholdResult.ok(HouseholdSnapshot(
      id: hid,
      name: (data['name'] ?? "").toString(),
      ownerId: (data['ownerId'] ?? "").toString(),
      showBalances: data['showBalances'] == true,
      members: members,
    ));
  } catch (e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      // No longer a member.
      await refreshHouseholdState();
      return const HouseholdResult.fail("You are no longer in this household.");
    }
    return HouseholdResult.fail(_friendlyError(e));
  }
}

// ---------------------------------------------------------------------------
// create / join / leave

/// Creates a household with the signed-in person as its owner. Returns an error message or null.
Future<String?> createHousehold({
  required String name,
  required String nickname,
}) async {
  name = name.trim();
  nickname = nickname.trim();
  if (name == "") return "Enter a name for the household.";
  if (nickname == "") return "Enter the name others will see.";
  final String? checkError = await refreshHouseholdState();
  if (checkError != null) return checkError;
  if (isInHousehold) return "You are already in a household.";
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    final String uid = _uid;
    final DocumentReference<Map<String, dynamic>> ref =
        db.collection('households').doc();
    // In two steps on purpose: the rules check that the household exists
    // before they let its owner become a member.
    await ref.set({
      'ownerId': uid,
      'name': name,
      'showBalances': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.collection('members').doc(uid).set({
      'role': 'owner',
      'canDelete': true,
      'displayName': nickname,
    });
    await db.doc('users/$uid').set(
        {'householdId': ref.id, 'displayName': nickname}, SetOptions(merge: true));
    await _saveLocal(id: ref.id, name: name, role: 'owner', nickname: nickname);
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

/// Joins the household that [code] belongs to. Returns an error message or null.
Future<String?> joinHousehold({
  required String code,
  required String nickname,
}) async {
  final String cleanCode = normalizeInviteCode(code);
  nickname = nickname.trim();
  if (cleanCode.length != _inviteLength) {
    return "Invite codes have $_inviteLength letters and numbers.";
  }
  if (nickname == "") return "Enter the name others will see.";
  final String? checkError = await refreshHouseholdState();
  if (checkError != null) return checkError;
  if (isInHousehold) return "You are already in a household.";
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    final String uid = _uid;
    final invite = await db.doc('invites/$cleanCode').get();
    final String hid = (invite.data()?['householdId'] ?? "").toString();
    if (!invite.exists || hid == "") return "That invite code is not valid.";
    await db.doc('households/$hid/members/$uid').set({
      'role': 'member',
      'canDelete': false,
      'displayName': nickname,
      'inviteCode': cleanCode,
    });
    await db.doc('users/$uid').set(
        {'householdId': hid, 'displayName': nickname}, SetOptions(merge: true));
    final household = await db.doc('households/$hid').get();
    await _saveLocal(
      id: hid,
      name: (household.data()?['name'] ?? "").toString(),
      role: 'member',
      nickname: nickname,
    );
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

/// A member leaves. The owner cannot leave (ownership transfer comes later).
Future<String?> leaveHousehold() async {
  if (!isInHousehold) return null;
  if (isHouseholdOwner) {
    return "As the owner you can't leave yet. Remove the other members first.";
  }
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    final String uid = _uid;
    await db.doc('households/$householdId/members/$uid').delete();
    await db.doc('users/$uid').set(
        {'householdId': FieldValue.delete()}, SetOptions(merge: true));
    await _clearLocal();
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

// ---------------------------------------------------------------------------
// owner actions

Future<String?> removeHouseholdMember(String memberUid) async {
  if (!isHouseholdOwner) return "Only the owner can remove members.";
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    await db.doc('households/$householdId/members/$memberUid').delete();
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

Future<String?> setMemberCanDelete(String memberUid, bool canDelete) async {
  if (!isHouseholdOwner) return "Only the owner can change this.";
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    await db
        .doc('households/$householdId/members/$memberUid')
        .update({'canDelete': canDelete});
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

Future<String?> setShowBalances(bool show) async {
  if (!isHouseholdOwner) return "Only the owner can change this.";
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    await db.doc('households/$householdId').update({'showBalances': show});
    await saveHouseholdBalancesShown(show);
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

/// The current invite code (if one was made), or null.
Future<String?> currentInviteCode() async {
  final FirebaseFirestore? db = await _db();
  if (db == null) return null;
  try {
    final userDoc = await db.doc('users/${_uid}').get();
    final String code = (userDoc.data()?['inviteCode'] ?? "").toString();
    return code == "" ? null : code;
  } catch (e) {
    return null;
  }
}

/// Makes a new invite code and cancels the previous one.
Future<HouseholdResult<String>> createInviteCode() async {
  if (!isHouseholdOwner) {
    return const HouseholdResult.fail("Only the owner can invite people.");
  }
  final FirebaseFirestore? db = await _db();
  if (db == null) return const HouseholdResult.fail(_offlineMessage);
  try {
    final String uid = _uid;
    final members = await db.collection('households/$householdId/members').get();
    if (members.docs.length >= kMaxHouseholdMembers) {
      return const HouseholdResult.fail(
          "A household can have up to $kMaxHouseholdMembers people.");
    }
    final String? oldCode = await currentInviteCode();
    for (int attempt = 0; attempt < 5; attempt++) {
      final String code = _newInviteCode();
      try {
        await db.doc('invites/$code').set({
          'householdId': householdId,
          'ownerId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        // A code that already exists cannot be overwritten: try another one.
        if (e.code == 'permission-denied') continue;
        rethrow;
      }
      await db.doc('users/$uid').set({'inviteCode': code}, SetOptions(merge: true));
      if (oldCode != null && oldCode != code) {
        try {
          await db.doc('invites/$oldCode').delete();
        } catch (_) {}
      }
      return HouseholdResult.ok(code);
    }
    return const HouseholdResult.fail("Could not make a code. Try again.");
  } catch (e) {
    return HouseholdResult.fail(_friendlyError(e));
  }
}

/// Cancels the current invite code.
Future<String?> revokeInviteCode() async {
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    final String? code = await currentInviteCode();
    if (code != null) {
      await db.doc('invites/$code').delete();
      await db.doc('users/${_uid}').set(
          {'inviteCode': FieldValue.delete()}, SetOptions(merge: true));
    }
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}

// ---------------------------------------------------------------------------
// any member

Future<String?> setMyNickname(String nickname) async {
  nickname = nickname.trim();
  if (nickname == "") return "Enter the name others will see.";
  if (!isInHousehold) return "Not in a household.";
  final FirebaseFirestore? db = await _db();
  if (db == null) return _offlineMessage;
  try {
    final String uid = _uid;
    await db
        .doc('households/$householdId/members/$uid')
        .update({'displayName': nickname});
    await db
        .doc('users/$uid')
        .set({'displayName': nickname}, SetOptions(merge: true));
    await updateSettings("householdNickname", nickname,
        updateGlobalState: false);
    return null;
  } catch (e) {
    return _friendlyError(e);
  }
}
