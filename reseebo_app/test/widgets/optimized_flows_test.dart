import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/state/local_editor_controller.dart';
import 'package:reseebo_app/features/comparison/screens/product_comparison_screen.dart';
import 'package:reseebo_app/features/comparison/state/comparison_controller.dart';
import 'package:reseebo_app/features/planner/screens/basket_planner_screen.dart';
import 'package:reseebo_app/features/planner/state/basket_controller.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';
import 'package:reseebo_app/features/receipts/screens/receipt_detail_screen.dart';
import 'dashboard_comparison_test.dart' as fixtures;

class FlowAdapter extends fixtures.FixtureAdapter {
  final recognition = Completer<ReceiptDraft>();
  final commit = Completer<SaveReceiptResult>();
  final basket = Completer<BasketEstimate>();
  int saves = 0;
  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> paths, {
    List<String>? recognitionImagePaths,
  }) => recognition.future;
  @override
  Future<List<Product>> getProducts({String? query}) async => [
    fixtures.product,
    fixtures.missingProduct,
  ];
  @override
  Future<Product?> getProductById(String id) async =>
      id == fixtures.product.id ? fixtures.product : fixtures.missingProduct;
  @override
  Future<List<ProductAlias>> getAliases(String productId) async => [];
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(String description) async =>
      [];
  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft draft) {
    saves++;
    return commit.future;
  }

  @override
  Future<ReceiptDetail> getReceipt(String id) async => ReceiptDetail(
    receipt: Receipt(
      id: id,
      supplier: fixtures.supplierA,
      purchasedAt: DateTime(2026, 10, 9),
      hasPurchaseTime: false,
      createdAt: DateTime(2026, 10, 9),
      imagePath: '/missing.jpg',
      lineCount: 1,
      totalCents: 8400,
    ),
    lines: [records[1]],
  );
}

ReceiptDraft validDraft() => ReceiptDraft(
  imagePath: '/missing.jpg',
  supplierName: 'Supplier A',
  purchasedAt: DateTime(2026, 10, 9),
  dateConfirmed: true,
  lines: [
    ParsedLineItem(
      description: 'Coffee 26G',
      productId: fixtures.product.id,
      quantity: 1,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      grossAmountCents: 8400,
      confirmed: true,
    ),
  ],
);

