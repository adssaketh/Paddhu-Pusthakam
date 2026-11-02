import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/smsTransactionParser.dart';
import 'package:budget/widgets/openPopup.dart';

/// Messages already handled in this run, so the same notification (posted again when it is updated
/// or dismissed) does not open the Add Transaction page twice.
final List<String> _handledSmsKeys = [];

/// Called with a notification's title (the SMS sender) and content (the SMS text) when no scanner
/// template matched. Opens the Add Transaction page prefilled with the amount, direction, title and
/// a suggested category. Nothing is saved until you press save, same as template notifications.
///
/// Returns true when a page was opened.
Future<bool> queueTransactionFromSmartParse(String? sender, String? body) async {
  if (appStateSettings["notificationSmartParse"] != true) return false;
  if (sender == null || body == null) return false;
  if (!looksLikeSenderId(sender)) return false;

  final ParsedSmsTransaction? parsed = parseSmsTransaction(sender, body);
  if (parsed == null) return false;
  // The matching bank debit is its own SMS, adding this one too would count the bill twice.
  if (parsed.cardPayment) return false;
  if (parsed.amount <= 0) return false;

  final String dedupeKey = '$sender|$body';
  if (_handledSmsKeys.contains(dedupeKey)) return false;
  _handledSmsKeys.insert(0, dedupeKey);
  if (_handledSmsKeys.length > 50) _handledSmsKeys.removeLast();

  // 1. A category you chose for this title before (Paddhu's associated titles) beats the rules.
  TransactionCategory? category =
      (await database.getSimilarAssociatedTitles(title: parsed.title, limit: 1))
          .firstOrNull
          ?.category;

  // 2. Otherwise the rule-based suggestion, when it maps to one of the default categories.
  if (category == null && parsed.categoryPk != null) {
    category = await database.getCategoryInstanceOrNull(parsed.categoryPk!);
  }

  // A remembered category of the wrong direction (e.g. an income category on a payment) is dropped.
  if (category != null && category.income == parsed.isExpense) {
    category = null;
  }

  final String? account = parsed.instrumentName;

  pushRoute(
    null,
    AddTransactionPage(
      selectedIncome: !parsed.isExpense,
      useCategorySelectedIncome: false,
      routesToPopAfterDelete: RoutesToPopAfterDelete.None,
      selectedAmount: parsed.amount,
      selectedTitle: parsed.title,
      selectedCategory: category,
      selectedNotes: account,
      startInitialAddTransactionSequence: false,
    ),
  );
  return true;
}
