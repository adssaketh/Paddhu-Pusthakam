// Pure rules about the placeholder accounts that hold other members' transactions.
// No imports on purpose, so tests can run this file with plain `dart run`.

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
