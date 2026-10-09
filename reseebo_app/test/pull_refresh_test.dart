import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/latest_product_cost.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:reseebo_app/features/profile/screens/profile_screen.dart';
import 'package:reseebo_app/features/comparison/screens/product_comparison_screen.dart';

const _product = Product(
  id: 'coffee',
  name: 'Coffee',
  brand: 'Coffee brand',
  variant: 'Original',
  size: '26g',
);

class _Adapter extends MockReseeboDataAdapter {
  int profileReads = 0;
  int productReads = 0;
  int comparisonReads = 0;
  bool empty = false;
  bool longCatalog = false;
  bool failedComparison = false;
  StoreProfile profile = const StoreProfile(
    name: 'Saved store',
    ownerName: 'Saved owner',
  );
  @override
  Future<StoreProfile> getStoreProfile() async {
    profileReads++;
    return profile;
  }

  @override
  Future<List<Product>> getProducts({String? query}) async {
    productReads++;
    return empty
        ? []
        : longCatalog
        ? List.generate(
            100,
            (index) =>
                _product.copyWith(id: 'coffee-$index', name: 'Coffee $index'),
          )
        : [_product];
  }

  @override
  Future<List<Receipt>> getRecentReceipts({
    int limit = 200,
    String? query,
  }) async => [];
  @override
  Future<Map<String, LatestProductCost>> getLatestProductCosts(
    Iterable<String> ids,
  ) async => {};
  @override
  Future<ProductComparisonData> getProductComparison(String id) async {
    comparisonReads++;
    if (failedComparison) throw Exception('read failed');
    return ProductComparisonData(
      product: _product,
      profile: profile,
      latestPrices: const [],
      history: const [],
    );
  }
}

Widget _app(Widget child) =>
    MaterialApp(theme: AppTheme.lightTheme, home: child);
Future<void> _pull(WidgetTester tester, Finder scroll) async {
  await tester.drag(scroll, const Offset(0, 450));
  await tester.pumpAndSettle();
}

void main() {
  for (final empty in [false, true]) {
    testWidgets(
      'Home pull refresh reads once with ${empty ? 'empty' : 'short'} data',
      (tester) async {
        final adapter = _Adapter()..empty = empty;
        await tester.pumpWidget(_app(DashboardScreen(dataAdapter: adapter)));
        await tester.pumpAndSettle();
        final tab = empty
            ? 'dashboard-receipts-list'
            : 'dashboard-products-list';
        expect(adapter.productReads, 1);
        await _pull(tester, find.byKey(PageStorageKey(tab)));
        expect(adapter.productReads, 2);
        expect(find.byIcon(Icons.refresh_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('long product list pull refresh triggers only at the top', (
    tester,
  ) async {
    final adapter = _Adapter()..longCatalog = true;
    await tester.pumpWidget(_app(DashboardScreen(dataAdapter: adapter)));
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('dashboard-products-list'));
    await tester.drag(list, const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(adapter.productReads, 1);
    for (var i = 0; i < 4; i++) {
      await tester.drag(list, const Offset(0, 350));
      await tester.pumpAndSettle();
      if (adapter.productReads > 1) break;
    }
    expect(adapter.productReads, 2);
    expect(find.byTooltip('Add product').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Settings pull keeps dirty fields while refreshing pristine fields',
    (tester) async {
      final adapter = _Adapter();
      await tester.pumpWidget(_app(ProfileScreen(dataAdapter: adapter)));
      await tester.pumpAndSettle();
      final name = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Store name',
      );
      final owner = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Owner name (optional)',
      );
      await tester.enterText(name, 'Unsaved store');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      adapter.profile = const StoreProfile(
        name: 'New saved store',
        ownerName: 'New saved owner',
        defaultMarkupPercent: 25,
      );
      await _pull(tester, find.byType(ListView));
      expect(adapter.profileReads, 2);
      expect(tester.widget<TextField>(name).controller!.text, 'Unsaved store');
      expect(
        tester.widget<TextField>(owner).controller!.text,
        'New saved owner',
      );
      expect(find.text('25%'), findsWidgets);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final error in [false, true]) {
    testWidgets(
      'Product pull refresh works with ${error ? 'error' : 'empty history'} and no restock feature',
      (tester) async {
        final adapter = _Adapter()..failedComparison = error;
        await tester.pumpWidget(
          _app(
            ProductComparisonScreen(
              dataAdapter: adapter,
              productId: _product.id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(adapter.comparisonReads, 1);
        await _pull(tester, find.byType(SingleChildScrollView).first);
        expect(adapter.comparisonReads, 2);
        expect(find.text('Plan restock & profit'), findsNothing);
        expect(find.byIcon(Icons.refresh_rounded), findsNothing);
        expect(find.text('Retry'), error ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
