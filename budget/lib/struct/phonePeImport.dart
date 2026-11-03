// The phone-side work for PhonePe imports: read the text of a screenshot (on the phone, no internet), pull the
// text out of a statement PDF, read a CSV, and turn what was found into rows for the review screen. The
// actual understanding of the text is in phonePeParser.dart.

import 'dart:convert';
import 'dart:io';

import 'package:budget/struct/phonePeParser.dart';
import 'package:budget/struct/pingImport.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Thrown for a PDF that needs a password (or whose password was wrong).
class PdfPasswordNeeded implements Exception {
  const PdfPasswordNeeded();
}

Future<String> readTextFromImage(String path) async {
  final TextRecognizer recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final RecognizedText result = await recognizer.processImage(InputImage.fromFilePath(path));
    return result.text;
  } finally {
    await recognizer.close();
  }
}

/// One payment from a screenshot of a UPI app's payment-success page (PhonePe, Paytm, Google Pay, BHIM, CRED, MobiKwik, ...).
Future<PingImport> buildImportFromScreenshot(String imagePath) async {
  final String text = await readTextFromImage(imagePath);
  final PhonePeEntry? entry = parseUpiScreenshotText(text);
  if (entry == null) {
    throw const FormatException(
        'Could not read a payment from this picture. Open the payment in your UPI app so the success page, with the amount, date, name and details, is fully visible, and take the screenshot again.');
  }
  return phonePeEntriesToImport([entry]);
}

/// The text of a PDF, laid out in lines like the page.
String _pdfText(List<int> bytes, String? password, {required bool layout}) {
  PdfDocument? doc;
  try {
    doc = password == null || password.isEmpty
        ? PdfDocument(inputBytes: bytes)
        : PdfDocument(inputBytes: bytes, password: password);
    return PdfTextExtractor(doc).extractText(layoutText: layout);
  } catch (e) {
    final String m = e.toString().toLowerCase();
    if (m.contains('password') || m.contains('encrypt') || m.contains('decrypt')) {
      throw const PdfPasswordNeeded();
    }
    rethrow;
  } finally {
    doc?.dispose();
  }
}

/// All payments of a PhonePe statement file (.pdf or .csv).
Future<PingImport> buildImportFromStatement(String path, {String? pdfPassword}) async {
  final File file = File(path);
  if (!await file.exists()) throw const FormatException('The file was not found.');
  final String lower = path.toLowerCase();
  List<PhonePeEntry> entries;

  if (lower.endsWith('.pdf')) {
    final List<int> bytes = await file.readAsBytes();
    entries = parsePhonePeStatementText(_pdfText(bytes, pdfPassword, layout: true));
    if (entries.isEmpty) {
      entries = parsePhonePeStatementText(_pdfText(bytes, pdfPassword, layout: false));
    }
  } else {
    final String text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    entries = parsePhonePeCsv(text);
  }

  if (entries.isEmpty) {
    throw const FormatException(
        'No payments were found in this file. Check that it is a PhonePe transaction statement. If it is, send the file to the developer so the reader can be matched to it.');
  }
  return phonePeEntriesToImport(entries);
}
