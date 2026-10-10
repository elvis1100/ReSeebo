import 'dart:convert';

import '../errors/app_exception.dart';
import '../models/models.dart';
import '../models/ocr_engine.dart';
import '../models/pending_receipt.dart';

/// Versioned, lossless evidence DTO. Unknown versions, fields and malformed
/// types fail explicitly instead of reopening a partially discarded receipt.
class ReceiptSnapshotCodec {
  static const version = 1;
  String encode(ReceiptDraft draft) => jsonEncode(toMap(draft));
  ReceiptDraft decode(String payload) {
    try {
      return fromMap(jsonDecode(payload));
    } on ReceiptSnapshotException {
      rethrow;
    } on Object {
      throw const ReceiptSnapshotException(
        'The saved receipt snapshot is malformed.',
      );
    }
  }

  Map<String, Object?> toMap(ReceiptDraft d) => {
    'version': version,
    'draft': {
      'operationId': d.operationId,
      'imagePath': d.imagePath,
      'imagePaths': d.imagePaths,
      'recognitionImagePath': d.recognitionImagePath,
      'supplierId': d.supplierId,
      'supplierName': d.supplierName,
      'supplierBranch': d.supplierBranch,
      'supplierNotes': d.supplierNotes,
      'purchasedAt': d.purchasedAt?.toIso8601String(),
      'hasPurchaseTime': d.hasPurchaseTime,
      'dateConfirmed': d.dateConfirmed,
      'dateManuallyEdited': d.dateManuallyEdited,
      'dateFromReceipt': d.dateFromReceipt,
      'dateCandidates': d.dateCandidates
          .map(
            (c) => {
              'date': c.date.toIso8601String(),
              'order': c.order.name,
              'hasTime': c.hasTime,
            },
          )
          .toList(),
      'receiptNumber': d.receiptNumber,
      'notes': d.notes,
      'rawText': d.rawText,
      'detectedTotalCents': d.detectedTotalCents,
      'totalIsPartial': d.totalIsPartial,
      'ocrRun': d.ocrRun?.toJson(),
      'provenance': _provenance(d.provenance, ReceiptMetadataField.values),
      'totalDifferenceConfirmed': d.totalDifferenceConfirmed,
      'allowDuplicate': d.allowDuplicate,
      'textLines': d.textLines.map(_ocrLine).toList(),
      'ocrPages': d.ocrPages
          .map(
            (p) => {
              'imagePath': p.imagePath,
              'recognitionImagePath': p.recognitionImagePath,
              'comparisonImagePath': p.comparisonImagePath,
              'textLines': p.textLines.map(_ocrLine).toList(),
              'originalTextLines': p.originalTextLines.map(_ocrLine).toList(),
            },
          )
          .toList(),
      'mediaEvidence': d.mediaEvidence.map(mediaToMap).toList(),
      'lines': d.lines
          .map(
            (l) => {
              'id': l.id,
              'description': l.description,
              'productId': l.productId,
              'matchOrigin': l.matchOrigin,
              'printedItemCode': l.printedItemCode,
              'extractedQuantity': l.extractedQuantity,
              'extractedAmountCents': l.extractedAmountCents,
              'extractedUnitPriceCents': l.extractedUnitPriceCents,
              'quantityEdited': l.quantityEdited,
              'amountEdited': l.amountEdited,
              'quantity': l.quantity,
              'unit': l.unit?.name,
              'piecesPerPack': l.piecesPerPack,
              'grossAmountCents': l.grossAmountCents,
              'discountCents': l.discountCents,
              'normalizedDiscountCents': l.normalizedDiscountCents,
              'confirmed': l.confirmed,
              'sourcePage': l.sourcePage,
              'possibleDuplicateOf': l.possibleDuplicateOf,
              'provenance': _provenance(
                l.provenance,
                ReceiptSuggestionField.values,
              ),
              'warnings': l.warnings,
            },
          )
          .toList(),
      'warnings': d.warnings,
    },
  };

