import 'dart:convert';
import 'dart:io';

import 'package:reseebo_app/core/services/receipt_parser.dart';
import '../test/support/receipt_benchmark.dart';

/// Run from the app root. Stdout is JSON; images and captured OCR are untouched.
void main() {
  final parser = ReceiptParser();
  Map<String, dynamic> read(File file) =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final synthetic =
      Directory('test/fixtures/receipts')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final cases = <Map<String, dynamic>>[];
  for (final file in synthetic) {
    final fixture = read(file);
    final draft = parser.parse(
      imagePath: '/synthetic.jpg',
      textLines: benchmarkOcrLines(fixture),
    );
    cases.add({
      'id': file.uri.pathSegments.last,
      'kind': 'synthetic-parser',
      'layout': fixture['layoutFamily'] ?? fixture['name'],
      ...scoreReceipt(draft, fixture['expected'] as Map<String, dynamic>),
    });
  }
  final truths =
      Directory('test/fixtures/grocery_benchmark')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('_truth.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in truths) {
    final truth = read(file);
    final capturesDirectory =
        truth['captureDirectory'] as String? ?? 'test/fixtures/public_receipts';
    for (final capture in truth['captures'] as List) {
      final fixture = read(File('$capturesDirectory/$capture.json'));
      final draft = parser.parse(
        imagePath: '/$capture.jpg',
        textLines: benchmarkOcrLines(fixture),
      );
      cases.add({
        'id': capture,
        'kind': 'captured-OCR-against-photo',
        'verification': truth['verification'],
        ...scoreReceipt(draft, truth['expected'] as Map<String, dynamic>),
      });
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'scope':
          'Parser replay; no new native OCR or device verification. '
          'Synthetic cases and photo truth are reported separately. '
          'Null synthetic expectations require abstention. '
          'Extra/unmatched rows include alignment failures; inspect failures.',
      'cases': cases,
    }),
  );
}
