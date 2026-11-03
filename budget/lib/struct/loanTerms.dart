// Where the terms of instalment loans (interest, GST, which EMIs are paid) are kept: in the app's settings,
// under "loanTerms", one entry per loan (the loan's objectivePk). Settings are part of the backup, and no
// database change is needed.

import 'package:budget/struct/loanSchedule.dart';
import 'package:budget/struct/settings.dart';

Map<String, dynamic> _allLoanTerms() {
  final dynamic stored = appStateSettings["loanTerms"];
  return stored is Map ? Map<String, dynamic>.from(stored) : <String, dynamic>{};
}

/// The terms saved for this loan, or null for an ordinary loan.
LoanTerms? loanTermsFor(String objectivePk) {
  return LoanTerms.fromJson(_allLoanTerms()[objectivePk]);
}

/// Pks of every loan that has terms.
List<String> loanPksWithTerms() => _allLoanTerms().keys.toList();

Future<void> saveLoanTerms(String objectivePk, LoanTerms terms) async {
  final Map<String, dynamic> all = _allLoanTerms();
  all[objectivePk] = terms.toJson();
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
  if (all.remove(objectivePk) == null) return;
  await updateSettings("loanTerms", all, updateGlobalState: false);
}
