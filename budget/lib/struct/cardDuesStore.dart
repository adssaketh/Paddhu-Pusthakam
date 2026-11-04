// Where the credit card dues are kept: in the app's settings under "cardDues", one entry per SMS (or per
// correction made by hand). Like loans and deposits they sync between devices item by item
// (settingsMerge.dart): each entry has "_u" and a removed one leaves a marker.

import 'package:budget/struct/cardDues.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/settingsMerge.dart';

const String _key = 'cardDues';

List<Map<String, dynamic>> _raw() {
  final dynamic stored = appStateSettings[_key];
  if (stored is! List) return [];
  return [
    for (final dynamic j in stored)
      if (j is Map) Map<String, dynamic>.from(j)
  ];
}

Future<void> _write(List<Map<String, dynamic>> items) => updateSettings(
      _key,
      items,
      updateGlobalState: false,
      pagesNeedingRefresh: [0],
      setStateAllPageFrameworks: true,
    );

List<CardDueEntry> loadCardDues() {
  final List<CardDueEntry> out = [];
  for (final Map<String, dynamic> j in _raw()) {
    if (isDeletedItem(j)) continue;
    final CardDueEntry? e = CardDueEntry.fromJson(j);
    if (e != null) out.add(e);
  }
  return out;
}

/// Adds the entries that are not there yet (an entry that was removed by hand stays removed).
/// Returns how many were added.
Future<int> recordCardDues(List<CardDueEntry> entries) async {
  if (entries.isEmpty) return 0;
  final List<Map<String, dynamic>> items = _raw();
  final Set<String> known = {for (final Map<String, dynamic> j in items) '${j['id']}'};
  int added = 0;
  for (final CardDueEntry e in entries) {
    if (!known.add(e.id)) continue;
    items.add(stampItem(e.toJson()));
    added++;
  }
  if (added > 0) await _write(items);
  return added;
}

Future<void> addCardDue(CardDueEntry e) async {
  final List<Map<String, dynamic>> items = _raw();
  items.removeWhere((j) => '${j['id']}' == e.id);
  items.add(stampItem(e.toJson()));
  await _write(items);
}

Future<void> deleteCardDue(String id) async {
  final List<Map<String, dynamic>> items = _raw();
  final int i = items.indexWhere((j) => '${j['id']}' == id);
  if (i < 0) return;
  items[i] = {'id': id, ...deletedMarker()};
  await _write(items);
}

/// Makes [card] show [target] as owed from now on.
Future<void> setCardOwed(String card, double target) async {
  final double current = owedByCard(loadCardDues().where((e) => e.card == card))[card] ?? 0;
  await addCardDue(correctionFor(card, current, target, DateTime.now()));
}
