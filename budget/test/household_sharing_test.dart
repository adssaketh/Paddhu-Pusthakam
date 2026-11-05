// Rules for sharing loans and fixed deposits: who sees, who edits, what happens when access goes.
// Run with: dart run test/household_sharing_test.dart

import '../lib/struct/householdSharingRules.dart';
import '../lib/struct/settingsMerge.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

const Set<String> members = {'me', 'sis', 'dad', 'mom'};

SharedItemMeta item({
  String kind = kSharedKindFixedDeposit,
  String owner = 'me',
  String localId = 'fd-1',
  List<String> visibleTo = const [],
  bool canEdit = false,
  int updatedAt = 100,
}) =>
    SharedItemMeta(
      kind: kind,
      ownerUid: owner,
      localId: localId,
      visibleTo: visibleTo,
      membersCanEdit: canEdit,
      updatedAt: updatedAt,
    );

bool sees(SharedItemMeta i, String uid, [Set<String> m = members]) =>
    sharedItemVisible(item: i, uid: uid, memberUids: m);

bool edits(SharedItemMeta i, String uid, [Set<String> m = members]) =>
    sharedItemCanEdit(item: i, uid: uid, memberUids: m);

String? write(SharedItemMeta? existing, SharedItemMeta incoming, String uid, [Set<String> m = members]) =>
    sharedItemWriteError(existing: existing, incoming: incoming, uid: uid, memberUids: m);

