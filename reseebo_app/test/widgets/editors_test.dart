import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/features/catalog/screens/product_editor_screen.dart';
import 'package:reseebo_app/features/profile/screens/store_profile_screen.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/product_match_picker.dart';

const _product = Product(
  id: 'coffee',
  name: 'Coffee',
  brand: 'Brand X',
  variant: 'Original',
  size: '26g',
);

class _EditorAdapter implements IReseeboDataAdapter {
  StoreProfile profile = const StoreProfile();
  Product? savedProduct;
  int receiptSaves = 0;
  @override
  Future<StoreProfile> getStoreProfile() async => profile;
  @override
  Future<void> updateStoreProfile(StoreProfile value) async {
    profile = value;
  }

  @override
  Future<List<Product>> getProducts({String? query}) async => [_product];
  @override
  Future<List<Supplier>> getSuppliers() async => [];
  @override
  Future<List<ProductAlias>> getAliases(String productId) async => [];
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(String description) async =>
      [];
  @override
  Future<void> saveProduct(Product product) async {
    savedProduct = product;
  }

  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft draft) async {
    receiptSaves++;
    return const SaveReceiptResult(
      receiptId: 'receipt',
      lineIds: ['line'],
      unitCostsCents: [800],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReceiptDraft _draft() => ReceiptDraft(
  imagePath: '/receipt.jpg',
  supplierName: 'Wholesaler',
  purchasedAt: DateTime(2026, 10, 9),
  dateConfirmed: true,
  lines: [
    ParsedLineItem(
      description: 'COFFEE 26G',
      productId: _product.id,
      quantity: 2,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      grossAmountCents: 16000,
    ),
  ],
);

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => screen),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('product matching remains scrollable with a phone keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 350);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SizedBox(
            height: 544,
            child: ProductMatchPicker(
              adapter: _EditorAdapter(),
              description: 'BRANDX COF 26G',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Coffee'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Coffee'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('review requires explicit confirmation and editing clears it', () async {
    final state = ReceiptReviewState(
      adapter: _EditorAdapter(),
      draft: _draft(),
    );
    await state.load();
    expect(state.problem, contains('confirm'));
    final line = state.draft.lines.single;
    state.confirmLine(line);
    expect(state.problem, isNull);
    expect(line.costPerPieceCents, 800);
    line.quantity = 3;
    state.changed(line: line, affectsTotal: true);
    expect(line.confirmed, isFalse);
    expect(state.problem, contains('confirm'));
    state.dispose();
  });

  test('pack size and total mismatch block a save until reviewed', () async {
    final adapter = _EditorAdapter();
    final state = ReceiptReviewState(adapter: adapter, draft: _draft());
    await state.load();
    final line = state.draft.lines.single;
    line.piecesPerPack = null;
    expect(state.lineProblem(line), contains('pieces per pack'));
    line.piecesPerPack = 10;
    state.confirmLine(line);
    state.draft.detectedTotalCents = 17000;
    expect(state.problem, contains('difference'));
    await expectLater(state.save(), throwsA(isA<ValidationException>()));
    expect(adapter.receiptSaves, 0);
    state.draft.totalDifferenceConfirmed = true;
    await state.save();
    expect(adapter.receiptSaves, 1);
    state.dispose();
  });

  testWidgets('profile requires a name on save and keeps markup optional', (
    tester,
  ) async {
    final adapter = _EditorAdapter();
    await _open(tester, StoreProfileScreen(adapter: adapter));
    await tester.scrollUntilVisible(
      find.text('Save store details'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save store details'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your store name.'), findsOneWidget);
    expect(find.text('Your tindahan'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Store name'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Store name'),
      'Corner Store',
    );
    await tester.ensureVisible(find.text('Save store details'));
    await tester.tap(find.text('Save store details'));
    await tester.pumpAndSettle();
    expect(adapter.profile.name, 'Corner Store');
    expect(adapter.profile.defaultMarkupPercent, isNull);
    expect(find.text('Open editor'), findsOneWidget);
  });

  testWidgets('dirty editor back keeps edits until discard is confirmed', (
    tester,
  ) async {
    await _open(tester, StoreProfileScreen(adapter: _EditorAdapter()));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Store name'),
      'Unsaved Store',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved Store'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes').last);
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
  });

  testWidgets('product keeps exact identity and saves a zero markup override', (
    tester,
  ) async {
    final adapter = _EditorAdapter();
    await _open(
      tester,
      ProductEditorScreen(adapter: adapter, product: _product),
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(TextFormField, 'Product markup override (%)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Product markup override (%)'),
      '0',
    );
    await tester.scrollUntilVisible(
      find.text('Save product'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();
    expect(adapter.savedProduct?.identity, _product.identity);
    expect(adapter.savedProduct?.markupPercent, 0);
    expect(adapter.savedProduct?.sellingPriceCents, isNull);
    expect(find.text('Open editor'), findsOneWidget);
  });
}
