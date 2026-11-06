// The phone-side work for PhonePe imports: read the text of a screenshot (on the phone, no internet), pull the
// text out of a statement PDF, read a CSV, and turn what was found into rows for the review screen. The
// actual understanding of the text is in phonePeParser.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// A copy of the picture with the colours inverted (light text on a dark screen becomes dark text on a
/// light one), which the text reader handles better. null when it could not be made.
Future<String?> _invertedCopy(String path) async {
  try {
    final ui.Codec codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
    final ui.Image image = (await codec.getNextFrame()).image;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawImage(
      image,
      ui.Offset.zero,
      ui.Paint()
        ..colorFilter = const ui.ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
    );
    final ui.Image inverted = await recorder.endRecording().toImage(image.width, image.height);
    final ByteData? data = await inverted.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final File out = File('${Directory.systemTemp.path}/phonepe-inverted.png');
    await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    return out.path;
  } catch (e) {
    return null;
  }
}

/// One payment from a screenshot of a UPI app's payment-success page (PhonePe, Paytm, Google Pay, BHIM, CRED, MobiKwik, ...).
Future<PingImport> buildImportFromScreenshot(String imagePath) async {
  final String text = await readTextFromImage(imagePath);
  PhonePeEntry? entry = parseUpiScreenshotText(text);
  if (entry == null || entry.amountUnconfirmed) {
    // The rupee sign is the hardest character to read: it can come out as a "7" or a "T", most of all on a
    // dark screen, and then the amount is wrong. A second reading of the inverted picture often gets it
    // right. A reading with a rupee sign in front of the amount is preferred; otherwise the first stays.
    final String? inverted = await _invertedCopy(imagePath);
    if (inverted != null) {
      try {
        final PhonePeEntry? second = parseUpiScreenshotText(await readTextFromImage(inverted));
        if (second != null && (entry == null || !second.amountUnconfirmed)) entry = second;
      } catch (e) {
        // keep the first reading
      } finally {
        try {
          await File(inverted).delete();
        } catch (e) {
          // a leftover cache file does no harm
        }
      }
    }
  }
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
