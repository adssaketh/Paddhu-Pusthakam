import '../lib/struct/settingsMerge.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

void main() {
  // two devices each add a loan: both are kept
  final a = <String, dynamic>{'loanTerms': {'L1': stampItem({'principal': 100}, 10)}};
  final b = <String, dynamic>{'loanTerms': {'L2': stampItem({'principal': 200}, 20)}};
  var r = mergeSettings(a, b);
  check((r.settings['loanTerms'] as Map).length == 2 && r.changedKeys.contains('loanTerms'), 'loans from both devices are kept');

  // the newer edit of the same loan wins, either way round
  final old = <String, dynamic>{'loanTerms': {'L1': stampItem({'principal': 100}, 10)}};
  final newer = <String, dynamic>{'loanTerms': {'L1': stampItem({'principal': 150}, 30)}};
  check(((mergeSettings(old, newer).settings['loanTerms'] as Map)['L1'] as Map)['principal'] == 150, 'newer loan edit wins');
  check(((mergeSettings(newer, old).settings['loanTerms'] as Map)['L1'] as Map)['principal'] == 150, 'older edit does not overwrite');

  // a deletion reaches the other device
  final deleted = <String, dynamic>{'loanTerms': {'L1': deletedMarker(40)}};
  final after = mergeSettings(newer, deleted).settings['loanTerms'] as Map;
  check(isDeletedItem(after['L1']), 'deleted loan stays deleted');
  // ...and an older copy cannot bring it back
  check(isDeletedItem((mergeSettings(deleted, newer).settings['loanTerms'] as Map)['L1']), 'old copy does not resurrect it');

  // fixed deposits (list with ids)
  final f1 = <String, dynamic>{'fixedDeposits': [stampItem({'id': 'fd-1', 'principal': 1}, 10)]};
  final f2 = <String, dynamic>{'fixedDeposits': [stampItem({'id': 'fd-2', 'principal': 2}, 20), stampItem({'id': 'fd-1', 'principal': 5}, 30)]};
  final fm = mergeSettings(f1, f2).settings['fixedDeposits'] as List;
  check(fm.length == 2 && (fm[0] as Map)['principal'] == 5, 'deposits merged by id, newer wins');
  check(mergeSettings(f1, <String, dynamic>{'fixedDeposits': null}).changedKeys.isEmpty, 'nothing to merge');

  // legacy items without a time (saved before this update) still reach a device that has none
  final legacy = <String, dynamic>{'fixedDeposits': [{'id': 'fd-0', 'principal': 9}]};
  check((mergeSettings(<String, dynamic>{}, legacy).settings['fixedDeposits'] as List).length == 1, 'legacy deposit synced');

  // ordinary settings: newest change wins, unchanged defaults never overwrite
  final l = <String, dynamic>{'theme': 'dark', 'font': 'A', kSettingsModifiedKey: {'theme': 100}};
  final m = <String, dynamic>{'theme': 'light', 'font': 'B', kSettingsModifiedKey: {'theme': 200}};
  r = mergeSettings(l, m);
  check(r.settings['theme'] == 'light' && r.settings['font'] == 'A' && r.changedKeys.length == 1, 'newer setting wins, default without a time does not');
  r = mergeSettings(m, l);
  check(r.settings['theme'] == 'light' && r.changedKeys.isEmpty, 'older setting ignored');

  // this device's own things are never taken
  r = mergeSettings(<String, dynamic>{'hasSignedIn': true, 'selectedWalletPk': '1'},
      <String, dynamic>{'hasSignedIn': false, 'selectedWalletPk': '9', 'locale': 'fr', kSettingsModifiedKey: {'hasSignedIn': 999, 'selectedWalletPk': 999, 'locale': 999}});
  check(r.settings['hasSignedIn'] == true && r.settings['selectedWalletPk'] == '1' && !r.settings.containsKey('locale'), 'device settings are not synced');
}
