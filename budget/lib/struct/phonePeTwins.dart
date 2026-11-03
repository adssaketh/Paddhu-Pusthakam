// The same payment can reach Paddhu Pusthakam twice: from the bank's SMS and from PhonePe (screenshot or
// statement). To avoid two transactions, the second one to arrive is matched with the first by direction,
// amount and day, and only adds its details to the first one's note:
//   - a PhonePe row finds a transaction that came from a bank SMS (claimExistingForPhonePe),
//   - a bank SMS row finds a transaction that came from PhonePe (claimPhonePeTwinForSms).
// A transaction that was already matched once is not matched again, so two payments of the same amount on one
// day stay two transactions.

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/phonePeParser.dart';
import 'package:budget/struct/pingImport.dart';
import 'package:drift/drift.dart' hide Column;

/// A real Ping SMS id in a note (not a PhonePe one, those start with "pp-").
final RegExp _smsMarker = RegExp(r'Ping SMS #(?!pp-)');

Future<List<Transaction>> _sameDayAndAmount(PingImportRow row) async {
  final DateTime start = DateTime(row.date.year, row.date.month, row.date.day);
  final DateTime end = start.add(const Duration(days: 1));
  final List<Transaction> found = await (database.select(database.transactions)
        ..where((t) =>
            t.dateCreated.isBiggerOrEqualValue(start) &
            t.dateCreated.isSmallerThanValue(end) &
            t.income.equals(!row.isExpense)))
      .get();
  return found.where((t) => (t.amount.abs() - row.amount.abs()).abs() < 0.005).toList();
}

/// A PhonePe [row] whose payment is already in Paddhu from the bank SMS: adds the PhonePe details and markers
/// to that transaction and returns true (nothing new is saved).
Future<bool> claimExistingForPhonePe(PingImportRow row) async {
  if (!row.smsId.startsWith('pp-')) return false;
  for (final Transaction t in await _sameDayAndAmount(row)) {
    if (!_smsMarker.hasMatch(t.note) || t.note.contains('Ping SMS #pp-')) continue;
    await database.createOrUpdateTransaction(
        t.copyWith(note: '${t.note}\n${row.extraNote}\nPing SMS #${row.smsId} Ping SMS key ${row.contentKey}'));
    return true;
  }
  return false;
}

/// A bank SMS [row] whose payment is already in Paddhu from PhonePe: adds the SMS markers to that transaction
/// and returns true (nothing new is saved).
Future<bool> claimPhonePeTwinForSms(PingImportRow row) async {
  if (row.smsId.startsWith('pp-')) return false;
  for (final Transaction t in await _sameDayAndAmount(row)) {
    if (!t.note.contains('Ping SMS #pp-') || _smsMarker.hasMatch(t.note)) continue;
    await database.createOrUpdateTransaction(
        t.copyWith(note: '${t.note}\nPing SMS #${row.smsId} Ping SMS key ${row.contentKey}'));
    return true;
  }
  return false;
}
