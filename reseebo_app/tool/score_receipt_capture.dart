import 'dart:convert';
import 'dart:io';

import 'package:reseebo_app/core/services/receipt_parser.dart';
import '../test/support/receipt_benchmark.dart';

/// Scores an external OCR capture against independent photo truth. Without
/// truth, reports suggestions only; populated fields are not accuracy results.
void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/score_receipt_capture.dart capture.json [truth.json]',
    );
    exitCode = 64;
    return;
  }
  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final capture = read(args.first);
  final draft = ReceiptParser().parse(
    imagePath: '/external-capture.jpg',
    textLines: benchmarkOcrLines(capture),
  );
  final score = args.length == 2
      ? scoreReceipt(draft, read(args[1])['expected'] as Map<String, dynamic>)
      : null;
  if (score != null) {
    final failedRows = (score['failures'] as List)
        .cast<Map<String, dynamic>>()
        .where((failure) => failure['row'] != 'receipt')
        .map((failure) => failure['row'])
        .toSet();
    // Completeness applies only to declared truth fields; it does not prove
    // catalog identity, unit conversion, or discounted net costs unless scored.
    score['expectedRowsCorrectOnDeclaredFields'] =
        (score['expectedRows'] as int) - failedRows.length;
    score['receiptCorrectOnDeclaredFields'] =
        failedRows.isEmpty &&
        (score['failures'] as List).isEmpty &&
        score['extraOrUnmatchedRows'] == 0;
  }
  final report = <String, dynamic>{
    'scope': 'Parser replay of external OCR; no native device verification.',
    'capture': args.first,
    'provenance': capture['provenance'],
    'totalCents': draft.detectedTotalCents,
    'suggestions': [
      for (final line in draft.lines)
        {
          'description': line.description,
          'quantity': line.quantity,
          'unit': line.unit?.name,
          'amountCents': line.grossAmountCents,
          'warnings': line.warnings,
        },
    ],
    'score': ?score,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
