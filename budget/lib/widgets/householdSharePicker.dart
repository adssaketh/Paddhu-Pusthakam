// Who can see a loan or a fixed deposit of this person, and whether they may edit it. Used in the loan editor
// and the fixed deposit editor, and shown only inside a household.
//
//  - [SharingChoice] holds the choice while the editor is open. [SharingChoice.save] is called after the
//    item itself was saved: it records the choice when it changed (setItemSharing) and asks for a sync,
//    because loans and deposits live in settings, which the database watcher does not see.
//  - [HouseholdSharePicker] is the card with the member list and the "Members can edit" switch.
//  - [HouseholdSharedBadge] is the small "Shared with ..." line for the owner's own shared items.
//
// Nothing is shared unless the owner picks people here. Only the owner changes who sees an item, whether
// others may edit it, or deletes it.

import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSharedEditRules.dart';
import 'package:budget/struct/householdSharedItems.dart';
import 'package:budget/struct/householdSharingRules.dart';
import 'package:budget/struct/householdSync.dart';
import 'package:budget/widgets/financeUi.dart';
import 'package:flutter/material.dart';

class SharingChoice {
  SharingChoice._(this.kind, this.visibleTo, this.membersCanEdit)
      : _initialVisibleTo = {...visibleTo},
        _initialCanEdit = membersCanEdit;

  /// The choice that is in force now for the item ([localId] is null for an item that is not saved yet,
  /// which is private).
  factory SharingChoice.load(String kind, String? localId) {
    final SharedItemMeta? meta =
        localId == null ? null : ownSharingOf(kind, localId);
    final Set<String> members = householdMemberNames.keys.toSet();
    final Set<String> visible = {
      for (final String uid in meta?.visibleTo ?? const <String>[])
        if (members.isEmpty || members.contains(uid)) uid
    };
    return SharingChoice._(kind, visible, meta?.membersCanEdit ?? false);
  }

  final String kind;
  final Set<String> visibleTo;
  bool membersCanEdit;
  final Set<String> _initialVisibleTo;
  final bool _initialCanEdit;

  bool get changed => sharedChoiceChanged(
        beforeVisibleTo: _initialVisibleTo,
        beforeCanEdit: _initialCanEdit,
        afterVisibleTo: visibleTo,
        afterCanEdit: membersCanEdit,
      );

  /// Call after the item was saved ([localId] is its id now). Returns a message when the choice could not
  /// be recorded, or null.
  Future<String?> save(String localId) async {
    if (!isInHousehold) return null;
    String? error;
    if (changed) {
      error = await setItemSharing(
        kind: kind,
        localId: localId,
        visibleTo: visibleTo.toList(),
        membersCanEdit: membersCanEdit,
      );
    }
    // The item itself may have changed too, and it lives in settings.
    requestHouseholdSync();
    return error;
  }
}

class HouseholdSharePicker extends StatefulWidget {
  const HouseholdSharePicker({required this.choice, Key? key})
      : super(key: key);

  final SharingChoice choice;

  @override
  State<HouseholdSharePicker> createState() => _HouseholdSharePickerState();
}

class _HouseholdSharePickerState extends State<HouseholdSharePicker> {
  @override
  Widget build(BuildContext context) {
    final String me = currentHouseholdUserUid;
    if (!isInHousehold || me == "") return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final SharingChoice choice = widget.choice;

    final List<MapEntry<String, String>> members = [
      for (final MapEntry<String, String> e in householdMemberNames.entries)
        if (e.key != me) MapEntry(e.key, householdMemberName(e.key))
    ]..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FinSectionTitle('Household'),
      FinCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Who can see this',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
              'Only you can see it until you pick people here. It is never added to their net worth or loan totals.',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(0.65))),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  'Nobody else is in your household yet. Invite people from the Household page.',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
            ),
          for (final MapEntry<String, String> member in members)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(member.value, overflow: TextOverflow.ellipsis),
              value: choice.visibleTo.contains(member.key),
              onChanged: (bool? picked) => setState(() {
                if (picked == true) {
                  choice.visibleTo.add(member.key);
                } else {
                  choice.visibleTo.remove(member.key);
                }
              }),
            ),
          if (members.isNotEmpty) ...[
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Members can edit'),
              subtitle: Text(
                  choice.visibleTo.isEmpty
                      ? 'Pick at least one person first.'
                      : 'Off: they can only look. Only you can delete this or change who sees it.',
                  style: const TextStyle(fontSize: 12.5)),
              value: choice.membersCanEdit && choice.visibleTo.isNotEmpty,
              onChanged: choice.visibleTo.isEmpty
                  ? null
                  : (bool value) =>
                      setState(() => choice.membersCanEdit = value),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// "Shared with Asha and Ravi" for an item of this person that is shared. Shows nothing when it is private
/// or outside a household. [padding] is only added when the line is shown.
class HouseholdSharedBadge extends StatelessWidget {
  const HouseholdSharedBadge({
    required this.kind,
    required this.localId,
    this.padding = EdgeInsets.zero,
    Key? key,
  }) : super(key: key);

  final String kind;
  final String localId;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!isInHousehold) return const SizedBox.shrink();
    final SharedItemMeta? meta = ownSharingOf(kind, localId);
    if (meta == null) return const SizedBox.shrink();
    final String label = sharedWithLabel(
        [for (final String uid in meta.visibleTo) householdMemberName(uid)]);
    if (label.isEmpty) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.group_outlined,
            size: 14, color: cs.onSurface.withOpacity(0.55)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
              meta.membersCanEdit ? '$label · can edit' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        ),
      ]),
    );
  }
}