  static Map<String, Object?> referenceToMap(ReceiptImageReference r) => {
    'path': r.path,
    'sha256': r.sha256,
    'width': r.width,
    'height': r.height,
    'preprocessingIdentity': r.preprocessingIdentity,
  };
  static Map<String, Object?> mediaToMap(ReceiptPageMedia p) => {
    'original': referenceToMap(p.original),
    'recognition': p.recognition == null
        ? null
        : referenceToMap(p.recognition!),
    'comparison': p.comparison == null ? null : referenceToMap(p.comparison!),
  };
  static Map<String, Object?> _provenance<T extends Enum>(
    Map<T, ReceiptFieldProvenance> values,
    List<T> keys,
  ) => {
    for (final key in keys)
      if (values.containsKey(key))
        key.name: {
          'origin': values[key]!.origin.name,
          'explanation': values[key]!.explanation,
          'sourcePurchaseId': values[key]!.sourcePurchaseId,
          'sourceReceiptId': values[key]!.sourceReceiptId,
          'sourceSupplierId': values[key]!.sourceSupplierId,
          'sourceSupplierName': values[key]!.sourceSupplierName,
          'sourcePurchasedAt': values[key]!.sourcePurchasedAt
              ?.toIso8601String(),
        },
  };
  static Map<String, Object?> _ocrLine(OcrTextLine l) => {
    'text': l.text,
    'left': l.left,
    'top': l.top,
    'width': l.width,
    'height': l.height,
    'tokens': l.tokens
        .map(
          (t) => {
            'text': t.text,
            'left': t.left,
            'top': t.top,
            'width': t.width,
            'height': t.height,
          },
        )
        .toList(),
  };

