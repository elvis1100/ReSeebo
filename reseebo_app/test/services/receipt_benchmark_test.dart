import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/core/models/models.dart';

import '../support/receipt_benchmark.dart';

void main() {
  test('column parsing is independent of supplier name and image scale', () {
    final source =
        jsonDecode(
              File(
                'test/fixtures/receipts/token_columns.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final supplier in ['UNKNOWN GROCERY', 'GROCERY B', 'MARKET C']) {
      for (final scale in [.5, 1.0, 2.5]) {
        final fixture = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
        (fixture['lines'] as List).first['text'] = supplier;
        void transform(Map<String, dynamic> cell) {
          for (final field in ['left', 'top', 'width', 'height']) {
            if (cell[field] is num) cell[field] = (cell[field] as num) * scale;
          }
          for (final token in cell['tokens'] as List? ?? []) {
            transform(token as Map<String, dynamic>);
          }
        }

        for (final row in fixture['lines'] as List) {
          transform(row as Map<String, dynamic>);
        }
        final draft = ReceiptParser().parse(
          imagePath: '/test.jpg',
          textLines: benchmarkOcrLines(fixture),
        );
        final result = scoreReceipt(
          draft,
          fixture['expected'] as Map<String, dynamic>,
        );
        expect(result['failures'], isEmpty, reason: '$supplier at $scale');
        expect(result['missedRows'], 0);
        expect(result['extraOrUnmatchedRows'], 0);
      }
    }
  });

  test(
    'scorer separates wrong autofill, abstention, and missing/extra rows',
    () {
      final draft = ReceiptDraft(imagePath: '/test.jpg')
        ..lines.addAll([
          ParsedLineItem(description: 'COFFEE', quantity: 3),
          ParsedLineItem(description: 'MILK', grossAmountCents: 100),
          ParsedLineItem(description: 'EXTRA'),
        ]);
      final result = scoreReceipt(draft, {
        'lines': [
          {'description': 'COFFEE', 'quantity': 2, 'amount': 200},
          {'description': 'MILK', 'quantity': null, 'amount': null},
          {'description': 'MISSING', 'quantity': 1, 'amount': 300},
        ],
      });
      expect(result['missedRows'], 1);
      expect(result['extraOrUnmatchedRows'], 1);
      final fields = result['fields'] as Map;
      expect(fields['quantity'], {
        'correct': 0,
        'wrong': 1,
        'unresolved': 0,
        'safeUnresolved': 1,
        'unaligned': 1,
      });
      expect(fields['amount'], {
        'correct': 0,
        'wrong': 1,
        'unresolved': 1,
        'safeUnresolved': 0,
        'unaligned': 1,
      });
    },
  );

  test('ambiguous anchors never select whichever price happens to agree', () {
    final draft = ReceiptDraft(imagePath: '/test.jpg')
      ..lines.addAll([
        ParsedLineItem(description: 'COFFEE A', quantity: 1),
        ParsedLineItem(description: 'COFFEE B', quantity: 2),
      ]);
    final result = scoreReceipt(draft, {
      'lines': [
        {'description': 'COFFEE', 'matchPattern': 'COFFEE', 'quantity': 2},
      ],
    });
    expect(result['matchedRows'], 0);
    expect(result['extraOrUnmatchedRows'], 2);
  });
  test('overlapping truth anchors reject both rows in either order', () {
    final draft = ReceiptDraft(imagePath: '/test.jpg')
      ..lines.add(ParsedLineItem(description: 'COFFEE A', quantity: 2));
    final truths = [
      {'description': 'COFFEE A', 'quantity': 2},
      {'description': 'COFFEE', 'matchPattern': 'COFFEE', 'quantity': 1},
    ];
    for (final rows in [truths, truths.reversed.toList()]) {
      final result = scoreReceipt(draft, {'lines': rows});
      expect(result['matchedRows'], 0);
      expect((result['alignmentFailures'] as List).length, 2);
      final quantity = (result['fields'] as Map)['quantity'] as Map;
      expect(quantity['unaligned'], 2);
      expect(quantity['unresolved'], 0);
    }
  });

  test('exact duplicate rows align in order without choosing by values', () {
    final draft = ReceiptDraft(imagePath: '/test.jpg')
      ..lines.addAll([
        ParsedLineItem(description: 'COFFEE', quantity: 2),
        ParsedLineItem(description: 'COFFEE', quantity: 1),
      ]);
    final result = scoreReceipt(draft, {
      'lines': [
        {'description': 'COFFEE', 'quantity': 1},
        {'description': 'COFFEE', 'quantity': 2},
      ],
    });
    expect(result['matchedRows'], 2);
    final quantity = (result['fields'] as Map)['quantity'] as Map;
    expect(quantity['wrong'], 2);
    expect(quantity['correct'], 0);
    expect(quantity['unaligned'], 0);
  });

  test(
    'duplicate multiplicity mismatch stays ambiguous, even for null truth',
    () {
      final draft = ReceiptDraft(imagePath: '/test.jpg')
        ..lines.add(ParsedLineItem(description: 'COFFEE', quantity: 1));
      final result = scoreReceipt(draft, {
        'lines': [
          {'description': 'COFFEE', 'quantity': 1},
          {'description': 'COFFEE', 'quantity': null},
        ],
      });
      expect(result['matchedRows'], 0);
      final quantity = (result['fields'] as Map)['quantity'] as Map;
      expect(quantity['unaligned'], 2);
      expect(quantity['safeUnresolved'], 0);
    },
  );
}
