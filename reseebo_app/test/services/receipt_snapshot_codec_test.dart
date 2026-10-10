import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/errors/app_exception.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/core/models/pending_receipt.dart';
import 'package:reseebo_app/core/services/receipt_snapshot_codec.dart';

void main() {
  final codec = ReceiptSnapshotCodec();
  test(
    'lossless evidence snapshot preserves nulls, owner clears and all roles',
    () {
      final provenance = ReceiptFieldProvenance(
        origin: ReceiptFieldOrigin.ownerEdited,
        explanation: 'Owner cleared value',
        sourcePurchaseId: 'purchase',
        sourceReceiptId: 'receipt',
        sourceSupplierId: 'supplier',
        sourceSupplierName: 'Supplier A',
        sourcePurchasedAt: DateTime.utc(2026, 3, 2, 14, 30),
      );
      const line = OcrTextLine(
        text: 'raw',
        left: 1.25,
        top: 2,
        width: 30,
        height: 4,
        tokens: [
          OcrTextToken(text: 'raw', left: 2, top: 3, width: 4, height: 5),
        ],
      );
      final draft = ReceiptDraft(
        operationId: 'draft-operation',
        imagePath: 'original',
        imagePaths: ['original', 'original-2'],
        recognitionImagePath: 'recognition',
        supplierId: null,
        supplierName: '',
        supplierBranch: '',
        supplierNotes: 'supplier notes',
        purchasedAt: null,
        hasPurchaseTime: true,
        dateConfirmed: false,
        dateManuallyEdited: true,
        dateFromReceipt: true,
        dateCandidates: [
          PurchaseDateCandidate(
            DateTime(2026, 4, 5, 12),
            NumericDateOrder.dayFirst,
            true,
          ),
          PurchaseDateCandidate(
            DateTime(2026, 5, 4, 12),
            NumericDateOrder.monthFirst,
            true,
          ),
        ],
        receiptNumber: 'OR1',
        notes: 'notes',
        rawText: 'ALL RAW OCR',
        detectedTotalCents: null,
        totalIsPartial: true,
        totalDifferenceConfirmed: true,
        allowDuplicate: true,
        textLines: [line],
        warnings: ['draft warning'],
        provenance: {ReceiptMetadataField.supplier: provenance},
        ocrPages: [
          ReceiptOcrPage(
            imagePath: 'original',
            recognitionImagePath: 'recognition',
            comparisonImagePath: 'comparison',
            textLines: [line],
            originalTextLines: [line],
          ),
          const ReceiptOcrPage(imagePath: 'original-2', textLines: []),
        ],
        ocrRun: const OcrRunMetadata(
          engineId: OcrEngineId.ppOcrV6Medium,
          modelVersion: 'model',
          runtimeVersion: 'runtime',
          parserVersion: '2',
          inputDigest: 'digest',
          preprocessingRevision: 'rotate 90',
          elapsedMs: 42,
        ),
        mediaEvidence: [
          const ReceiptPageMedia(
            original: ReceiptImageReference(
              path: 'original',
              sha256: 'hash',
              width: 30,
              height: 60,
              preprocessingIdentity: 'unedited',
            ),
            recognition: ReceiptImageReference(
              path: 'recognition',
              sha256: 'hash-rec',
              width: 60,
              height: 30,
              preprocessingIdentity: 'rotate 90',
            ),
            comparison: ReceiptImageReference(
              path: 'comparison',
              sha256: 'hash-cmp',
              width: 30,
              height: 60,
              preprocessingIdentity: 'comparison',
            ),
          ),
          const ReceiptPageMedia(
            original: ReceiptImageReference(
              path: 'original-2',
              sha256: 'hash-2',
              width: 10,
              height: 20,
              preprocessingIdentity: 'unedited',
            ),
          ),
        ],
        lines: [
          ParsedLineItem(
            id: 'stable-line',
            description: 'Coffee',
            productId: null,
            matchOrigin: 'cleared',
            printedItemCode: 'CODE',
            extractedQuantity: 2,
            extractedAmountCents: null,
            extractedUnitPriceCents: 2100,
            quantityEdited: true,
            amountEdited: true,
            quantity: null,
            unit: null,
            piecesPerPack: null,
            grossAmountCents: null,
            discountCents: 100,
            normalizedDiscountCents: 1000,
            confirmed: false,
            sourcePage: 1,
            possibleDuplicateOf: 'earlier-line',
            warnings: ['line warning'],
            provenance: {ReceiptSuggestionField.amount: provenance},
          ),
        ],
      );
      final encoded = codec.encode(draft);
      final restored = codec.decode(encoded);
      expect(codec.encode(restored), encoded);
      expect(restored.lines.single.id, 'stable-line');
      expect(restored.lines.single.normalizedDiscountCents, 1000);
      expect(restored.lines.single.extractedUnitPriceCents, 2100);
      expect(restored.lines.single.grossAmountCents, isNull);
      expect(restored.lines.single.productId, isNull);
      expect(
        restored.ocrPages.first.originalTextLines.first.tokens.first.left,
        2,
      );
      expect(restored.mediaEvidence.first.comparison!.path, 'comparison');
      expect(restored.operationId, 'draft-operation');
      expect(restored.rawText, 'ALL RAW OCR');
      expect(restored.warnings, ['draft warning']);
      expect(restored.imagePaths, ['original', 'original-2']);
      expect(restored.ocrRun!.engineId, OcrEngineId.ppOcrV6Medium);
      expect(restored.ocrRun!.preprocessingRevision, 'rotate 90');
      expect(restored.ocrRun!.inputDigest, 'digest');
      expect(restored.ocrRun!.elapsedMs, 42);
      expect(restored.purchasedAt, isNull);
      expect(restored.detectedTotalCents, isNull);
      expect(restored.totalIsPartial, isTrue);
      expect(restored.allowDuplicate, isTrue);
      expect(restored.hasPurchaseTime, isTrue);
      expect(restored.dateConfirmed, isFalse);
      expect(restored.dateManuallyEdited, isTrue);
      expect(restored.dateFromReceipt, isTrue);
      expect(restored.dateCandidates.map((c) => c.order), [
        NumericDateOrder.dayFirst,
        NumericDateOrder.monthFirst,
      ]);
      expect(restored.dateCandidates.first.date, DateTime(2026, 4, 5, 12));
      expect(
        restored.provenance[ReceiptMetadataField.supplier]!.sourcePurchasedAt,
        DateTime.utc(2026, 3, 2, 14, 30),
      );
      expect(
        restored.lines.single.provenance[ReceiptSuggestionField.amount]!.origin,
        ReceiptFieldOrigin.ownerEdited,
      );
      expect(
        restored
            .lines
            .single
            .provenance[ReceiptSuggestionField.amount]!
            .sourcePurchaseId,
        'purchase',
      );
      expect(restored.lines.single.quantityEdited, isTrue);
      expect(restored.lines.single.amountEdited, isTrue);
      expect(restored.lines.single.quantity, isNull);
      expect(restored.lines.single.unit, isNull);
      expect(restored.lines.single.piecesPerPack, isNull);
      expect(restored.lines.single.extractedAmountCents, isNull);
      expect(restored.lines.single.extractedQuantity, 2);
      expect(restored.lines.single.printedItemCode, 'CODE');
      expect(restored.lines.single.sourcePage, 1);
      expect(restored.lines.single.possibleDuplicateOf, 'earlier-line');
      expect(restored.lines.single.warnings, ['line warning']);
      draft.lines.single.description = 'mutated';
      expect(restored.lines.single.description, 'Coffee');
      expect(codec.encode(restored.snapshot()), encoded);
    },
  );
  test('unknown snapshot version has a typed readable error', () {
    final json =
        jsonDecode(codec.encode(ReceiptDraft(imagePath: 'image')))
            as Map<String, dynamic>;
    json['version'] = 999;
    expect(
      () => codec.decode(jsonEncode(json)),
      throwsA(
        isA<ReceiptSnapshotException>().having(
          (e) => e.message,
          'message',
          contains('version'),
        ),
      ),
    );
  });
  test(
    'malformed nullable types and unrecognized fields never disappear silently',
    () {
      for (final entry in {
        'purchasedAt': 4,
        'detectedTotalCents': '100',
        'totalIsPartial': null,
        'supplierId': [],
        'unknownEvidence': 'do not discard',
      }.entries) {
        final json =
            jsonDecode(codec.encode(ReceiptDraft(imagePath: 'image')))
                as Map<String, dynamic>;
        (json['draft'] as Map<String, dynamic>)[entry.key] = entry.value;
        expect(
          () => codec.decode(jsonEncode(json)),
          throwsA(isA<ReceiptSnapshotException>()),
          reason: entry.key,
        );
      }
    },
  );
  test(
    'every provenance key and origin is retained with stable dictionary ordering',
    () {
      final provenance = {
        for (final field in ReceiptMetadataField.values)
          field: ReceiptFieldProvenance(
            origin: ReceiptFieldOrigin.values[field.index],
            explanation: field.name,
          ),
      };
      final lineProvenance = {
        for (final field in ReceiptSuggestionField.values)
          field: ReceiptFieldProvenance(
            origin: ReceiptFieldOrigin
                .values[field.index % ReceiptFieldOrigin.values.length],
            explanation: field.name,
          ),
      };
      final draft = ReceiptDraft(
        imagePath: 'image',
        provenance: provenance,
        lines: [ParsedLineItem(id: 'line', provenance: lineProvenance)],
      );
      final restored = codec.decode(codec.encode(draft));
      expect(restored.provenance.keys, ReceiptMetadataField.values);
      expect(
        restored.lines.single.provenance.keys,
        ReceiptSuggestionField.values,
      );
      expect(
        restored
            .lines
            .single
            .provenance[ReceiptSuggestionField.piecesPerPack]!
            .origin,
        ReceiptFieldOrigin.ownerEdited,
      );
      final rearranged = draft.snapshot();
      rearranged.provenance.clear();
      rearranged.provenance.addEntries(provenance.entries.toList().reversed);
      expect(codec.encode(rearranged), codec.encode(draft));
    },
  );
}
