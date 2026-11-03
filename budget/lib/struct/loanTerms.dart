// Where the terms of instalment loans (interest, GST, which EMIs are paid) are kept: in the app's settings,
// under "loanTerms", one entry per loan (the loan's objectivePk). Settings are part of the backup, and no
// database change is needed. Each entry carries "_u" (when it was last changed) and a deleted loan leaves
// a marker behind, so the other devices see the change when the settings sync (settingsMerge.dart).

import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/settingsMerge.dart';
import 'package:budget/struct/settings.dart';

Map<String, dynamic> _allLoanTerms() {
  final dynamic stored = appStateSettings["loanTerms"];
  return stored is Map ? Map<String, dynamic>.from(stored) : <String, dynamic>{};
}

/// The terms saved for this loan, or null for an ordinary loan.
LoanTerms? loanTermsFor(String objectivePk) {
  final dynamic item = _allLoanTerms()[objectivePk];
  if (isDeletedItem(item)) return null;
  return LoanTerms.fromJson(item);
}

/// Pks of every loan that has terms.
List<String> loanPksWithTerms() {
  final Map<String, dynamic> all = _allLoanTerms();
  return [for (final String k in all.keys) if (!isDeletedItem(all[k])) k];
}

Future<void> saveLoanTerms(String objectivePk, LoanTerms terms) async {
  final Map<String, dynamic> all = _allLoanTerms();
  all[objectivePk] = stampItem(terms.toJson());
  await updateSettings(
    "loanTerms",
    all,
    updateGlobalState: false,
    pagesNeedingRefresh: [0],
    setStateAllPageFrameworks: true,
  );
}

Future<void> removeLoanTerms(String objectivePk) async {
  final Map<String, dynamic> all = _allLoanTerms();
  if (all[objectivePk] == null || isDeletedItem(all[objectivePk])) return;
  all[objectivePk] = deletedMarker();
  await updateSettings("loanTerms", all, updateGlobalState: false);
}