  ReceiptDraft fromMap(Object? payload) {
    final root = _Dto(payload, 'snapshot', ['version', 'draft']);
    if (root.integer('version') != version) {
      throw const ReceiptSnapshotException(
        'This receipt snapshot version is not supported.',
      );
    }
    final d = _Dto(root.value('draft'), 'draft', [
      'operationId',
      'imagePath',
      'imagePaths',
      'recognitionImagePath',
      'supplierId',
      'supplierName',
      'supplierBranch',
      'supplierNotes',
      'purchasedAt',
      'hasPurchaseTime',
      'dateConfirmed',
      'dateManuallyEdited',
      'dateFromReceipt',
      'dateCandidates',
      'receiptNumber',
      'notes',
      'rawText',
      'detectedTotalCents',
      'totalIsPartial',
      'ocrRun',
      'provenance',
      'totalDifferenceConfirmed',
      'allowDuplicate',
      'textLines',
      'ocrPages',
      'mediaEvidence',
      'lines',
      'warnings',
    ]);
    final runValue = d.value('ocrRun');
    OcrRunMetadata? run;
    if (runValue != null) {
      final r = _Dto(runValue, 'ocrRun', [
        'engineId',
        'modelVersion',
        'runtimeVersion',
        'parserVersion',
        'inputDigest',
        'preprocessingRevision',
        'elapsedMs',
      ]);
      try {
        run = OcrRunMetadata.fromJson(r.map);
      } on Object {
        throw const ReceiptSnapshotException(
          'Invalid receipt OCR run metadata.',
        );
      }
    }
    return ReceiptDraft(
      operationId: d.text('operationId'),
      imagePath: d.text('imagePath'),
      imagePaths: d.strings('imagePaths'),
      recognitionImagePath: d.optionalText('recognitionImagePath'),
      supplierId: d.optionalText('supplierId'),
      supplierName: d.text('supplierName'),
      supplierBranch: d.text('supplierBranch'),
      supplierNotes: d.text('supplierNotes'),
      purchasedAt: d.date('purchasedAt'),
      hasPurchaseTime: d.boolean('hasPurchaseTime'),
      dateConfirmed: d.boolean('dateConfirmed'),
      dateManuallyEdited: d.boolean('dateManuallyEdited'),
      dateFromReceipt: d.boolean('dateFromReceipt'),
      dateCandidates: d.list('dateCandidates').map((v) {
        final c = _Dto(v, 'date candidate', ['date', 'order', 'hasTime']);
        return PurchaseDateCandidate(
          c.date('date', required: true)!,
          c.enumeration('order', NumericDateOrder.values)!,
          c.boolean('hasTime'),
        );
      }).toList(),
      receiptNumber: d.text('receiptNumber'),
      notes: d.text('notes'),
      rawText: d.text('rawText'),
      detectedTotalCents: d.optionalInteger('detectedTotalCents'),
      totalIsPartial: d.boolean('totalIsPartial'),
      ocrRun: run,
      provenance: _readProvenance(
        d.value('provenance'),
        ReceiptMetadataField.values,
      ),
      totalDifferenceConfirmed: d.boolean('totalDifferenceConfirmed'),
      allowDuplicate: d.boolean('allowDuplicate'),
      textLines: d.list('textLines').map(_readOcrLine).toList(),
      ocrPages: d.list('ocrPages').map((v) {
        final p = _Dto(v, 'OCR page', [
          'imagePath',
          'recognitionImagePath',
          'comparisonImagePath',
          'textLines',
          'originalTextLines',
        ]);
        return ReceiptOcrPage(
          imagePath: p.text('imagePath'),
          recognitionImagePath: p.optionalText('recognitionImagePath'),
          comparisonImagePath: p.optionalText('comparisonImagePath'),
          textLines: p.list('textLines').map(_readOcrLine).toList(),
          originalTextLines: p
              .list('originalTextLines')
              .map(_readOcrLine)
              .toList(),
        );
      }).toList(),
      mediaEvidence: d.list('mediaEvidence').map((v) {
        final p = _Dto(v, 'media page', [
          'original',
          'recognition',
          'comparison',
        ]);
        return ReceiptPageMedia(
          original: _readReference(p.value('original')),
          recognition: p.value('recognition') == null
              ? null
              : _readReference(p.value('recognition')),
          comparison: p.value('comparison') == null
              ? null
              : _readReference(p.value('comparison')),
        );
      }).toList(),
      lines: d.list('lines').map((v) {
        final l = _Dto(v, 'receipt line', [
          'id',
          'description',
          'productId',
          'matchOrigin',
          'printedItemCode',
          'extractedQuantity',
          'extractedAmountCents',
          'extractedUnitPriceCents',
          'quantityEdited',
          'amountEdited',
          'quantity',
          'unit',
          'piecesPerPack',
          'grossAmountCents',
          'discountCents',
          'normalizedDiscountCents',
          'confirmed',
          'sourcePage',
          'possibleDuplicateOf',
          'provenance',
          'warnings',
        ]);
        return ParsedLineItem(
          id: l.text('id'),
          description: l.text('description'),
          productId: l.optionalText('productId'),
          matchOrigin: l.optionalText('matchOrigin'),
          printedItemCode: l.optionalText('printedItemCode'),
          extractedQuantity: l.optionalInteger('extractedQuantity'),
          extractedAmountCents: l.optionalInteger('extractedAmountCents'),
          extractedUnitPriceCents: l.optionalInteger('extractedUnitPriceCents'),
          quantityEdited: l.boolean('quantityEdited'),
          amountEdited: l.boolean('amountEdited'),
          quantity: l.optionalInteger('quantity'),
          unit: l.enumeration('unit', PurchaseUnit.values, nullable: true),
          piecesPerPack: l.optionalInteger('piecesPerPack'),
          grossAmountCents: l.optionalInteger('grossAmountCents'),
          discountCents: l.integer('discountCents'),
          normalizedDiscountCents: l.integer('normalizedDiscountCents'),
          confirmed: l.boolean('confirmed'),
          sourcePage: l.integer('sourcePage'),
          possibleDuplicateOf: l.optionalText('possibleDuplicateOf'),
          provenance: _readProvenance(
            l.value('provenance'),
            ReceiptSuggestionField.values,
          ),
          warnings: l.strings('warnings'),
        );
      }).toList(),
      warnings: d.strings('warnings'),
    );
  }

  static ReceiptImageReference _readReference(Object? value) {
    final r = _Dto(value, 'image reference', [
      'path',
      'sha256',
      'width',
      'height',
      'preprocessingIdentity',
    ]);
    return ReceiptImageReference(
      path: r.text('path'),
      sha256: r.text('sha256'),
      width: r.integer('width'),
      height: r.integer('height'),
      preprocessingIdentity: r.text('preprocessingIdentity'),
    );
  }

