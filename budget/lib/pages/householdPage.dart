import 'package:budget/functions.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSync.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// Create a household, invite people with a code, join one, and manage members.
class HouseholdPage extends StatefulWidget {
  const HouseholdPage({Key? key}) : super(key: key);

  @override
  State<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends State<HouseholdPage> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  HouseholdSnapshot? _household;
  String? _inviteCode;
  int _waiting = 0; // transactions waiting to be uploaded

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _say(String message) {
    openSnackbar(SnackbarMessage(title: message));
  }

  Future<void> _reload() async {
    if (appStateSettings["hasSignedIn"] != true) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _household = null;
        _inviteCode = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final String? refreshError = await refreshHouseholdState();
    if (!mounted) return;
    if (refreshError != null) {
      setState(() {
        _loading = false;
        _error = refreshError;
      });
      return;
    }
    // Keep this phone's sharing in step with the household (also stops it after a removal).
    await applyHouseholdSyncState();
    if (!isInHousehold) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _household = null;
        _inviteCode = null;
        _waiting = 0;
      });
      return;
    }
    final HouseholdResult<HouseholdSnapshot> result = await loadHousehold();
    String? code;
    if (result.isOk && isHouseholdOwner) code = await currentInviteCode();
    final int waiting =
        householdSyncReady ? await countWaitingTransactions() : 0;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _household = result.value;
      _error = result.error;
      _inviteCode = code;
      _waiting = waiting;
    });
  }

  /// Asks what to do with the transactions already on this phone.
  void _askShare() {
    openPopup(
      context,
      title: "Share your existing transactions?",
      description:
          "Your earlier transactions can be added to the household so everyone sees them. If you keep them private, they stay on this phone and only new transactions are shared.",
      onSubmitLabel: "Share them",
      onCancelLabel: "Keep private",
      onSubmit: () {
        popRoute(context);
        _adopt(true);
      },
      onCancel: () {
        popRoute(context);
        _adopt(false);
      },
    );
  }

  Future<void> _adopt(bool share) async {
    await _run(() => adoptExistingTransactions(share: share),
        success: share
            ? "Your transactions are being shared"
            : "Only new transactions will be shared");
  }

  Future<void> _syncNow() async {
    await _run(syncHouseholdNow, success: "Everything is uploaded");
  }

  /// After creating or joining: ask what to share if that was not decided yet.
  Future<void> _afterSetup() async {
    await _reload();
    if (mounted && isInHousehold && !householdSyncReady) _askShare();
  }

  /// Runs an action that returns an error message (or null), then refreshes the page.
  Future<void> _run(Future<String?> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _say(error);
    } else if (success != null) {
      _say(success);
    }
    await _reload();
  }

  Future<void> _openCreate() async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: "Create a household",
        child: _HouseholdForm(
          firstLabel: "Household name",
          secondLabel: "Your name in the household",
          secondInitial: defaultNickname(),
          buttonLabel: "Create",
          onSubmit: (name, nickname) =>
              createHousehold(name: name, nickname: nickname),
        ),
      ),
      popupWithKeyboard: true,
    );
    await _afterSetup();
  }

  Future<void> _openJoin() async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: "Join with an invite code",
        child: _HouseholdForm(
          firstLabel: "Invite code",
          firstUpperCase: true,
          secondLabel: "Your name in the household",
          secondInitial: defaultNickname(),
          buttonLabel: "Join",
          onSubmit: (code, nickname) =>
              joinHousehold(code: code, nickname: nickname),
        ),
      ),
      popupWithKeyboard: true,
    );
    await _afterSetup();
  }

  Future<void> _openRename() async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: "Your name in the household",
        child: _HouseholdForm(
          secondLabel: "Name",
          secondInitial: householdNickname,
          buttonLabel: "Save",
          onSubmit: (_, nickname) => setMyNickname(nickname),
        ),
      ),
      popupWithKeyboard: true,
    );
    await _reload();
  }

  Future<void> _openMember(HouseholdMember member) async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: member.nickname,
        child: Column(
          children: [
            SettingsContainerSwitch(
              title: "Can delete others' transactions",
              description:
                  "Everyone can always edit and delete their own transactions.",
              initialValue: member.canDelete,
              onSwitched: (value) async {
                final String? error =
                    await setMemberCanDelete(member.uid, value);
                if (error != null) _say(error);
              },
            ),
            const SizedBox(height: 15),
            Button(
              label: "Remove from household",
              onTap: () {
                popRoute(context);
                _confirmRemove(member);
              },
            ),
          ],
        ),
      ),
    );
    await _reload();
  }

  void _confirmRemove(HouseholdMember member) {
    openPopup(
      context,
      title: "Remove ${member.nickname}?",
      description:
          "They lose access to the household's shared data right away. Anything already saved on their phone stays there.",
      onSubmitLabel: "Remove",
      onCancelLabel: "Cancel",
      onSubmit: () {
        popRoute(context);
        _run(() => removeHouseholdMember(member.uid),
            success: "${member.nickname} was removed");
      },
      onCancel: () {
        popRoute(context);
      },
    );
  }

  void _confirmLeave() {
    openPopup(
      context,
      title: "Leave this household?",
      description:
          "You will stop seeing the household's shared data. Everything you entered stays on this phone.",
      onSubmitLabel: "Leave",
      onCancelLabel: "Cancel",
      onSubmit: () {
        popRoute(context);
        _run(() async {
          final String? error = await leaveHousehold();
          if (error == null) await releaseHouseholdTransactions();
          return error;
        }, success: "You left the household");
      },
      onCancel: () {
        popRoute(context);
      },
    );
  }

  Future<void> _makeInviteCode() async {
    if (_busy) return;
    setState(() => _busy = true);
    final HouseholdResult<String> result = await createInviteCode();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.isOk) {
      _say(result.error!);
    } else {
      _say("New invite code made");
    }
    await _reload();
  }

  Widget _signedOut() {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 25, vertical: 40),
      child: Column(
        children: [
          TextFont(
            text: "Sign in with Google to create or join a household.",
            fontSize: 16,
            textAlign: TextAlign.center,
            maxLines: 5,
          ),
          const SizedBox(height: 20),
          Button(
            label: "Sign in with Google",
            onTap: () async {
              await signInAndSync(context, next: () {});
              if (mounted) _reload();
            },
          ),
        ],
      ),
    );
  }

  Widget _notInHousehold() {
    return Column(
      children: [
        const SizedBox(height: 10),
        SettingsContainer(
          title: "Create a household",
          description: "Start a shared budget and invite the people you live with.",
          icon: Icons.add_home_rounded,
          onTap: _openCreate,
        ),
        SettingsContainer(
          title: "Join with an invite code",
          description: "Enter the code the household owner gave you.",
          icon: Icons.group_add_rounded,
          onTap: _openJoin,
        ),
      ],
    );
  }

  Widget _inHousehold(HouseholdSnapshot household) {
    final bool owner = isHouseholdOwner;
    final String myUid = currentHouseholdUserUid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 25, vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFont(
                text: household.name,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                maxLines: 2,
              ),
              const SizedBox(height: 2),
              TextFont(
                text: owner ? "You are the owner" : "You are a member",
                fontSize: 15,
              ),
            ],
          ),
        ),
        SettingsContainer(
          title: "Your name in the household",
          description: householdNickname,
          icon: Icons.badge_rounded,
          onTap: _openRename,
        ),
        if (!householdSyncReady)
          SettingsContainer(
            title: "Choose what to share",
            description:
                "Nothing is shared yet. Tap to choose what happens to your existing transactions.",
            icon: Icons.sync_problem_rounded,
            onTap: _askShare,
          )
        else ...[
          SettingsContainer(
            title: "Shared transactions",
            description: _waiting == 0
                ? "Everything is uploaded. Tap to check now."
                : "$_waiting waiting to upload. Tap to upload now.",
            icon: Icons.cloud_upload_rounded,
            onTap: _syncNow,
          ),
          SettingsContainer(
            title: "Share my earlier transactions",
            description:
                "Add the transactions you kept private on this phone to the household.",
            icon: Icons.history_rounded,
            onTap: _askShare,
          ),
        ],
        if (owner) ...[
          SettingsContainerSwitch(
            title: "Show account balances to members",
            description:
                "Members always see their own balances. Accounts stay private to their owner.",
            initialValue: household.showBalances,
            onSwitched: (value) {
              _run(() => setShowBalances(value));
            },
          ),
          SettingsContainer(
            title: _inviteCode == null ? "Make an invite code" : "Make a new invite code",
            description: "A new code cancels the old one.",
            icon: Icons.key_rounded,
            onTap: _makeInviteCode,
          ),
          if (_inviteCode != null) ...[
            SettingsContainer(
              title: "Invite code: ${formatInviteCode(_inviteCode!)}",
              description: "Tap to copy. Anyone with this code can join.",
              icon: Icons.copy_rounded,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: _inviteCode!));
                _say("Invite code copied");
              },
            ),
            SettingsContainer(
              title: "Cancel invite code",
              description: "Stop people joining with the current code.",
              icon: Icons.link_off_rounded,
              onTap: () {
                _run(revokeInviteCode, success: "Invite code cancelled");
              },
            ),
          ],
        ],
        Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 25, end: 25, top: 20, bottom: 6),
          child: TextFont(
            text:
                "Members (${household.members.length} of $kMaxHouseholdMembers)",
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        for (final HouseholdMember member in household.members)
          SettingsContainer(
            title: member.isOwner ? "${member.nickname} (owner)" : member.nickname,
            description: member.isOwner
                ? null
                : (member.canDelete
                    ? "Can delete others' transactions"
                    : "Can delete only their own transactions"),
            icon: Icons.person_rounded,
            onTap: owner && !member.isOwner && member.uid != myUid
                ? () => _openMember(member)
                : null,
          ),
        if (!owner) ...[
          const SizedBox(height: 25),
          Center(
            child: Button(
              label: "Leave household",
              onTap: _confirmLeave,
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (appStateSettings["hasSignedIn"] != true) {
      content = _signedOut();
    } else if (_error != null) {
      content = Padding(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 25, vertical: 40),
        child: Column(
          children: [
            TextFont(
              text: _error!,
              fontSize: 16,
              textAlign: TextAlign.center,
              maxLines: 6,
            ),
            const SizedBox(height: 20),
            Button(label: "Try again", onTap: _reload),
          ],
        ),
      );
    } else if (_household != null) {
      content = _inHousehold(_household!);
    } else {
      content = _notInHousehold();
    }

    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      expandedHeight: 56,
      title: "Household",
      slivers: [
        SliverToBoxAdapter(child: content),
      ],
    );
  }
}

