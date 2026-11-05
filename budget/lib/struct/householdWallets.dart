// Household accounts: which accounts this person sees and can pick.
//
// Accounts are private to their owner. Another member's transactions are kept on this phone
// in one placeholder account per member (walletPk "hh_<uid>", see householdDownload.dart).
// Rules for the placeholder accounts:
//  - They never appear in anything the person picks from (new transaction, budgets, Ping import).
//  - They never become the selected account.
//  - Their balance and transaction total are only shown when the household owner switched
//    "Show account balances to members" on. Otherwise they are left out of account lists and
//    account totals completely.
//  - They cannot be edited or deleted from the account screens (they belong to the other member).
//
// The pure helpers at the top have no database or Flutter dependencies, so they can be
// checked with `dart run`.

import 'package:budget/struct/settings.dart';

const String kPlaceholderWalletPrefix = 'hh_';

/// The placeholder account that holds [uid]'s transactions on this phone.
String placeholderWalletPk(String uid) => '$kPlaceholderWalletPrefix$uid';

bool isPlaceholderWalletPk(String walletPk) =>
    walletPk.startsWith(kPlaceholderWalletPrefix);

/// True when an account must be left out of lists and totals: it is another member's
/// placeholder account and the owner has not switched balances on.
bool householdWalletIsHidden({
  required String walletPk,
  required bool balancesShown,
}) =>
    isPlaceholderWalletPk(walletPk) && !balancesShown;

// ---------------------------------------------------------------------------
// settings-backed helpers

const String kHouseholdShowBalancesKey = "householdShowBalances";

/// The owner's "show account balances to members" switch, as last seen on this phone.
bool get householdBalancesShown =>
    appStateSettings[kHouseholdShowBalancesKey] == true;

bool get _inHousehold =>
    (appStateSettings["householdId"] ?? "").toString() != "";

/// True when placeholder accounts have to be left out of account lists and totals.
/// Always false outside a household, so single-user mode is untouched.
bool get householdHidesOtherMembersWallets =>
    _inHousehold && !householdBalancesShown;

/// Remembers the owner's switch on this phone. [updateGlobalState] rebuilds the app so account
/// lists and totals pick the change up.
Future<void> saveHouseholdBalancesShown(bool show) async {
  if (householdBalancesShown == show) return;
  await updateSettings(kHouseholdShowBalancesKey, show,
      updateGlobalState: true);
}
