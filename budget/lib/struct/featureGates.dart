import 'package:budget/database/tables.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:flutter/material.dart';

// Everything is unlocked. There is no Pro page, store or purchase code.

Future<bool> premiumPopupBudgets(BuildContext context) async => true;

Future<bool> premiumPopupObjectives(BuildContext context,
        {required ObjectiveType objectiveType}) async =>
    true;

Future<bool> premiumPopupPastBudgets(BuildContext context) async => true;

Future premiumPopupAddTransaction(BuildContext context) async {}

Future<void> initializeStoreAndPurchases(
    {required BuildContext context, required bool popRouteWithPurchase}) async {}

class LockedFeature extends StatelessWidget {
  const LockedFeature(
      {required this.child, this.actionAfter, this.showLock = false, Key? key})
      : super(key: key);
  final Widget child;
  final Function? actionAfter;
  final bool showLock;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: () async {
        if (actionAfter != null) await actionAfter!();
      },
      borderRadius: 20,
      color: Colors.transparent,
      child: IgnorePointer(child: child),
    );
  }
}

class FadeOutAndLockFeature extends StatelessWidget {
  const FadeOutAndLockFeature({
    required this.child,
    this.actionAfter,
    this.hasInitiallyDismissed = false,
    this.fadeOutQuick = false,
    super.key,
  });
  final Widget child;
  final VoidCallback? actionAfter;
  final bool hasInitiallyDismissed;
  final bool fadeOutQuick;

  @override
  Widget build(BuildContext context) => child;
}
