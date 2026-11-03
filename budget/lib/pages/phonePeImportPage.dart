// Starts a PhonePe import: reads a screenshot (shared to Paddhu Pusthakam, or chosen here) or a statement
// (PDF / CSV), then hands the payments to the review screen (ImportFromPingPage with [preloaded]).
//
// A single screenshot opens the Add Transaction page already filled in, so you confirm and save. A statement
// shows the list of payments to tick, with the ones already in Paddhu Pusthakam marked.

import 'dart:io';

import 'package:budget/pages/importFromPingPage.dart';
import 'package:budget/struct/phonePeImport.dart';
import 'package:budget/struct/pingImport.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum PhonePeSource {
  /// A screenshot shared from the gallery / PhonePe to Paddhu Pusthakam (copied by ShareReceiverActivity).
  sharedImage,

  /// A statement shared to Paddhu Pusthakam.
  sharedPdf,
  sharedCsv,

  /// Choose a screenshot here.
  pickImage,

  /// Choose a statement here.
  pickStatement,
}

/// Names used by ShareReceiverActivity.java for the file it copies into the cache.
const String kPhonePeSharedName = 'phonepe-share';

class PhonePeImportPage extends StatefulWidget {
  const PhonePeImportPage({required this.source, super.key});
  final PhonePeSource source;

  @override
  State<PhonePeImportPage> createState() => _PhonePeImportPageState();
}

class _PhonePeImportPageState extends State<PhonePeImportPage> {
  String? error;
  String status = 'Reading…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<String?> _path() async {
    switch (widget.source) {
      case PhonePeSource.sharedImage:
      case PhonePeSource.sharedPdf:
      case PhonePeSource.sharedCsv:
        final Directory dir = await getTemporaryDirectory();
        final String ext = widget.source == PhonePeSource.sharedPdf
            ? 'pdf'
            : widget.source == PhonePeSource.sharedCsv
                ? 'csv'
                : 'img';
        return '${dir.path}/$kPhonePeSharedName.$ext';
      case PhonePeSource.pickImage:
        final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image);
        return r?.files.single.path;
      case PhonePeSource.pickStatement:
        final FilePickerResult? r = await FilePicker.platform
            .pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'csv', 'txt']);
        return r?.files.single.path;
    }
  }

  Future<String?> _askPassword() async {
    final TextEditingController c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This PDF has a password'),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Open')),
        ],
      ),
    );
  }

  Future<void> _run() async {
    try {
      final String? path = await _path();
      if (path == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final bool isImage = widget.source == PhonePeSource.sharedImage ||
          widget.source == PhonePeSource.pickImage;
      PingImport imp;
      if (isImage) {
        if (mounted) setState(() => status = 'Reading the picture…');
        imp = await buildImportFromScreenshot(path);
      } else {
        if (mounted) setState(() => status = 'Reading the statement…');
        String? password;
        while (true) {
          try {
            imp = await buildImportFromStatement(path, pdfPassword: password);
            break;
          } on PdfPasswordNeeded {
            if (!mounted) return;
            password = await _askPassword();
            if (password == null) {
              if (mounted) Navigator.of(context).pop();
              return;
            }
          }
        }
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ImportFromPingPage(preloaded: imp, autoOpenSingle: isImage),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e is FormatException ? e.message : 'Could not read it: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PhonePe')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: error == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(status),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ]),
        ),
      ),
    );
  }
}