  static OcrTextLine _readOcrLine(Object? value) {
    final l = _Dto(value, 'OCR line', [
      'text',
      'left',
      'top',
      'width',
      'height',
      'tokens',
    ]);
    return OcrTextLine(
      text: l.text('text'),
      left: l.number('left'),
      top: l.number('top'),
      width: l.number('width'),
      height: l.number('height'),
      tokens: l.list('tokens').map((v) {
        final t = _Dto(v, 'OCR token', [
          'text',
          'left',
          'top',
          'width',
          'height',
        ]);
        return OcrTextToken(
          text: t.text('text'),
          left: t.number('left'),
          top: t.number('top'),
          width: t.number('width'),
          height: t.number('height'),
        );
      }).toList(),
    );
  }

  static Map<T, ReceiptFieldProvenance> _readProvenance<T extends Enum>(
    Object? value,
    List<T> keys,
  ) {
    final p = _Dto(
      value,
      'provenance',
      keys.map((e) => e.name).toList(),
      optionalKeys: true,
    );
    return {
      for (final key in keys)
        if (p.map.containsKey(key.name)) key: _readOrigin(p.map[key.name]),
    };
  }

  static ReceiptFieldProvenance _readOrigin(Object? value) {
    final p = _Dto(value, 'field provenance', [
      'origin',
      'explanation',
      'sourcePurchaseId',
      'sourceReceiptId',
      'sourceSupplierId',
      'sourceSupplierName',
      'sourcePurchasedAt',
    ]);
    return ReceiptFieldProvenance(
      origin: p.enumeration('origin', ReceiptFieldOrigin.values)!,
      explanation: p.text('explanation'),
      sourcePurchaseId: p.optionalText('sourcePurchaseId'),
      sourceReceiptId: p.optionalText('sourceReceiptId'),
      sourceSupplierId: p.optionalText('sourceSupplierId'),
      sourceSupplierName: p.optionalText('sourceSupplierName'),
      sourcePurchasedAt: p.date('sourcePurchasedAt'),
    );
  }
}

class _Dto {
  _Dto(
    Object? value,
    this.label,
    List<String> keys, {
    bool optionalKeys = false,
  }) {
    if (value is! Map ||
        value.keys.any((k) => k is! String || !keys.contains(k)) ||
        (!optionalKeys && keys.any((k) => !value.containsKey(k)))) {
      _bad('fields');
    }
    map = Map<String, dynamic>.from(value);
  }
  final String label;
  late final Map<String, dynamic> map;
  Never _bad(String field) =>
      throw ReceiptSnapshotException('Invalid saved receipt $label $field.');
  Object? value(String key) => map[key];
  String text(String key) =>
      map[key] is String ? map[key] as String : _bad(key);
  String? optionalText(String key) => map[key] == null ? null : text(key);
  int integer(String key) => map[key] is int ? map[key] as int : _bad(key);
  int? optionalInteger(String key) => map[key] == null ? null : integer(key);
  bool boolean(String key) => map[key] is bool ? map[key] as bool : _bad(key);
  double number(String key) => map[key] is num && (map[key] as num).isFinite
      ? (map[key] as num).toDouble()
      : _bad(key);
  List<dynamic> list(String key) =>
      map[key] is List ? map[key] as List : _bad(key);
  List<String> strings(String key) =>
      list(key).map((v) => v is String ? v : _bad(key)).toList();
  DateTime? date(String key, {bool required = false}) {
    if (map[key] == null && !required) return null;
    final parsed = DateTime.tryParse(text(key));
    if (parsed == null) _bad(key);
    return parsed;
  }

  T? enumeration<T extends Enum>(
    String key,
    List<T> values, {
    bool nullable = false,
  }) {
    if (map[key] == null && nullable) return null;
    final name = text(key);
    for (final value in values) {
      if (value.name == name) return value;
    }
    return _bad(key);
  }
}