/// A bottom sheet form with up to two text fields and one button.
/// [onSubmit] returns an error message to show, or null when it worked (the sheet then closes).
class _HouseholdForm extends StatefulWidget {
  const _HouseholdForm({
    Key? key,
    this.firstLabel,
    this.firstUpperCase = false,
    required this.secondLabel,
    this.secondInitial = "",
    required this.buttonLabel,
    required this.onSubmit,
  }) : super(key: key);

  final String? firstLabel;
  final bool firstUpperCase;
  final String secondLabel;
  final String secondInitial;
  final String buttonLabel;
  final Future<String?> Function(String first, String second) onSubmit;

  @override
  State<_HouseholdForm> createState() => _HouseholdFormState();
}

class _HouseholdFormState extends State<_HouseholdForm> {
  String _first = "";
  late String _second = widget.secondInitial;
  String? _error;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final String? error = await widget.onSubmit(_first, _second);
    if (!mounted) return;
    if (error == null) {
      popRoute(context);
    } else {
      setState(() {
        _submitting = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.firstLabel != null) ...[
          TextInput(
            labelText: widget.firstLabel!,
            autoFocus: true,
            textCapitalization: widget.firstUpperCase
                ? TextCapitalization.characters
                : TextCapitalization.words,
            onChanged: (value) => _first = value,
          ),
          const SizedBox(height: 10),
        ],
        TextInput(
          labelText: widget.secondLabel,
          initialValue: widget.secondInitial,
          autoFocus: widget.firstLabel == null,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => _second = value,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          TextFont(
            text: _error!,
            fontSize: 14,
            textColor: Theme.of(context).colorScheme.error,
            maxLines: 4,
          ),
        ],
        const SizedBox(height: 20),
        Button(
          label: _submitting ? "Please wait..." : widget.buttonLabel,
          disabled: _submitting,
          onTap: _submit,
        ),
      ],
    );
  }
}
