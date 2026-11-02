import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/knownAccounts.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/smsTransactionParser.dart';
import 'package:budget/widgets/openPopup.dart';

/// Messages already handled in this run, so the same notification (posted again when it is updated
/// or dismissed) does not open the Add Transaction page twice.
final List<String> _handledSmsKeys = [];

/// Apps that show your SMS. A notification from one of them is treated as an SMS even when its title is a
/// brand name ("Axis Bank") and not a sender ID ("AX-AXISBK-S").
const Set<String> kSmsAppPackages = {
  'com.google.android.apps.messaging', // Google Messages
  'com.samsung.android.messaging', // Samsung Messages
  'com.android.mms', // AOSP / many phones
  'com.oneplus.mms', // OnePlus
  'com.coloros.mms', // Oppo / Realme
  'com.vivo.mms', // Vivo
  'com.miui.mms', // Xiaomi
  'com.microsoft.android.smsorganizer',
  'com.truecaller',
  'com.ping.sms', // Ping
};

/// Called with a notification's title (the SMS sender), content (the SMS text) and the app that posted
/// it, when no scanner template matched. Opens the Add Transaction page prefilled with the amount,
/// direction, title and a suggested category. Nothing is saved until you press save, same as template
/// notifications.
///
/// Returns a short sentence saying what it did and why, which the Auto Transactions page shows under
/// each captured notification.
Future<String> queueTransactionFromSmartParse(String? sender, String? body,
    {String? packageName}) async {
  if (appStateSettings["notificationSmartParse"] != true) {
    return 'skipped: the Smart bank SMS parsing switch is off';
  }
  if (sender == null || sender.trim().isEmpty || sender == 'null') {
    return 'skipped: the notification has no title (sender)';
  }
  if (body == null || body.trim().isEmpty || body == 'null') {
    return 'skipped: the notification has no text';
  }

  final ParsedSmsTransaction? parsed = parseSmsTransaction(sender, body);
  if (parsed == null) {
    return 'skipped: not a completed payment (an OTP, reminder, request, promotion or chat)';
  }
  // The matching bank debit is its own SMS, adding this one too would count the bill twice.
  if (parsed.cardPayment) {
    return 'skipped: a credit card bill acknowledgement (the bank debit is a separate SMS)';
  }
  if (parsed.amount <= 0) return 'skipped: no amount found';

  // Only real SMS: a sender ID, a known messages app, or an SMS that names an account / card.
  final bool fromSmsApp = packageName != null && kSmsAppPackages.contains(packageName);
  final bool senderIdLike = looksLikeSenderId(sender);
  final bool namesAnAccount = parsed.instrumentKey.split(':').last.isNotEmpty;
  if (!fromSmsApp && !senderIdLike && !namesAnAccount) {
    return 'skipped: "$sender" from $packageName does not look like an SMS from a bank';
  }

  final String dedupeKey = '$sender|$body';
  if (_handledSmsKeys.contains(dedupeKey)) {
    return 'skipped: this notification was already handled';
  }
  _handledSmsKeys.insert(0, dedupeKey);
  if (_handledSmsKeys.length > 50) _handledSmsKeys.removeLast();

  // 1. A category you chose for this title before (Paddhu's associated titles) beats the rules.
  //    Only when the SMS named a merchant: generic titles like "Payment" would otherwise carry one
  //    category over to every message that has no merchant.
  TransactionCategory? category;
  if (parsed.merchant.isNotEmpty) {
    category = (await database.getSimilarAssociatedTitles(
            title: parsed.title, limit: 1))
        .firstOrNull
        ?.category;
  }

  // 2. Otherwise the rule-based suggestion, when it maps to one of the default categories.
  if (category == null && parsed.categoryPk != null) {
    category = await database.getCategoryInstanceOrNull(parsed.categoryPk!);
  }

  // A remembered category of the wrong direction (e.g. an income category on a payment) is dropped.
  if (category != null && category.income == parsed.isExpense) {
    category = null;
  }

  // Your own name for the account when it is known, otherwise "SBI ••6919" style.
  final KnownAccount? known = knownAccountFor(parsed.instrumentKey);
  final String? account = known != null
      ? (known.closed ? '${known.name} (closed)' : known.name)
      : parsed.instrumentName;

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
  return 'opened the Add Transaction page (${parsed.isExpense ? 'debit' : 'credit'} of ${parsed.amount})';
}
