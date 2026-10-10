import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/errors/app_exception.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/product_match_picker.dart';

class _RetryAdapter extends MockReseeboDataAdapter {
  int reads = 0;
  final retry = Completer<List<Product>>();

  @override
  Future<List<Product>> getProducts({String? query}) {
    reads++;
    if (reads == 1) {
      return Future.error(const AppException('Catalog unavailable.'));
    }
    return retry.future;
  }
}

void main() {
  testWidgets(
    'retry locks catalog actions and recovers without duplicate reads',
    (tester) async {
      final adapter = _RetryAdapter();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductMatchPicker(
              adapter: adapter,
              description: 'Coffee 26g',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Catalog unavailable.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(adapter.reads, 2);
      adapter.retry.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Catalog unavailable.'), findsNothing);
      expect(
        find.text('No matching products. Add the exact product above.'),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    },
  );
}
