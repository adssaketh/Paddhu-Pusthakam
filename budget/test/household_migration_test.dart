// Household schema migration (47 and 48), checked against the saved drift schemas and
// the migration code. Needs no database: it reads drift_schemas/ and tables.dart.
// Run from the budget folder with: dart run test/household_migration_test.dart

import 'dart:convert';
import 'dart:io';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

Map<String, dynamic>? column(int version, String table, String name) {
  final Map<String, dynamic> schema = jsonDecode(
          File('drift_schemas/drift_schema_v$version.json').readAsStringSync())
      as Map<String, dynamic>;
  for (final dynamic entity in schema['entities'] as List) {
    final Map<String, dynamic> data =
        (entity as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    if (data['name'] != table) continue;
    for (final dynamic c in data['columns'] as List) {
      if ((c as Map<String, dynamic>)['name'] == name) return c;
    }
  }
  return null;
}

void main() {
  // ---- schema 46: before the household columns
  check(column(46, 'wallets', 'owner_uid') == null, 'v46 has no wallets.owner_uid');
  check(column(46, 'transactions', 'owner_uid') == null, 'v46 has no transactions.owner_uid');
  check(column(46, 'transactions', 'is_private') == null, 'v46 has no transactions.is_private');

  // ---- schema 47: owner and private flag
  final walletOwner = column(47, 'wallets', 'owner_uid');
  final txOwner = column(47, 'transactions', 'owner_uid');
  final isPrivate = column(47, 'transactions', 'is_private');
  check(walletOwner != null && walletOwner['nullable'] == true, 'v47 wallets.owner_uid exists and may be empty (old rows stay unowned)');
  check(txOwner != null && txOwner['nullable'] == true, 'v47 transactions.owner_uid exists and may be empty');
  check(isPrivate != null && isPrivate['nullable'] == false && isPrivate['default_dart'] == 'const Constant(false)', 'v47 transactions.is_private is a flag that defaults to false');
  check(column(47, 'transactions', 'household_synced_at') == null, 'v47 has no household_synced_at yet');

  // ---- schema 48: what was last uploaded
  final synced = column(48, 'transactions', 'household_synced_at');
  check(synced != null && synced['nullable'] == true && synced['moor_type'] == 'dateTime', 'v48 transactions.household_synced_at exists and may be empty');
  check(column(48, 'wallets', 'owner_uid') != null && column(48, 'transactions', 'owner_uid') != null && column(48, 'transactions', 'is_private') != null, 'v48 keeps the v47 columns');

  // ---- the migration code adds exactly these columns
  final String tables = File('lib/database/tables.dart').readAsStringSync();
  check(tables.contains('int schemaVersionGlobal = 48;'), 'current schema version is 48');
  final int from47 = tables.indexOf('from46To47:');
  final int from48 = tables.indexOf('from47To48:');
  check(from47 >= 0 && from48 > from47, 'both migration steps exist');
  final String step47 = tables.substring(from47, from48);
  final String step48 = tables.substring(from48);
  check(step47.contains('schema.wallets.ownerUid') && step47.contains('schema.transactions.ownerUid') && step47.contains('schema.transactions.isPrivate'), 'step 46 to 47 adds wallets.ownerUid, transactions.ownerUid and isPrivate');
  check(step48.contains('schema.transactions.householdSyncedAt'), 'step 47 to 48 adds transactions.householdSyncedAt');

  // ---- a saved schema file exists for every version up to the current one
  for (final int v in [46, 47, 48]) {
    check(File('drift_schemas/drift_schema_v$v.json').existsSync(), 'drift_schema_v$v.json is saved');
  }
  check(File('lib/database/schema_versions.dart').readAsStringSync().contains('Schema48'), 'schema_versions.dart knows version 48');

  print('household migration: all checks passed');
}
