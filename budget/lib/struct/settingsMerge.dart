// Merging the app's settings between devices. The sync already downloads the other device's whole backup
// (which contains its settings, see backupSettings()), so this only decides what to take from it.
//
//  - Every setting has a "last changed" time (kept under "settingsModified"). The newer value wins.
//  - Loans ("loanTerms") and fixed deposits ("fixedDeposits") are merged item by item, so two devices
//    that each added a loan or deposit both keep both. Each item has "_u" (when it was last changed) and a
//    deleted item stays behind as a small marker {"_d": true} so the deletion reaches the other device too.
//  - Settings that belong to one device (login, notifications, backup schedule, ...) are never synced.
//
// Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

const String kSettingsModifiedKey = 'settingsModified';

/// Settings that describe this device or this login, not your preferences.
const Set<String> kSettingsNotSynced = {
  kSettingsModifiedKey,
  'databaseJustImported', 'backupLimit', 'backupSync', 'syncEveryChange', 'devicesHaveBeenSynced',
  'numBackups', 'autoBackups', 'autoBackupsFrequency', 'lastBackup', 'hasSignedIn', 'lastSynced',
  'lastLoginVersion', 'numLogins', 'forceAutoLogin', 'enableGoogleLoginFlyIn', 'openedStoreRating',
  'dismissedStoreRating', 'submittedFeedback', 'canShowBackupReminderPopup',
  'canShowTransactionActionButtonTip', 'autoLoginDisabledOnWebTip', 'allSpendingPageTip',
  'notifications', 'notificationHour', 'notificationMinute', 'notificationsUpcomingTransactions',
  'notificationsReminderType', 'appOpenedHour', 'appOpenedMinute', 'notificationScanning',
  'notificationScanningDebug', 'notificationSmartParse', 'emailScanning', 'emailScanningPullToRefresh',
  'sendTransactionsToServerQueue', 'currentUserEmail', 'requireAuth', 'selectedWalletPk', 'locale',
  'logging', 'iOSEmulate', 'iOSAnimatedGoo', 'previewDemo', 'purchaseID', 'selectedSubscriptionType',
  'premiumPopupAddTransactionCount', 'premiumPopupAddTransactionLastShown', 'premiumPopupFreeSeen',
  'hasOnboarded', 'appAnimations', 'animationSpeed', 'batterySaver', 'materialYou', 'accentSystemColor',
  'expandedNavigationSidebar', 'cachedCurrencyExchange', 'sharedBudgets', 'fdReminderCount',
  'allSpendingLastPage', 'loansLastPage',
};

/// Settings whose value is a collection of items, merged item by item.
const Set<String> kSettingsCollections = {'loanTerms', 'fixedDeposits'};

bool isSyncedSettingKey(String key) => !kSettingsNotSynced.contains(key);

int _updatedAt(dynamic item) {
  if (item is Map && item['_u'] is num) return (item['_u'] as num).toInt();
  return 0;
}

/// An item that was deleted (only the marker is left).
bool isDeletedItem(dynamic item) => item is Map && item['_d'] == true;

/// A copy of [json] stamped with the time it was changed.
Map<String, dynamic> stampItem(Map<String, dynamic> json, [int? nowMs]) =>
    {...json, '_u': nowMs ?? DateTime.now().millisecondsSinceEpoch, '_d': false};

/// The marker that replaces a deleted item.
Map<String, dynamic> deletedMarker([int? nowMs]) =>
    {'_d': true, '_u': nowMs ?? DateTime.now().millisecondsSinceEpoch};

/// Merges two maps of items (key -> item): the newer item wins, items found on one side only are kept.
Map<String, dynamic> mergeItemMaps(Map local, Map remote) {
  final Map<String, dynamic> out = {for (final e in local.entries) '${e.key}': e.value};
  for (final MapEntry e in remote.entries) {
    final String k = '${e.key}';
    if (!out.containsKey(k) || _updatedAt(e.value) > _updatedAt(out[k])) out[k] = e.value;
  }
  return out;
}

/// Merges two lists of items that have an "id": the newer item wins, new ones are added at the end.
List<dynamic> mergeItemLists(List local, List remote) {
  final List<dynamic> out = [...local];
  for (final dynamic r in remote) {
    if (r is! Map || r['id'] == null) continue;
    final int i = out.indexWhere((l) => l is Map && '${l['id']}' == '${r['id']}');
    if (i < 0) {
      out.add(r);
    } else if (_updatedAt(r) > _updatedAt(out[i])) {
      out[i] = r;
    }
  }
  return out;
}

class SettingsMergeResult {
  SettingsMergeResult(this.settings, this.changedKeys);

  /// The settings after merging (a new map, [local] is not changed).
  final Map<String, dynamic> settings;

  /// Keys whose value came from the other device.
  final Set<String> changedKeys;
}

Map<String, int> _modifiedOf(Map<String, dynamic> settings) {
  final dynamic m = settings[kSettingsModifiedKey];
  if (m is! Map) return {};
  return {for (final e in m.entries) if (e.value is num) '${e.key}': (e.value as num).toInt()};
}

/// Takes what is newer from [remote] (the other device's settings) into [local].
SettingsMergeResult mergeSettings(Map<String, dynamic> local, Map<String, dynamic> remote) {
  final Map<String, dynamic> out = {...local};
  final Map<String, int> localTimes = _modifiedOf(local);
  final Map<String, int> remoteTimes = _modifiedOf(remote);
  final Set<String> changed = {};

  for (final MapEntry<String, dynamic> e in remote.entries) {
    final String key = e.key;
    if (!isSyncedSettingKey(key)) continue;
    final dynamic rv = e.value;
    if (kSettingsCollections.contains(key)) {
      final dynamic lv = local[key];
      dynamic merged;
      if (rv is Map && (lv is Map || lv == null)) {
        merged = mergeItemMaps((lv as Map?) ?? {}, rv);
      } else if (rv is List && (lv is List || lv == null)) {
        merged = mergeItemLists((lv as List?) ?? [], rv);
      } else {
        continue;
      }
      if (_sameJson(merged, lv)) continue;
      out[key] = merged;
      changed.add(key);
      localTimes[key] = DateTime.now().millisecondsSinceEpoch;
      continue;
    }
    final int rt = remoteTimes[key] ?? 0;
    final int lt = localTimes[key] ?? 0;
    if (rt > lt && !_sameJson(rv, local[key])) {
      out[key] = rv;
      localTimes[key] = rt;
      changed.add(key);
    }
  }
  out[kSettingsModifiedKey] = localTimes;
  return SettingsMergeResult(out, changed);
}

bool _sameJson(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final dynamic k in a.keys) {
      if (!b.containsKey(k) || !_sameJson(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