void main() {
  // ---- who sees
  final SharedItemMeta priv = item();
  check(sees(priv, 'me'), 'the owner sees their own item');
  check(!sees(priv, 'sis'), 'private by default: nobody else sees it');
  final SharedItemMeta some = item(visibleTo: const ['sis', 'dad']);
  check(sees(some, 'sis') && sees(some, 'dad'), 'picked members see it');
  check(!sees(some, 'mom'), 'a member who was not picked does not see it');
  check(!sees(some, ''), 'an empty uid sees nothing');
  check(!sees(some, 'stranger'), 'a person outside the household sees nothing');
  check(!sees(some, 'sis', const {'me', 'dad'}), 'a person who left no longer sees it');
  check(!sees(some, 'sis', const {'sis', 'dad'}), 'items of an owner who left are seen by nobody');
  check(!sees(some, 'me', const {'sis', 'dad'}), 'the owner who left is not in the household any more');

  // ---- who edits
  check(edits(priv, 'me'), 'the owner edits their own item');
  check(!edits(some, 'sis'), 'a viewer cannot edit when the owner has not allowed it');
  final SharedItemMeta editable = item(visibleTo: const ['sis'], canEdit: true);
  check(edits(editable, 'sis'), 'a viewer edits when the owner allowed it');
  check(!edits(editable, 'dad'), 'allowing edits does not open it to members who were not picked');
  check(!edits(editable, 'sis', const {'me', 'dad'}), 'a person who left cannot edit');
  check(sharedItemCanManage(item: editable, uid: 'me'), 'the owner manages the item');
  check(!sharedItemCanManage(item: editable, uid: 'sis'), 'an editor cannot delete it or change who sees it');
  check(!sharedItemCanManage(item: editable, uid: ''), 'an empty uid manages nothing');

  // ---- cleaning the picked members
  check(
      cleanVisibleTo(ownerUid: 'me', requested: const ['sis', 'dad'], memberUids: members).join(',') == 'sis,dad',
      'picked members are kept in order');
  check(
      cleanVisibleTo(ownerUid: 'me', requested: const ['me', 'sis'], memberUids: members).join(',') == 'sis',
      'the owner is never in the list');
  check(
      cleanVisibleTo(ownerUid: 'me', requested: const ['sis', 'sis', 'dad'], memberUids: members).join(',') ==
          'sis,dad',
      'duplicates are dropped');
  check(
      cleanVisibleTo(ownerUid: 'me', requested: const ['ghost', '', 'mom'], memberUids: members).join(',') == 'mom',
      'people outside the household and blanks are dropped');
  final Set<String> big = {'me', for (int i = 1; i <= 10; i++) 'u$i'};
  check(
      cleanVisibleTo(ownerUid: 'me', requested: [for (int i = 1; i <= 10; i++) 'u$i'], memberUids: big).length ==
          kMaxSharedWith,
      'at most 7 people besides the owner');
  check(kMaxSharedWith == 7, 'the list limit follows the household limit of 8');

  // ---- audience change
  final SharedAudienceChange change = sharedAudienceChange(const ['sis', 'dad'], const ['dad', 'mom']);
  check(change.added.join(',') == 'mom' && change.removed.join(',') == 'sis', 'added and removed people are found');
  check(sharedAudienceChange(const ['sis'], const ['sis']).isEmpty, 'no change is empty');

  // ---- writes (mirrors firestore.rules)
  check(write(null, some, 'me') == null, 'the owner can share a new item');
  check(write(null, some, 'sis') != null, 'nobody can create an item for somebody else');
  check(write(null, some, 'stranger') != null, 'a stranger cannot create anything');
  check(write(null, item(kind: 'budget'), 'me') != null, 'only loans and deposits can be shared');
  check(write(null, item(visibleTo: const ['ghost']), 'me') != null, 'cannot share with somebody outside the household');
  check(write(null, item(visibleTo: const ['me']), 'me') != null, 'the owner cannot list themselves');
  check(write(null, item(visibleTo: const ['sis', 'sis']), 'me') != null, 'the same person cannot be listed twice');
  check(write(some, some.copyWith(visibleTo: const ['sis']), 'me') == null, 'the owner can take people out');
  check(write(some, some.copyWith(membersCanEdit: true), 'me') == null, 'the owner can allow edits');
  check(write(some, item(owner: 'sis', visibleTo: const ['sis', 'dad']), 'me') != null, 'the owner cannot be changed');
  check(write(some, item(localId: 'fd-2', visibleTo: const ['sis', 'dad']), 'me') != null, 'the item cannot become another one');
  check(write(some, item(kind: kSharedKindLoan, visibleTo: const ['sis', 'dad']), 'me') != null, 'the kind cannot change');

  check(write(editable, editable.copyWith(updatedAt: 200), 'sis') == null, 'an editor can save a change');
  check(write(some, some.copyWith(updatedAt: 200), 'sis') != null, 'a viewer cannot save when edits are not allowed');
  check(write(editable, editable.copyWith(membersCanEdit: false), 'sis') != null, 'an editor cannot switch editing off');
  check(write(editable, editable.copyWith(visibleTo: const ['sis', 'dad']), 'sis') != null, 'an editor cannot add people');
  check(write(editable, editable.copyWith(visibleTo: const []), 'sis') != null, 'an editor cannot take people out');
  check(write(editable, editable.copyWith(updatedAt: 200), 'dad') != null, 'a member who was not picked cannot edit');
  check(write(editable, editable.copyWith(updatedAt: 200), 'sis', const {'me', 'dad'}) != null, 'a person who left cannot save');

  // ---- reading a document
  final SharedItemMeta? parsed = SharedItemMeta.fromJson({
    'kind': 'loan',
    'ownerUid': 'me',
    'localId': 'obj-1',
    'visibleTo': ['sis', 7, '', 'dad'],
    'membersCanEdit': true,
    '_u': 250.0,
  });
  check(parsed != null && parsed.visibleTo.join(',') == 'sis,dad', 'bad entries in the list are ignored');
  check(parsed != null && parsed.membersCanEdit && parsed.updatedAt == 250, 'fields are read');
  check(SharedItemMeta.fromJson({'kind': 'loan', 'ownerUid': 'me'}) == null, 'a document without an id is ignored');
  check(SharedItemMeta.fromJson({'kind': 'x', 'ownerUid': 'me', 'localId': '1'}) == null, 'an unknown kind is ignored');
  check(SharedItemMeta.fromJson('nope') == null, 'something that is not a document is ignored');
  final SharedItemMeta? bare = SharedItemMeta.fromJson({'kind': 'fd', 'ownerUid': 'me', 'localId': 'fd-1'});
  check(bare != null && bare.visibleTo.isEmpty && !bare.membersCanEdit && bare.updatedAt == 0,
      'missing fields mean private, not editable');
  final SharedItemMeta again = SharedItemMeta.fromJson(editable.toJson())!;
  check(again.visibleTo.join(',') == 'sis' && again.membersCanEdit && again.updatedAt == 100, 'a document survives a round trip');

  // ---- document id
  check(sharedItemDocId('fd', 'me', 'fd-1') == 'fd-me-fd-1', 'document id has the kind, owner and local id');
  check(sharedItemDocId('loan', 'me', 'a/b') == 'loan-me-a_b', 'a slash in the local id is replaced');
  check(sharedItemDocId('fd', 'me', 'x') != sharedItemDocId('fd', 'sis', 'x'), 'two owners can use the same local id');

  // ---- newer copy wins
  check(sharedRemoteIsNewer(localUpdatedAt: 100, remoteUpdatedAt: 101), 'a newer server copy replaces mine');
  check(!sharedRemoteIsNewer(localUpdatedAt: 100, remoteUpdatedAt: 100), 'the same time is my own change coming back');
  check(!sharedRemoteIsNewer(localUpdatedAt: 100, remoteUpdatedAt: 99), 'an older server copy is ignored');

  // ---- owner upload
  check(sharedUploadAction(localUpdatedAt: 100, serverUpdatedAt: null) == SharedUploadAction.upload,
      'an item not on the server yet is uploaded');
  check(sharedUploadAction(localUpdatedAt: 100, serverUpdatedAt: 90) == SharedUploadAction.upload,
      'my change is uploaded over an older server copy');
  check(sharedUploadAction(localUpdatedAt: 100, serverUpdatedAt: 100) == SharedUploadAction.skip,
      'nothing to upload when the server already has it');
  check(sharedUploadAction(localUpdatedAt: 100, serverUpdatedAt: 150) == SharedUploadAction.takeRemote,
      'an editor changed it meanwhile: take theirs, do not overwrite');

  // ---- copies that must go
  check(
      sharedCopiesToRemove(heldDocIds: const {'a', 'b', 'c'}, visibleDocIds: const {'b'}).join(',') == 'a,c',
      'copies the server no longer shows me are removed');
  check(sharedCopiesToRemove(heldDocIds: const {'a'}, visibleDocIds: const {'a', 'z'}).isEmpty,
      'copies I may still see are kept');
  final Set<String> drop = sharedCopiesToDropOnLeave(
      heldOwnerByDocId: const {'x': 'sis', 'y': 'me', 'z': 'dad'}, myUid: 'me');
  check(drop.length == 2 && drop.contains('x') && drop.contains('z') && !drop.contains('y'),
      'leaving drops other people\'s copies and keeps my own items');

  // ---- clearing what I shared before I left or was removed
  final Set<String> purge = sharedServerDocsToPurge(
      serverDocIds: const {'fd-me-a', 'loan-me-b'}, activeDocIds: const {});
  check(purge.length == 2, 'after joining again, everything I shared before is stale and goes');
  final Set<String> purgeSome = sharedServerDocsToPurge(
      serverDocIds: const {'fd-me-a', 'loan-me-b'}, activeDocIds: const {'fd-me-a'});
  check(purgeSome.length == 1 && purgeSome.contains('loan-me-b'),
      'an item I still share is not purged');
  check(sharedServerDocsToPurge(serverDocIds: const {}, activeDocIds: const {'fd-me-a'}).isEmpty,
      'nothing on the server means nothing to purge');
  // A person who left is no longer a member, so nobody sees their items any more.
  final SharedItemMeta leaverItem = item(owner: 'sis', visibleTo: const ['me']);
  check(sees(leaverItem, 'me'), 'while sis is a member, I see what she shared with me');
  check(!sees(leaverItem, 'me', const {'me', 'dad', 'mom'}),
      'after sis left or was removed, her items are hidden from me');
  // Handing the household over changes who owns it, not who owns an item.
  check(sharedItemCanManage(item: leaverItem, uid: 'sis'), 'an item stays with the person who made it');
  check(!sharedItemCanManage(item: leaverItem, uid: 'me'),
      'the new household owner does not become the owner of other people\'s items');

  // ---- the settings that hold the owner's choices
  check(isSyncedSettingKey('householdSharedOwn'), 'who I share with is kept in step between my own phones');
  check(!isSyncedSettingKey('householdSharedUploaded'), 'what this phone sent is not copied to my other phones');
  final Map<String, dynamic> localOwn = {
    'householdSharedOwn': {'fd-me-a': {'_u': 10, '_d': false, 'visibleTo': ['sis']}},
  };
  final Map<String, dynamic> remoteOwn = {
    'householdSharedOwn': {
      'fd-me-a': {'_u': 20, '_d': true},
      'loan-me-b': {'_u': 5, '_d': false, 'visibleTo': ['dad']},
    },
  };
  final Map merged = mergeSettings(localOwn, remoteOwn).settings['householdSharedOwn'] as Map;
  check(merged['loan-me-b'] != null, 'a choice made on the other phone is added');
  check((merged['fd-me-a'] as Map)['_d'] == true, 'the newer change (made private again) wins');

  print('household sharing: all checks passed');
}
