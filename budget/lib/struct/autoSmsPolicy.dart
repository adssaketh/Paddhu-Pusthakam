// Decides what happens to a bank SMS that Ping handed over by itself: save it straight away, or put
// it in the review list for you to look at.
//
// "Confident" means the SMS tells us everything that matters and nothing needs guessing:
//   - the account / card is one you named in knownAccounts.dart (and is not closed),
//   - the SMS names a merchant (or it is a salary / interest / cashback credit),
//   - a category is known for it: one you picked for this title before (Paddhu's "associated titles",
//     that is the learning part), or one of the keyword rules in smsTransactionParser.dart.
// Everything else is "review": transfers to people (a UPI handle with no keyword), accounts that are not
// in your list, closed accounts, pension / provident fund rows and credit card bill debits.
//
// Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

import 'pingImport.dart';

enum AutoSmsVerdict { save, review }

class AutoSmsDecision {
  const AutoSmsDecision(this.verdict, this.reason);

  final AutoSmsVerdict verdict;

  /// Short sentence, for the review list and for debugging.
  final String reason;

  bool get isSave => verdict == AutoSmsVerdict.save;
}

/// [learnedCategoryPk] is the category you chose before for a transaction with this same title, or null.
/// The caller looks it up (it needs the database); this function only decides.
AutoSmsDecision decideAutoSave(PingImportRow row, {String? learnedCategoryPk}) {
  if (!row.knownAccount) {
    return const AutoSmsDecision(
        AutoSmsVerdict.review, 'the account is not in your list');
  }
  if (row.closed) {
    return const AutoSmsDecision(AutoSmsVerdict.review, 'a closed account');
  }
  if (!row.tickByDefault) {
    return const AutoSmsDecision(AutoSmsVerdict.review,
        'a pension / provident fund row or a credit card bill payment');
  }

  final bool incomeLabel = !row.isExpense && row.categoryLabel == 'income';
  if (row.merchant.trim().isEmpty && !incomeLabel) {
    return const AutoSmsDecision(
        AutoSmsVerdict.review, 'the SMS does not name a merchant');
  }

  final bool hasCategory = learnedCategoryPk != null || row.categoryPk != null;
  if (!hasCategory) {
    return const AutoSmsDecision(AutoSmsVerdict.review,
        'no category is known for it (maybe a transfer to a person)');
  }

  return AutoSmsDecision(
      AutoSmsVerdict.save,
      learnedCategoryPk != null
          ? 'a category you chose before'
          : 'a known keyword (merchant, salary, interest...)');
}
