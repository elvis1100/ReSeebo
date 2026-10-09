import 'package:reseebo_app/core/models/models.dart';

List<OcrTextLine> benchmarkOcrLines(Map<String, dynamic> fixture) => [
  for (final row in fixture['lines'] as List)
    OcrTextLine(
      text: row['text'] as String,
      left: (row['left'] as num? ?? 0).toDouble(),
      top: (row['top'] as num? ?? 0).toDouble(),
      width: (row['width'] as num? ?? 0).toDouble(),
      height: (row['height'] as num? ?? 0).toDouble(),
      tokens: [
        for (final token in row['tokens'] as List? ?? [])
          OcrTextToken(
            text: token['text'] as String,
            left: (token['left'] as num? ?? 0).toDouble(),
            top: (token['top'] as num? ?? 0).toDouble(),
            width: (token['width'] as num? ?? 0).toDouble(),
            height: (token['height'] as num? ?? 0).toDouble(),
          ),
      ],
    ),
];

String _normalized(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Evaluation-only anchors associate rows without using prices/counts. Exact
/// repeated descriptions align by order only when multiplicities agree;
/// overlapping or ambiguous anchors remain unmatched. This never supplies
/// corrections to the app or treats a populated field as an accurate field.
Map<String, dynamic> scoreReceipt(
  ReceiptDraft draft,
  Map<String, dynamic> expected,
) {
  final fields = <String, Map<String, int>>{};
  final failures = <Map<String, dynamic>>[];
  final matched = <int>{};
  var detected = 0;
  final alignmentFailures = <Map<String, dynamic>>[];
  void score(
    String field,
    Object? truth,
    Object? actual,
    String row, {
    bool aligned = true,
  }) {
    final counts = fields.putIfAbsent(
      field,
      () => {
        'correct': 0,
        'wrong': 0,
        'unresolved': 0,
        'safeUnresolved': 0,
        'unaligned': 0,
      },
    );
    final category = !aligned
        ? 'unaligned'
        : truth == null
        ? (actual == null ? 'safeUnresolved' : 'wrong')
        : actual == null
        ? 'unresolved'
        : actual == truth
        ? 'correct'
        : 'wrong';
    counts[category] = counts[category]! + 1;
    if (category == 'wrong' ||
        category == 'unresolved' ||
        category == 'unaligned') {
      failures.add({
        'row': row,
        'category': category,
        'field': field,
        'expected': truth,
        'actual': actual,
      });
    }
  }

  final items = expected['lines'] as List;
  final candidatesByRow = <List<int>>[
    for (final raw in items)
      [
        for (var i = 0; i < draft.lines.length; i++)
          if ((raw as Map<String, dynamic>)['matchPattern'] == null
              ? _normalized(draft.lines[i].description) ==
                    _normalized(raw['description'] as String)
              : RegExp(
                  raw['matchPattern'] as String,
                  caseSensitive: false,
                ).hasMatch(draft.lines[i].description))
            i,
      ],
  ];
  final ownersByActual = <List<int>>[
    for (var i = 0; i < draft.lines.length; i++)
      [
        for (var j = 0; j < items.length; j++)
          if (candidatesByRow[j].contains(i)) j,
      ],
  ];
  for (var index = 0; index < items.length; index++) {
    final item = items[index] as Map<String, dynamic>;
    final description = item['description'] as String;
    final candidates = candidatesByRow[index];
    int? actualIndex;
    if (candidates.length == 1 &&
        ownersByActual[candidates.single].length == 1) {
      actualIndex = candidates.single;
    } else if (item['matchPattern'] == null && candidates.isNotEmpty) {
      final exactGroup = <int>[
        for (var j = 0; j < items.length; j++)
          if ((items[j] as Map)['matchPattern'] == null &&
              _normalized(items[j]['description'] as String) ==
                  _normalized(description))
            j,
      ];
      // Any competing regex anchor makes the group ambiguous, even when its
      // own expected row appears later. Never choose matches by field values.
      final exclusive = candidates.every(
        (candidate) => ownersByActual[candidate].every(exactGroup.contains),
      );
      if (exclusive && exactGroup.length == candidates.length) {
        actualIndex = candidates[exactGroup.indexOf(index)];
      }
    }
    final actual = actualIndex == null ? null : draft.lines[actualIndex];
    if (actualIndex != null) {
      matched.add(actualIndex);
      detected++;
    } else {
      alignmentFailures.add({
        'row': '$index: $description',
        'reason': candidates.isEmpty ? 'noCandidate' : 'ambiguousCandidates',
        'candidateRows': candidates,
      });
    }
    score(
      'description',
      _normalized(description),
      actual == null ? null : _normalized(actual.description),
      '$index: $description',
      aligned: actual != null,
    );
    final values = <String, Object?>{
      'quantity': actual?.quantity,
      'unit': actual?.unit?.name,
      'amount': actual?.grossAmountCents,
    };
    for (final field in values.keys) {
      if (item.containsKey(field)) {
        score(
          field,
          item[field],
          values[field],
          '$index: $description',
          aligned: actual != null,
        );
      }
    }
  }
  if (expected.containsKey('total')) {
    score('total', expected['total'], draft.detectedTotalCents, 'receipt');
  }
  if (expected.containsKey('date')) {
    final date = expected['date'] as String?;
    score(
      'date',
      date == null ? null : DateTime.parse(date).toIso8601String(),
      draft.purchasedAt?.toIso8601String(),
      'receipt',
    );
  }
  return {
    'expectedRows': items.length,
    'matchedRows': detected,
    'missedRows': items.length - detected,
    'extraOrUnmatchedRows': draft.lines.length - matched.length,
    'alignmentFailures': alignmentFailures,
    'fields': fields,
    'failures': failures,
  };
}
