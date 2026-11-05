// Pure rules for sharing loans and fixed deposits inside a household.
// No Flutter or database imports, so tests can run this file with plain `dart run`.
//
// One shared item is one Firestore document under the household. Its fields (see [SharedItemMeta]):
//   kind            'loan' or 'fd'
//   ownerUid        who owns the item (only the owner deletes it or changes who can see it)
//   localId         the item's id on the owner's phone (the loan's objectivePk, or the deposit's id)
//   visibleTo       members, besides the owner, who can see it (empty = only the owner)
//   membersCanEdit  true = everyone in visibleTo may also change it
//   _u              when it was last changed (ms), the newer copy wins, like settingsMerge.dart
//   payload         the loan (its row and terms) or the deposit, as a map
//
// Deleting a document, or taking a person out of visibleTo, makes it vanish from that person's query,
// so their phone drops its copy. No delete marker is needed on the server.

import 'householdOwnership.dart';

const String kSharedKindLoan = 'loan';
const String kSharedKindFixedDeposit = 'fd';
const Set<String> kSharedKinds = {kSharedKindLoan, kSharedKindFixedDeposit};

/// Most people an item can be shared with: everyone in a full household except the owner.
const int kMaxSharedWith = kMaxHouseholdMembers - 1;

class SharedItemMeta {
  const SharedItemMeta({
    required this.kind,
    required this.ownerUid,
    required this.localId,
    this.visibleTo = const [],
    this.membersCanEdit = false,
    this.updatedAt = 0,
  });

