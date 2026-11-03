import 'dart:io';

import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/autoSmsPolicy.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/phonePeTwins.dart';
import 'package:budget/struct/pingImport.dart';
import 'package:budget/struct/pingInbox.dart';
import 'package:budget/struct/pingSave.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// Review list for the bank SMS you sent from Ping (Ping > Settings > Send to Paddhu Pusthakam).
/// Nothing is saved until you press Save: tick what you want, change a row with the edit button.
///
/// Opened by the share sheet (the shared file is already in the app's cache), or with
/// [pickFile] = true to choose a Ping export file yourself, or with [reviewQueue] = true to look at the
/// messages Ping sent by itself that Paddhu Pusthakam was not sure about (see pingInbox.dart).
class ImportFromPingPage extends StatefulWidget {
  const ImportFromPingPage(
      {this.pickFile = false,
      this.autoOpenSingle = false,
      this.reviewQueue = false,
      this.preloaded,
      super.key});

  final bool pickFile;

  /// Payments already read from somewhere else (PhonePe screenshot / statement): shown instead of a Ping file.
  final PingImport? preloaded;

  /// Show the messages waiting in the review list instead of a shared file.
  final bool reviewQueue;

  /// Ping's "Add to Paddhu" button sends one SMS: open the Add Transaction page for it straight away.
  final bool autoOpenSingle;

  @override
  State<ImportFromPingPage> createState() => _ImportFromPingPageState();
}

class _ImportFromPingPageState extends State<ImportFromPingPage> {
  bool loading = true;
  bool saving = false;
  String? error;
  PingImport? data;

  /// SMS ids that already exist in Paddhu (from the note marker).
  Set<String> savedIds = {};

  /// Day + text keys of the SMS already in Paddhu, which also catches the same SMS sent another way.
  Set<String> savedKeys = {};

  bool _isSaved(PingImportRow r) =>
      savedIds.contains(r.smsId) || savedKeys.contains(r.contentKey);

  /// SMS ids ticked for saving.
  Set<String> ticked = {};
  int progress = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _readFileText() async {
    if (widget.reviewQueue) return await readReviewQueueAsExport();
    String? path;
    if (widget.pickFile) {
      final FilePickerResult? result = await FilePicker.platform.pickFiles();
      path = result?.files.single.path;
      if (path == null) return null;
    } else {
      final Directory dir = await getTemporaryDirectory();
      path = '${dir.path}/$kPingImportFileName';
    }
    final File file = File(path);
    if (!await file.exists()) {
      throw Exception('The shared file was not found. Send it from Ping again.');
    }
    return await file.readAsString();
  }

  /// [ids, keys] found in the notes of transactions that came from Ping.
  Future<List<Set<String>>> _existingPingMarkers() => existingPingMarkers();

