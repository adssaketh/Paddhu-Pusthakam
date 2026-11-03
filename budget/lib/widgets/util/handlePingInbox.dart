// Runs the automatic Ping inbox (struct/pingInbox.dart) and tells you what it did.
// Called when the app starts and every time it comes back to the front.

import 'package:budget/pages/importFromPingPage.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/pingInbox.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:flutter/material.dart';

Future<void> handlePingInbox({Duration delay = Duration.zero}) async {
  try {
    if (delay > Duration.zero) await Future.delayed(delay);
    final PingInboxResult result = await processPingInbox();
    if (!result.didSomething) return;

    final List<String> parts = [];
    if (result.saved > 0) {
      parts.add(
          'Added ${result.saved} transaction${result.saved == 1 ? '' : 's'}');
    }
    if (result.fixedDeposits > 0) {
      parts.add(
          '${result.fixedDeposits} fixed deposit${result.fixedDeposits == 1 ? '' : 's'}');
    }
    if (result.toReview > 0) {
      parts.add('${result.toReview} to review');
    }
    openSnackbar(SnackbarMessage(
      title: 'From Ping: ${parts.join(', ')}',
      description: result.toReview > 0
          ? 'Tap to review the ones that were not added automatically.'
          : null,
      icon: appStateSettings["outlinedIcons"] == true
          ? Icons.sms_outlined
          : Icons.sms_rounded,
      timeout: const Duration(seconds: 6),
      onTap: result.toReview > 0
          ? () => pushRoute(null, const ImportFromPingPage(reviewQueue: true))
          : null,
    ));
  } catch (_) {
    // Never let a problem here disturb the app.
  }
}
