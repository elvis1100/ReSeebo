import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:reseebo_app/core/widgets/store_header.dart';
import 'package:reseebo_app/main.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/latest_product_cost.dart';
import 'package:reseebo_app/features/dashboard/widgets/stat_header.dart';

class _LongCatalogAdapter extends MockReseeboDataAdapter {
  final _catalog = List.generate(
    100,
    (index) => Product(
      id: 'catalog-$index',
      name: 'Everyday grocery product $index',
      brand: 'Grocery brand',
      variant: 'Original',
      size: '100 g',
    ),
  );
  @override
  Future<List<Product>> getProducts({String? query}) async => _catalog;
  @override
  Future<List<Receipt>> getRecentReceipts({
    int limit = 200,
    String? query,
  }) async => [];
  @override
  Future<Map<String, LatestProductCost>> getLatestProductCosts(
    Iterable<String> ids,
  ) async => {};
}

void main() {
  testWidgets('ReseeboApp boots and renders offline dashboard', (
    WidgetTester tester,
  ) async {
    // Build Reseebo and trigger a frame.
    await tester.pumpWidget(const ReseeboApp());
    await tester.pumpAndSettle();

    // Verify that the title and core dashboard controls are rendered.
    expect(find.text('Reseebo'), findsOneWidget);
    expect(find.text('Scan Receipt'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('Scan Receipt'),
      ),
      findsOneWidget,
    );
    final headerText = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(StoreHeader),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data);
    expect(headerText, ['Reseebo']);
    expect(find.byTooltip('Refresh data'), findsOneWidget);
    expect(find.byTooltip('Add product').hitTestable(), findsNothing);
    await tester.tap(find.text('Products (4)'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add product').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Recent Receipts (4)'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add product').hitTestable(), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(StoreHeader),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data),
      ['Reseebo'],
    );
    expect(find.byTooltip('Refresh settings'), findsOneWidget);
  });
  testWidgets(
    'saving settings preserves an existing hidden logo and zero markup',
    (tester) async {
      final adapter = MockReseeboDataAdapter();
      await adapter.updateStoreProfile(
        const StoreProfile(
          name: 'Original store',
          photoPath: 'existing-store-logo.jpg',
          defaultMarkupPercent: 0,
        ),
      );
      await tester.pumpWidget(ReseeboApp(dataAdapter: adapter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Store logo (optional)'), findsNothing);
      expect(find.byTooltip('Choose store logo'), findsNothing);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Store name',
        ),
        'Updated store',
      );
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      final saved = await adapter.getStoreProfile();
      expect(saved.storeName, 'Updated store');
      expect(saved.photoPath, 'existing-store-logo.jpg');
      expect(saved.defaultMarkupPercent, 0);
    },
  );
  testWidgets(
    'compact Home fits 360dp with larger text and keeps Add beside product search',
    (tester) async {
      await tester.runAsync(() async {
        await (FontLoader(
          'Inter',
        )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
      });
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ReseeboApp());
      await tester.pumpAndSettle();
      expect(find.text('Tracked Items'), findsNothing);
      final storeName = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text("Aling Nena's Sari-Sari Store"),
          matching: find.byType(RichText),
        ),
      );
      expect(storeName.didExceedMaxLines, isTrue);
      expect(storeName.overflow, TextOverflow.ellipsis);
      expect(find.text('Receipts'), findsNothing);
      await tester.tap(find.text('Products (4)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final search = tester.getRect(
        find.byKey(const ValueKey('dashboard-search')),
      );
      final add = tester.getRect(
        find.byKey(const ValueKey('dashboard-add-product')),
      );
      expect(add.left, greaterThan(search.right));
      expect((add.center.dy - search.center.dy).abs(), lessThan(1));
      expect(add.right, lessThanOrEqualTo(360));
      for (final label in ['Recent Receipts (4)', 'Products (4)']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(label),
            matching: find.byType(RichText),
          ),
        );
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout();
        expect(painter.width, lessThanOrEqualTo(paragraph.size.width));
        expect(painter.height, lessThanOrEqualTo(paragraph.size.height));
        painter.dispose();
      }
      expect(find.text('Add').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh data'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add product').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Recent Receipts (4)'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add product'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scrolling back reveals Home controls for long and empty product lists',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ReseeboApp(dataAdapter: _LongCatalogAdapter()));
      await tester.pumpAndSettle();
      final list = find.byKey(const PageStorageKey('dashboard-products-list'));
      final search = find.byKey(const ValueKey('dashboard-search'));
      expect(search.hitTestable(), findsOneWidget);
      await tester.drag(list, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsNothing);
      await tester.drag(list, const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsOneWidget);
      expect(find.byTooltip('Add product').hitTestable(), findsOneWidget);
      await tester.enterText(search, 'no-such-grocery');
      await tester.pumpAndSettle();
      expect(find.text('No matching products'), findsOneWidget);
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsNothing);
      await tester.drag(list, const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsOneWidget);
      expect(find.byTooltip('Add product').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add product'), findsNothing);
      expect(find.text('No matching receipts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rounded pill tabs and gradient store tile contain their press surfaces',
    (tester) async {
      await tester.pumpWidget(const ReseeboApp());
      await tester.pumpAndSettle();
      final surface = tester.widget<Material>(
        find.byKey(const ValueKey('dashboard-tabs-surface')),
      );
      expect(surface.clipBehavior, Clip.antiAlias);
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(
        tabs.splashBorderRadius,
        tabs.indicator is BoxDecoration
            ? (tabs.indicator! as BoxDecoration).borderRadius
            : null,
      );
      expect(tabs.dividerHeight, 0);
      expect(
        find.descendant(
          of: find.byType(StatHeader),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      final ink = tester.widget<Ink>(
        find.descendant(
          of: find.byType(StatHeader),
          matching: find.byType(Ink),
        ),
      );
      expect(
        (ink.decoration! as BoxDecoration).gradient,
        isA<LinearGradient>(),
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.text('Recent Receipts (4)')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await pointer.up();
      await tester.pumpAndSettle();
    },
  );
}