  final String kind;
  final String ownerUid;
  final String localId;
  final List<String> visibleTo;
  final bool membersCanEdit;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'ownerUid': ownerUid,
        'localId': localId,
        'visibleTo': visibleTo,
        'membersCanEdit': membersCanEdit,
        '_u': updatedAt,
      };

  /// Reads the fields of a document. Anything missing or of the wrong type becomes the safe value
  /// (nobody can see it, nobody can edit it).
  static SharedItemMeta? fromJson(dynamic j) {
    if (j is! Map) return null;
    final dynamic kind = j['kind'];
    final dynamic owner = j['ownerUid'];
    final dynamic local = j['localId'];
    if (kind is! String || !kSharedKinds.contains(kind)) return null;
    if (owner is! String || owner.isEmpty) return null;
    if (local is! String || local.isEmpty) return null;
    final dynamic vt = j['visibleTo'];
    return SharedItemMeta(
      kind: kind,
      ownerUid: owner,
      localId: local,
      visibleTo: vt is List ? [for (final dynamic u in vt) if (u is String && u.isNotEmpty) u] : const [],
      membersCanEdit: j['membersCanEdit'] == true,
      updatedAt: j['_u'] is num ? (j['_u'] as num).toInt() : 0,
    );
  }

  SharedItemMeta copyWith({
    List<String>? visibleTo,
    bool? membersCanEdit,
    int? updatedAt,
  }) =>
      SharedItemMeta(
        kind: kind,
        ownerUid: ownerUid,
        localId: localId,
        visibleTo: visibleTo ?? this.visibleTo,
        membersCanEdit: membersCanEdit ?? this.membersCanEdit,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// The document id for an item. Different owners can have items with the same local id, so the owner is
/// part of it. A "/" would split the path, so it is replaced.
String sharedItemDocId(String kind, String ownerUid, String localId) =>
    '$kind-$ownerUid-${localId.replaceAll('/', '_')}';

/// The people an owner may pick from: members only, never the owner, no duplicates, no blanks, at most
/// [kMaxSharedWith]. The order of [requested] is kept.
List<String> cleanVisibleTo({
  required String ownerUid,
  required Iterable<String> requested,
  required Set<String> memberUids,
}) {
  final List<String> out = [];
  for (final String u in requested) {
    if (u.isEmpty || u == ownerUid) continue;
    if (!memberUids.contains(u) || out.contains(u)) continue;
    if (out.length >= kMaxSharedWith) break;
    out.add(u);
  }
  return out;
}

/// True when [uid] may see the item. [memberUids] are the people in the household right now.
/// Items of someone who is no longer in the household are seen by nobody.
bool sharedItemVisible({
  required SharedItemMeta item,
  required String uid,
  required Set<String> memberUids,
}) {
  if (uid.isEmpty || !memberUids.contains(uid)) return false;
  if (!memberUids.contains(item.ownerUid)) return false;
  return uid == item.ownerUid || item.visibleTo.contains(uid);
}

/// True when [uid] may change the item's details (not delete it, not change who can see it).
bool sharedItemCanEdit({
  required SharedItemMeta item,
  required String uid,
  required Set<String> memberUids,
}) {
  if (!sharedItemVisible(item: item, uid: uid, memberUids: memberUids)) return false;
  return uid == item.ownerUid || item.membersCanEdit;
}

/// Only the owner deletes an item or changes who can see it or whether others can edit it.
bool sharedItemCanManage({required SharedItemMeta item, required String uid}) =>
    uid.isNotEmpty && uid == item.ownerUid;

/// Who is added and who is taken away when the audience changes (used to warn the owner).
class SharedAudienceChange {
  const SharedAudienceChange(this.added, this.removed);
  final List<String> added;
  final List<String> removed;
  bool get isEmpty => added.isEmpty && removed.isEmpty;
}

SharedAudienceChange sharedAudienceChange(List<String> before, List<String> after) => SharedAudienceChange(
      [for (final String u in after) if (!before.contains(u)) u],
      [for (final String u in before) if (!after.contains(u)) u],
    );

/// Why [uid] may not write [incoming] over [existing] (null when creating), or null when the write is fine.
/// This mirrors what firestore.rules must enforce, so the app and the rules agree.
String? sharedItemWriteError({
  required SharedItemMeta? existing,
  required SharedItemMeta incoming,
  required String uid,
  required Set<String> memberUids,
}) {
  if (uid.isEmpty || !memberUids.contains(uid)) return 'You are not in this household.';
  if (!kSharedKinds.contains(incoming.kind)) return 'Unknown kind of item.';

  if (existing == null) {
    if (incoming.ownerUid != uid) return 'You can only share your own items.';
    return _audienceError(incoming, memberUids);
  }

  // same item: who it is and what it is can never change
  if (incoming.ownerUid != existing.ownerUid ||
      incoming.kind != existing.kind ||
      incoming.localId != existing.localId) {
    return 'The owner of an item cannot be changed.';
  }
  if (uid == existing.ownerUid) return _audienceError(incoming, memberUids);

  // somebody else: only when the owner allowed it, and only the details
  if (!sharedItemCanEdit(item: existing, uid: uid, memberUids: memberUids)) {
    return 'The owner has not allowed you to edit this.';
  }
  if (incoming.membersCanEdit != existing.membersCanEdit ||
      !_sameList(incoming.visibleTo, existing.visibleTo)) {
    return 'Only the owner can change who sees or edits this.';
  }
  return null;
}

String? _audienceError(SharedItemMeta item, Set<String> memberUids) {
  if (item.visibleTo.length > kMaxSharedWith) return 'Too many people.';
  final Set<String> seen = {};
  for (final String u in item.visibleTo) {
    if (u == item.ownerUid) return 'The owner is always included.';
    if (!memberUids.contains(u)) return 'That person is not in the household.';
    if (!seen.add(u)) return 'The same person is listed twice.';
  }
  return null;
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A copy that came from the server replaces the one on this phone only when it is newer. An equal
/// time means it is the same change coming back (for example the owner's own upload).
bool sharedRemoteIsNewer({required int localUpdatedAt, required int remoteUpdatedAt}) =>
    remoteUpdatedAt > localUpdatedAt;

enum SharedUploadAction { upload, takeRemote, skip }

/// What the owner's phone does with a changed item: [serverUpdatedAt] is the time on the server copy,
/// or null when the item is not there yet. If somebody with edit rights changed it in the meantime, the
/// server copy is taken instead of being overwritten.
SharedUploadAction sharedUploadAction({required int localUpdatedAt, required int? serverUpdatedAt}) {
  if (serverUpdatedAt == null) return SharedUploadAction.upload;
  if (serverUpdatedAt > localUpdatedAt) return SharedUploadAction.takeRemote;
  if (serverUpdatedAt == localUpdatedAt) return SharedUploadAction.skip;
  return SharedUploadAction.upload;
}

/// Copies other people shared with me that this phone still holds but the server no longer shows me
/// (visibility taken away, item deleted, or the owner left). [heldDocIds] are the copies on this phone,
/// [visibleDocIds] what the server shows me now.
Set<String> sharedCopiesToRemove({required Set<String> heldDocIds, required Set<String> visibleDocIds}) =>
    heldDocIds.difference(visibleDocIds);

/// When I leave or am removed, every copy of somebody else's item goes. [heldOwnerByDocId] maps a copy's
/// document id to the owner's uid. My own items stay.
Set<String> sharedCopiesToDropOnLeave({required Map<String, String> heldOwnerByDocId, required String myUid}) =>
    {for (final MapEntry<String, String> e in heldOwnerByDocId.entries) if (e.value != myUid) e.key};
