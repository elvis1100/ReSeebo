import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';

class _ConflictAdapter extends MockReseeboDataAdapter {
  @override
  Future<List<Product>> getProducts({String? query}) async => [];
  @override
  Future<List<Supplier>> getSuppliers() async => [];
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String description, {
    String? supplierId,
  }) async => [];
  @override
  Future<PendingSaveResult> savePendingReceipt(
    ReceiptDraft draft, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  }) async => throw const RevisionConflictException();
}

void main() {
  testWidgets(
    'pending conflict handling keeps competing edits and saves disabled',
    (tester) async {
      final release = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewMatchScreen(
            dataAdapter: _ConflictAdapter(),
            initialDraft: ReceiptDraft(imagePaths: []),
            pendingId: 'pending',
            expectedRevision: 2,
            onPendingSaveError: (_, review) => release.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Needs review'));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save Needs review'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<PopScope>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isFalse,
      );
      release.complete(true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save Needs review'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'pending save conflict hook receives private owner edits and suppresses default error when handled',
    (tester) async {
      final initial = ReceiptDraft(
        imagePath: 'original.png',
        lines: [ParsedLineItem(description: 'Coffee')],
      );
      Object? capturedError;
      ReceiptDraft? capturedDraft;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewMatchScreen(
            dataAdapter: _ConflictAdapter(),
            initialDraft: initial,
            pendingId: 'pending',
            expectedRevision: 2,
            onPendingSaveError: (error, review) async {
              capturedError = error;
              capturedDraft = review.draft.snapshot();
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('description')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('description')),
        'Owner coffee',
      );
      await tester.pump();
      await tester.tap(find.text('Save Needs review'));
      await tester.pumpAndSettle();
      expect(capturedError, isA<RevisionConflictException>());
      expect(capturedDraft!.lines.single.description, 'Owner coffee');
      expect(initial.lines.single.description, 'Coffee');
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}