  Future<void> _load() async {
    try {
      final PingImport parsed;
      if (widget.preloaded != null) {
        parsed = widget.preloaded!;
        // a payment that is already in Paddhu from the bank SMS: add the PhonePe details to it, no second copy
        List<Set<String>> before = await _existingPingMarkers();
        for (final PingImportRow r in parsed.rows) {
          if (before[0].contains(r.smsId) || before[1].contains(r.contentKey)) continue;
          await claimExistingForPhonePe(r);
        }
      } else {
        final String? text = await _readFileText();
        if (text == null) {
          if (mounted) setState(() => loading = false);
          return;
        }
        parsed = parsePingExport(text);
      }
      final List<Set<String>> existing = await _existingPingMarkers();
      savedIds = existing[0];
      savedKeys = existing[1];
      if (widget.reviewQueue) {
        // Saved some other way since (for example with the Add to Paddhu button): no longer waiting.
        final List<String> done =
            parsed.rows.where(_isSaved).map((r) => r.smsId).toList();
        if (done.isNotEmpty) await removeFromReviewQueue(done);
      }
      final Set<String> toTick = {
        for (final r in parsed.rows)
          if (!_isSaved(r) && r.tickByDefault) r.smsId,
      };
      if (!mounted) return;
      setState(() {
        data = widget.reviewQueue
            ? PingImport(
                rows: parsed.rows.where((r) => !_isSaved(r)).toList(),
                skipped: parsed.skipped,
                from: parsed.from,
                to: parsed.to)
            : parsed;
        ticked = toTick;
        loading = false;
      });
      // One SMS from the "Add to Paddhu" button: go straight to the Add Transaction page for it.
      final List<PingImportRow> open =
          parsed.rows.where((r) => !_isSaved(r)).toList();
      if (widget.autoOpenSingle && open.length == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _editRow(open.first);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e is FormatException ? e.message : e.toString();
        loading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------------------------------

  Future<void> _save() async {
    final PingImport? d = data;
    if (d == null || saving) return;
    final List<PingImportRow> rows = d.rows
        .where((r) => ticked.contains(r.smsId) && !_isSaved(r))
        .toList();
    if (rows.isEmpty) return;

    setState(() {
      saving = true;
      progress = 0;
    });
    try {
      final PingSaver saver = PingSaver();
      if (!await saver.init()) {
        throw Exception('Create a wallet in Paddhu Pusthakam first.');
      }
      int saved = 0;
      final List<String> savedNow = [];

      try {
        for (final PingImportRow row in rows) {
          // the same payment may already be in Paddhu from PhonePe: no second copy
          if (await claimPhonePeTwinForSms(row)) {
            savedNow.add(row.smsId);
            savedIds.add(row.smsId);
            savedKeys.add(row.contentKey);
            ticked.remove(row.smsId);
            continue;
          }
          await saver.save(row);
          saved++;
          savedNow.add(row.smsId);
          savedIds.add(row.smsId);
          savedKeys.add(row.contentKey);
          ticked.remove(row.smsId);
          progress = saved;
          if (saved % 25 == 0 && mounted) setState(() {});
        }
      } finally {
        // whatever was saved no longer needs reviewing, even if a later row failed
        if (widget.reviewQueue && savedNow.isNotEmpty) {
          await removeFromReviewQueue(savedNow);
        }
      }

      if (!mounted) return;
      setState(() => saving = false);
      openSnackbar(SnackbarMessage(
        title: "Saved $saved transactions",
        description: widget.preloaded != null ? "Imported from PhonePe" : "Imported from Ping",
        icon: appStateSettings["outlinedIcons"]
            ? Icons.check_circle_outline
            : Icons.check_circle_rounded,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      openSnackbar(SnackbarMessage(
        title: "Could not save everything",
        description: e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.warning_outlined
            : Icons.warning_rounded,
      ));
    }
  }

  /// Opens the normal Add Transaction page for one row, so you can change anything before saving.
  Future<void> _editRow(PingImportRow row) async {
    TransactionCategory? category;
    if (row.categoryPk != null) {
      category = await database.getCategoryInstanceOrNull(row.categoryPk!);
      if (category != null && category.income == row.isExpense) category = null;
    }
    TransactionWallet? wallet;
    for (final w in await database.getAllWallets()) {
      if (w.name.trim().toLowerCase() == row.walletName.trim().toLowerCase()) {
        wallet = w;
        break;
      }
    }
    if (!mounted) return;
    await pushRoute(
      context,
      AddTransactionPage(
        selectedIncome: !row.isExpense,
        useCategorySelectedIncome: false,
        routesToPopAfterDelete: RoutesToPopAfterDelete.None,
        selectedAmount: row.amount,
        selectedTitle: row.title,
        selectedCategory: category,
        selectedNotes: row.note,
        selectedWallet: wallet,
        selectedDate: row.date,
        startInitialAddTransactionSequence: false,
      ),
    );
    // If it was saved there, its note now carries the marker: show it as already in Paddhu.
    final List<Set<String>> existing = await _existingPingMarkers();
    if (!mounted) return;
    setState(() {
      savedIds = existing[0];
      savedKeys = existing[1];
      ticked.removeWhere((id) => savedIds.contains(id));
    });
    if (widget.reviewQueue && _isSaved(row)) {
      await removeFromReviewQueue([row.smsId]);
    }
    // The single SMS from the "Add to Paddhu" button is done once it is saved: leave this screen.
    if (widget.autoOpenSingle && _isSaved(row) && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Review list only: forget the messages that are not ticked (not saved, not wanted), so they stop coming back.
  Future<void> _dismissUnticked() async {
    final PingImport? d = data;
    if (d == null || saving) return;
    final List<PingImportRow> drop =
        d.rows.where((r) => !_isSaved(r) && !ticked.contains(r.smsId)).toList();
    if (drop.isEmpty) return;
    await removeFromReviewQueue(drop.map((r) => r.smsId));
    if (!mounted) return;
    final Set<String> dropped = drop.map((r) => r.smsId).toSet();
    setState(() {
      data = PingImport(
        rows: d.rows.where((r) => !dropped.contains(r.smsId)).toList(),
        skipped: d.skipped,
        from: d.from,
        to: d.to,
      );
    });
    openSnackbar(SnackbarMessage(
      title: "Removed ${drop.length} from the review list",
      icon: appStateSettings["outlinedIcons"]
          ? Icons.delete_outline
          : Icons.delete_rounded,
    ));
  }

  // ---------------------------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------------------------

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  Widget _buildRow(PingImportRow row) {
    final bool already = _isSaved(row);
    final bool isTicked = ticked.contains(row.smsId);
    final Color amountColor = row.isExpense
        ? Theme.of(context).colorScheme.error
        : Colors.green.shade600;
    final String money = convertToMoney(
        Provider.of<AllWallets>(context, listen: false), row.amount);
    final String detail = already
        ? 'Already in Paddhu Pusthakam'
        : widget.reviewQueue
            ? 'Not added automatically: ${decideAutoSave(row).reason}'
            : '${row.categoryLabel.isEmpty ? 'No category suggested' : row.categoryLabel}  →  ${row.walletName}';

    void toggle() {
      if (already || saving) return;
      setState(() {
        if (isTicked) {
          ticked.remove(row.smsId);
        } else {
          ticked.add(row.smsId);
        }
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggle,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: already ? true : isTicked,
              onChanged: already || saving ? null : (_) => toggle(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFont(
                    text: row.title,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    maxLines: 1,
                  ),
                  TextFont(
                    text:
                        '${_formatDate(row.date)}  ·  ${row.accountName ?? row.walletName}${row.closed ? ' (closed)' : ''}',
                    fontSize: 12,
                    maxLines: 1,
                  ),
                  TextFont(
                      text: detail,
                      fontSize: 12,
                      maxLines: widget.reviewQueue ? 3 : 1),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: TextFont(
                text: '${row.isExpense ? '-' : '+'}$money',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                textColor: amountColor,
                maxLines: 1,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: already || saving ? null : () => _editRow(row),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHeader(PingImport d) {
    final int newCount = d.rows.where((r) => !_isSaved(r)).length;
    final int alreadyCount = d.rows.length - newCount;
    final int tickedCount = d.rows
        .where((r) => ticked.contains(r.smsId) && !_isSaved(r))
        .length;

    // how many ticked rows go into each wallet
    final Map<String, int> perWallet = {};
    for (final r in d.rows) {
      if (ticked.contains(r.smsId) && !_isSaved(r)) {
        perWallet[r.walletName] = (perWallet[r.walletName] ?? 0) + 1;
      }
    }
    final List<String> walletLines = perWallet.entries
        .map((e) => '${e.key}: ${e.value}')
        .toList()
      ..sort();

    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 6),
        child: TextFont(
          text: widget.reviewQueue
              ? '${d.rows.length} bank messages from Ping were not added automatically because Paddhu Pusthakam was not sure about them '
                  '(a transfer to a person, an account that is not in your list...). '
                  '$tickedCount ticked. Save the ones that are fine, edit the others with the pencil, or remove what you do not need.'
              : '${d.rows.length} transactions found${d.from != null && d.to != null ? ' (${_formatDate(d.from!).substring(0, 10)} to ${_formatDate(d.to!).substring(0, 10)})' : ''}. '
                  '$alreadyCount already in Paddhu Pusthakam, $newCount new, $tickedCount ticked. '
                  '${d.skipped} messages skipped (not a payment, or a card bill acknowledgement).',
          fontSize: 14,
          maxLines: 10,
        ),
      ),
      if (walletLines.isNotEmpty)
        Padding(
          padding:
              const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 10),
          child: TextFont(
            text: 'Wallets: ${walletLines.join('  ·  ')}',
            fontSize: 12,
            maxLines: 12,
          ),
        ),
      Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 4),
        child: Row(
          children: [
            Flexible(
              child: Button(
                label: 'Tick all new',
                expandedLayout: true,
                disabled: saving,
                onTap: () => setState(() {
                  ticked = {
                    for (final r in d.rows)
                      if (!_isSaved(r)) r.smsId,
                  };
                }),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Button(
                label: 'Untick all',
                expandedLayout: true,
                disabled: saving,
                onTap: () => setState(() => ticked = {}),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 8),
        child: Button(
          label: saving
              ? 'Saving $progress of $tickedCount...'
              : 'Save $tickedCount transactions',
          expandedLayout: true,
          disabled: saving || tickedCount == 0,
          onTap: _save,
        ),
      ),
      if (widget.reviewQueue)
        Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 4),
          child: Button(
            label: 'Remove unticked from this list',
            expandedLayout: true,
            disabled: saving,
            onTap: _dismissUnticked,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final PingImport? d = data;
    final List<Widget> widgets = [];

    if (loading) {
      widgets.add(const Padding(
        padding: EdgeInsetsDirectional.all(40),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (error != null) {
      widgets.add(Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: TextFont(text: error!, fontSize: 15, maxLines: 10),
      ));
    } else if (d == null) {
      widgets.add(Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: TextFont(
            text: widget.reviewQueue
                ? 'Nothing to review. Messages Ping sends that Paddhu Pusthakam is not sure about will show up here.'
                : 'No file was chosen.',
            fontSize: 15,
            maxLines: 4),
      ));
    } else if (d.rows.isEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: TextFont(
          text: widget.reviewQueue
              ? 'Nothing left to review.'
              : 'No importable transactions in this file (${d.skipped} messages skipped).',
          fontSize: 15,
          maxLines: 5,
        ),
      ));
    } else {
      widgets.addAll(_buildHeader(d));
      for (final PingImportRow row in d.rows) {
        widgets.add(_buildRow(row));
      }
    }

    return PageFramework(
      dragDownToDismiss: true,
      title: widget.reviewQueue
          ? "Review Ping messages"
          : widget.preloaded != null
              ? "Import from PhonePe"
              : "Import from Ping",
      listWidgets: widgets,
    );
  }
}
