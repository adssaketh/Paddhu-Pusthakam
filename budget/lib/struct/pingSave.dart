// Puts rows from Ping into Paddhu Pusthakam's database. Used by the review screen (importFromPingPage.dart)
// and by the automatic inbox (pingInbox.dart), so both save a row in exactly the same way: same wallet
// naming, same "Uncategorized" fallback, same note with the duplicate markers.

import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/pingImport.dart';
import 'package:budget/struct/settings.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart' show Colors;

/// [ids, keys] found in the notes of transactions that came from Ping (see kPingNoteMarker and
/// kPingKeyMarker in pingImport.dart).
Future<List<Set<String>>> existingPingMarkers() async {
  final rows = await (database.select(database.transactions)
        ..where((t) => t.note.like('%$kPingNoteMarker%')))
      .get();
  final RegExp idRe = RegExp(r'Ping SMS #([\w-]+)');
  final RegExp keyRe = RegExp(r'Ping SMS key ([\w-]+)');
  final Set<String> ids = {};
  final Set<String> keys = {};
  for (final t in rows) {
    for (final m in idRe.allMatches(t.note)) {
      ids.add(m.group(1)!);
    }
    for (final m in keyRe.allMatches(t.note)) {
      keys.add(m.group(1)!);
    }
  }
  return [ids, keys];
}

/// The category you chose before for a transaction with this same title (Paddhu's "associated titles"),
/// or null. Only an exact title match counts (ignoring case), and only when the SMS named a merchant:
/// a generic title like "Payment" must not carry one category over to every message.
Future<TransactionCategory?> learnedCategoryFor(PingImportRow row) async {
  if (row.merchant.trim().isEmpty) return null;
  final String wanted = row.title.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  final found =
      await database.getSimilarAssociatedTitles(title: row.title, limit: 10);
  for (final a in found) {
    if (a.type != TitleType.TitleExists) continue;
    if (a.title.title.trim().toLowerCase() != wanted) continue;
    // an income category on a payment (or the reverse) is not a match
    if (a.category.income == row.isExpense) continue;
    return a.category;
  }
  return null;
}

/// Saves rows one at a time. Create it, then call [save] for each row. Wallets and the fallback
/// categories are created on first use and remembered, so a long list does not look them up again.
class PingSaver {
  late Map<String, String> _walletPkByName;
  late TransactionWallet _baseWallet;
  late int _nextWalletOrder;
  final Map<String, String> _fallbackCategoryCache = {};
  bool _ready = false;

  /// false when Paddhu Pusthakam has no wallet yet (not set up), in which case nothing can be saved.
  Future<bool> init() async {
    final List<TransactionWallet> wallets = await database.getAllWallets();
    if (wallets.isEmpty) return false;
    _walletPkByName = {
      for (final w in wallets) w.name.trim().toLowerCase(): w.walletPk,
    };
    _baseWallet = wallets.firstWhere(
      (w) => w.walletPk == appStateSettings["selectedWalletPk"],
      orElse: () => wallets.first,
    );
    _nextWalletOrder = wallets.length;
    _ready = true;
    return true;
  }

  /// Category for a row: the suggested default one when it exists and matches the direction,
  /// otherwise an "Uncategorized" category (created once) you can sort out later.
  Future<String> _categoryPkFor(PingImportRow row) async {
    final String? suggested = row.categoryPk;
    if (suggested != null) {
      final TransactionCategory? c =
          await database.getCategoryInstanceOrNull(suggested);
      if (c != null && c.income == !row.isExpense) return c.categoryPk;
    }
    final bool income = !row.isExpense;
    final String cacheKey = income ? 'income' : 'expense';
    final String? cached = _fallbackCategoryCache[cacheKey];
    if (cached != null) return cached;

    final String name = income ? 'Uncategorized income' : 'Uncategorized';
    Future<String?> find() async {
      final List<TransactionCategory> all =
          await database.getAllCategories(allCategories: true, limit: 1000);
      for (final c in all) {
        if (c.income == income &&
            c.name.trim().toLowerCase() == name.toLowerCase()) {
          return c.categoryPk;
        }
      }
      return null;
    }

    String? pk = await find();
    if (pk == null) {
      final int count =
          (await database.getAllCategories(allCategories: true, limit: 1000))
              .length;
      await database.createOrUpdateCategory(
        TransactionCategory(
          categoryPk: "-1",
          name: name,
          colour: toHexString(Colors.grey),
          iconName: income ? "coin.png" : "bills.png",
          dateCreated: DateTime.now(),
          dateTimeModified: null,
          order: count,
          income: income,
        ),
        insert: true,
      );
      pk = await find();
    }
    final String result = pk ?? "-1";
    _fallbackCategoryCache[cacheKey] = result;
    return result;
  }

  Future<String> _walletPkFor(String walletNameRaw) async {
    final String walletName = walletNameRaw.trim();
    String? walletPk = _walletPkByName[walletName.toLowerCase()];
    if (walletPk != null) return walletPk;
    await database.createOrUpdateWallet(
      TransactionWallet(
        walletPk: "-1",
        name: walletName,
        dateCreated: DateTime.now(),
        dateTimeModified: null,
        order: _nextWalletOrder++,
        currency: _baseWallet.currency,
        currencyFormat: _baseWallet.currencyFormat,
        decimals: _baseWallet.decimals,
      ),
      insert: true,
    );
    walletPk = (await database.getWalletInstanceGivenName(walletName)).walletPk;
    _walletPkByName[walletName.toLowerCase()] = walletPk;
    return walletPk;
  }

  /// Saves one row. [categoryPkOverride] (a category you chose before for this title) wins over the
  /// row's own keyword suggestion. Call [init] first.
  Future<void> save(PingImportRow row, {String? categoryPkOverride}) async {
    if (!_ready) throw StateError('PingSaver.init() was not called');
    final String walletPk = await _walletPkFor(row.walletName);
    final String categoryPk = categoryPkOverride ?? await _categoryPkFor(row);
    await database.createOrUpdateTransaction(
      Transaction(isPrivate: false, 
        transactionPk: "-1",
        name: row.title,
        amount: row.isExpense ? -row.amount.abs() : row.amount.abs(),
        note: row.note,
        categoryFk: categoryPk,
        walletFk: walletPk,
        dateCreated: row.date,
        dateTimeModified: null,
        income: !row.isExpense,
        paid: true,
        skipPaid: true,
      ),
      insert: true,
    );
  }
}
