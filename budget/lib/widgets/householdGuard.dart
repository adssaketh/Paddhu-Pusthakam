// Small helpers that stop an edit of somebody else's transaction and say why.
// The rules themselves are in struct/householdView.dart (householdCanEdit).

import 'package:budget/database/tables.dart';
import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdView.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:flutter/material.dart';

/// True when this person may change a transaction owned by [ownerUid]. Otherwise a message says
/// whose it is and false is returned. Always true outside a household.
bool guardCanEditTransaction(String? ownerUid) {
  if (canEditTransactionOwnedBy(ownerUid)) return true;
  final String? name = householdOwnerLabel(ownerUid);
  openSnackbar(
    SnackbarMessage(
      title: kCannotEditOthersMessage,
      description: name == null ? null : "Added by $name",
      icon: Icons.lock_outline_rounded,
    ),
  );
  return false;
}

/// Keeps only the transactions this person may change. When some are left out, a message says so.
List<Transaction> onlyEditableTransactions(List<Transaction> transactions) {
  final List<Transaction> allowed = transactions
      .where((transaction) => canEditTransactionOwnedBy(transaction.ownerUid))
      .toList();
  final int leftOut = transactions.length - allowed.length;
  if (leftOut > 0) {
    openSnackbar(
      SnackbarMessage(
        title: kCannotEditOthersMessage,
        description: allowed.isEmpty
            ? null
            : "$leftOut of ${transactions.length} left out",
        icon: Icons.lock_outline_rounded,
      ),
    );
  }
  return allowed;
}