Finder priceScroll() => find
    .descendant(
      of: find.byKey(const PageStorageKey('comparison-prices')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  test(
    'capture preserves page order and excludes identical imported bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp('reseebo-pages-');
      final a = File('${directory.path}/a.jpg');
      final b = File('${directory.path}/b.jpg');
      final duplicate = File('${directory.path}/same.jpg');
      await a.writeAsString('first page');
      await b.writeAsString('second page');
      await a.copy(duplicate.path);
      final state = CaptureState(adapter: FlowAdapter());
      try {
        await state.addImages([a.path, b.path, duplicate.path]);
        expect(state.pages, hasLength(2));
        expect(state.notice, contains('duplicate photo'));
        state.moveSelectedPage(-1);
        expect(state.manualDraft().imagePaths, [b.path, a.path]);
        state.removeSelectedPage();
        expect(state.manualDraft().imagePaths, [a.path]);
      } finally {
        state.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'overlap decisions block saving until resolved and invalidate confirmation',
    () async {
      final draft = validDraft();
      final earlier = draft.lines.single;
      final repeated = earlier.snapshot();
      final later = ParsedLineItem(
        description: repeated.description,
        productId: repeated.productId,
        quantity: 1,
        unit: PurchaseUnit.pack,
        piecesPerPack: 10,
        grossAmountCents: 8400,
        confirmed: true,
        possibleDuplicateOf: earlier.id,
      );
      draft.lines.add(later);
      final state = ReceiptReviewState(adapter: FlowAdapter(), draft: draft);
      await state.load();
      expect(state.problem, contains('overlap'));
      state.removeLine(state.draft.lines.first);
      expect(state.draft.lines.single.possibleDuplicateOf, isNull);
      expect(state.draft.lines.single.confirmed, isFalse);
      state.confirmLine(state.draft.lines.single);
      expect(state.problem, isNull);
      state.dispose();
    },
  );

  test(
    'local editor submits once and preserves the caller draft after failure',
    () async {
      final pending = Completer<void>();
      var writes = 0;
      final editor = LocalEditorController<String>(
        write: (_) {
          writes++;
          return pending.future;
        },
      );
      final first = editor.save('draft');
      expect(editor.saving, isTrue);
      expect(await editor.save('draft'), isFalse);
      pending.completeError(const AppException('Storage unavailable'));
      expect(await first, isFalse);
      expect(editor.saved, isFalse);
      expect(writes, 1);
      expect(editor.error, isA<AppException>());
      editor.dispose();
    },
  );

  test(
    'comparison refresh retains scenario inputs while saved edit can reset them',
    () async {
      final controller = ComparisonController(
        FlowAdapter(),
        fixtures.product.id,
      );
      await controller.load();
      controller.changePricing(markup: '35', selling: '15.00');
      await controller.load();
      expect(controller.markupInput, '35');
      expect(controller.sellingInput, '15.00');
      await controller.load(resetPricing: true);
      expect(controller.markupInput, '0.0');
      controller.dispose();
    },
  );

  testWidgets('capture blocks original navigation during recognition', (
    tester,
  ) async {
    final adapter = FlowAdapter();
    await tester.pumpWidget(
      fixtures.app(
        CaptureScreen(adapter: adapter, initialImagePath: '/missing.jpg'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Recognize receipt'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Recognize receipt'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Open original photo'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Open original photo'),
          )
          .onPressed,
      isNull,
    );
    adapter.recognition.complete(validDraft());
    await tester.pumpAndSettle();
    expect(find.text('Review & match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review locks viewers during save and returns the committed receipt',
    (tester) async {
      final adapter = FlowAdapter();
      SaveReceiptResult? result;
      await tester.pumpWidget(
        fixtures.app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<SaveReceiptResult>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReviewMatchScreen(
                        adapter: adapter,
                        draft: validDraft(),
                      ),
                    ),
                  );
                },
                child: const Text('Review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save confirmed purchase'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save confirmed purchase'));
      await tester.pump();
      expect(adapter.saves, 1);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('View original receipt'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Open original · pinch to zoom'),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Open original · pinch to zoom'),
            )
            .onPressed,
        isNull,
      );
      adapter.commit.complete(
        const SaveReceiptResult(
          receiptId: 'saved',
          lineIds: ['line'],
          unitCostsCents: [840],
        ),
      );
      await tester.pumpAndSettle();
      expect(result?.receiptId, 'saved');
      expect(find.text('Review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comparison keeps pricing inputs and scroll position after viewing a receipt',
    (tester) async {
      await tester.pumpWidget(
        fixtures.app(
          ProductComparisonScreen(
            adapter: FlowAdapter(),
            productId: fixtures.product.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pricing & restock'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Scenario markup (%)'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('comparison-calculators')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Scenario markup (%)'),
        '35',
      );
      await tester.tap(find.text('Prices & history'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('View source receipt').first,
        250,
        scrollable: priceScroll(),
      );
      final position = tester
          .state<ScrollableState>(priceScroll())
          .position
          .pixels;
      await tester.tap(find.text('View source receipt').first);
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptDetailScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(priceScroll()).position.pixels,
        position,
      );
      await tester.tap(find.text('Pricing & restock'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Scenario markup (%)'),
      );
      expect(field.controller!.text, '35');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'basket chooses products at narrow width and shows inline quantity errors',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        fixtures.app(BasketPlannerScreen(adapter: FlowAdapter()), scale: 1.3),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your basket is empty. Add a product to start.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Restock pieces'),
        findsNothing,
      );
      await tester.tap(find.text('Add products'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Search products'),
        '26 g',
      );
      await tester.pumpAndSettle();
      expect(find.text(fixtures.missingProduct.name), findsNothing);
      await tester.tap(find.text(fixtures.product.name));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Calculate buying basket'));
      await tester.tap(find.text('Calculate buying basket'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Coffee original: enter a whole quantity'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'basket names invalid amounts and freezes input while calculating',
    () async {
      final pending = Completer<BasketEstimate>();
      final adapter = PendingBasketAdapter(pending);
      final controller = BasketController(adapter);
      await controller.load();
      controller.addProduct(fixtures.product);
      expect(await controller.calculate(), isFalse);
      expect(
        controller.quantityError(fixtures.product.id),
        contains('Coffee original'),
      );
      controller.changeQuantity(fixtures.product.id, '2');
      controller.changeExtra(fixtures.supplierA.id, 'bad');
      expect(await controller.calculate(), isFalse);
      expect(
        controller.extraError(fixtures.supplierA.id),
        contains('Grocery A'),
      );
      controller.changeExtra(fixtures.supplierA.id, '0');
      final request = controller.calculate();
      expect(controller.calculating, isTrue);
      controller.changeQuantity(fixtures.product.id, '9');
      expect(controller.quantities[fixtures.product.id], '2');
      pending.complete(
        await fixtures.FixtureAdapter().calculateBasket({
          fixtures.product.id: 2,
        }),
      );
      expect(await request, isTrue);
      controller.removeProduct(fixtures.product.id);
      expect(controller.estimate, isNull);
      controller.dispose();
    },
  );
}

class PendingBasketAdapter extends FlowAdapter {
  PendingBasketAdapter(this.pending);
  final Completer<BasketEstimate> pending;
  @override
  Future<BasketEstimate> calculateBasket(
    Map<String, int> targetPieces, {
    Map<String, int> additionalCostsCents = const {},
  }) => pending.future;
}
