import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_validator.dart';
import 'package:reseebo_app/core/errors/app_exception.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';

const _product = Product(
  id: 'coffee',
  name: 'Coffee',
  brand: 'Brand X',
  variant: 'Original',
  size: '26g',
);

class _ReviewAdapter extends MockReseeboDataAdapter {
  ReceiptDraft? saved;
  bool duplicate = false;
  @override
  Future<List<Product>> getProducts({String? query}) async => [_product];
  @override
  Future<List<Supplier>> getSuppliers() async => [];
  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft draft) async {
    ReceiptValidator.validate(draft);
    if (duplicate && !draft.allowDuplicate) {
      throw const DuplicateReceiptException(['earlier']);
    }
    saved = draft.snapshot();
    return const SaveReceiptResult(
      receiptId: 'saved',
      lineIds: ['line'],
      unitCostsCents: [1000],
    );
  }
}

ReceiptDraft _validDraft() => ReceiptDraft(
  imagePath: 'original.jpg',
  supplierName: 'New supplier',
  purchasedAt: DateTime(2026, 10, 8),
  dateConfirmed: true,
  lines: [
    ParsedLineItem(
      id: 'line',
      description: 'Coffee',
      productId: 'coffee',
      quantity: 2,
      unit: PurchaseUnit.piece,
      piecesPerPack: 1,
      grossAmountCents: 2000,
      confirmed: true,
    ),
  ],
);

void main() {
  testWidgets('review controls fit a 360dp phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = _validDraft();
    draft.lines.single.unit = PurchaseUnit.pack;
    draft.lines.single.piecesPerPack = 10;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: ReviewMatchScreen(
          dataAdapter: _ReviewAdapter(),
          initialDraft: draft,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('piecesPerPack')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final bounds = tester.getRect(find.byKey(const ValueKey('piecesPerPack')));
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(360));
    await tester.scrollUntilVisible(
      find.text('I checked this item'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editing a checked quantity requires confirmation again before save',
    (tester) async {
      final adapter = _ReviewAdapter();
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewMatchScreen(
            dataAdapter: adapter,
            initialDraft: _validDraft(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quantity')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(const ValueKey('quantity')), '4');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save receipt'));
      await tester.pumpAndSettle();
      expect(adapter.saved, isNull);
      expect(
        find.textContaining('Check and confirm this product'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'recognized token assignment updates the target field without confirming it',
    (tester) async {
      final adapter = _ReviewAdapter();
      final draft = _validDraft();
      final evidenceDraft = ReceiptDraft(
        imagePath: draft.imagePath,
        supplierName: draft.supplierName,
        purchasedAt: draft.purchasedAt,
        dateConfirmed: true,
        lines: draft.lines,
        ocrPages: [
          const ReceiptOcrPage(
            imagePath: 'original.jpg',
            recognitionImagePath: 'cropped.jpg',
            textLines: [
              OcrTextLine(
                text: '12 Coffee',
                tokens: [
                  OcrTextToken(text: '12'),
                  OcrTextToken(text: 'Coffee'),
                ],
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewMatchScreen(
            dataAdapter: adapter,
            initialDraft: evidenceDraft,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byWidgetPredicate(
        (widget) =>
            widget is ChoiceChip &&
            widget.label is Text &&
            (widget.label as Text).data == 'Quantity',
      );
      await tester.scrollUntilVisible(
        find.text('Receipt details'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Receipt details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receipt details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Photo used for recognition'), findsOneWidget);
      await tester.ensureVisible(find.text('Recognized text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recognized text'));
      await tester.pumpAndSettle();
      final token = find.byWidgetPredicate(
        (widget) =>
            widget is FilterChip &&
            widget.label is Text &&
            (widget.label as Text).data == '12',
      );
      await tester.ensureVisible(token);
      await tester.pumpAndSettle();
      await tester.tap(token);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Apply to field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to field'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quantity')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final editor = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('quantity')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editor.controller.text, '12');
      expect(
        find.textContaining('Check and confirm this product'),
        findsWidgets,
      );
      expect(draft.lines.single.quantity, 2);
    },
  );

  testWidgets(
    'duplicate save resumes only after separate purchase confirmation',
    (tester) async {
      final adapter = _ReviewAdapter()..duplicate = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewMatchScreen(
            dataAdapter: adapter,
            initialDraft: _validDraft(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Possible duplicate receipt'), findsOneWidget);
      expect(adapter.saved, isNull);
      await tester.tap(find.text('This is a separate purchase'));
      await tester.pumpAndSettle();
      expect(adapter.saved!.allowDuplicate, isTrue);
      expect(adapter.saved!.lines.single.quantity, 2);
    },
  );

  testWidgets(
    'save preserves reviewed date, operation and every original page',
    (tester) async {
      final adapter = _ReviewAdapter();
      final draft = ReceiptDraft(
        operationId: 'operation',
        imagePath: 'original-a.jpg',
        imagePaths: ['original-a.jpg', 'original-b.jpg'],
        supplierName: 'New supplier',
        purchasedAt: DateTime(2026, 10, 8),
        dateConfirmed: true,
        receiptNumber: '123',
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            productId: 'coffee',
            quantity: 2,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            grossAmountCents: 2000,
            confirmed: true,
          ),
        ],
      );
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewMatchScreen(
            dataAdapter: adapter,
            initialDraft: draft,
            onSaved: (_) => saved = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save receipt'));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(adapter.saved!.operationId, 'operation');
      expect(adapter.saved!.imagePaths, ['original-a.jpg', 'original-b.jpg']);
      expect(adapter.saved!.dateConfirmed, isTrue);
      expect(adapter.saved!.supplierName, 'New supplier');
    },
  );
}
