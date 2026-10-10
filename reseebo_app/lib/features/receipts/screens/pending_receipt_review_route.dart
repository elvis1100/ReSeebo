import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../receipt_scan/screens/review_match_screen.dart';
import '../../receipt_scan/state/receipt_review_state.dart';
import '../state/pending_receipt_controller.dart';

class PendingReviewOutcome {
  const PendingReviewOutcome({this.saved, this.confirmed, this.reload = false});
  final PendingSaveResult? saved;
  final SaveReceiptResult? confirmed;
  final bool reload;
}

/// Both imports and corrections use the existing editor. Its pending command
/// owns the save retry; the controller owns the distinct confirmation retry.
Future<PendingReviewOutcome?> openPendingReceiptReview(
  BuildContext context, {
  required PendingReceiptController controller,
  required ValueChanged<String> onOpenPendingReceipt,
}) async {
  final draft = controller.draft;
  if (draft == null) return null;
  return Navigator.of(context).push<PendingReviewOutcome>(
    MaterialPageRoute(
      builder: (routeContext) {
        Future<bool> handleFailure(
          Object failure,
          ReceiptReviewState review,
        ) async {
          controller.recordFailure(failure, review.draft);
          if (failure is! RevisionConflictException) return false;
          final reload = await showDialog<bool>(
            context: routeContext,
            builder: (dialogContext) => AlertDialog(
              title: const Text('This receipt changed'),
              content: const Text(
                'Your unsaved input is kept. Keep editing to compare or copy your changes. Reloading replaces these fields with the current saved receipt.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Keep editing'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Reload current receipt'),
                ),
              ],
            ),
          );
          if (reload == true && routeContext.mounted) {
            Navigator.pop(
              routeContext,
              const PendingReviewOutcome(reload: true),
            );
          }
          return true;
        }

        return ReviewMatchScreen(
          dataAdapter: controller.adapter,
          initialDraft: draft,
          pendingId: controller.pendingId,
          expectedRevision: controller.expectedRevision,
          correctionOfReceiptId: controller.correctionOfReceiptId,
          expectedConfirmedRevision: controller.expectedConfirmedRevision,
          preserveSuggestions: true,
          importedAt: controller.importedAt,
          onDraftChanged: controller.retainDraft,
          onOpenPendingReceipt: onOpenPendingReceipt,
          onPendingSaveError: handleFailure,
          onPendingSaved: (result) {
            // The editor reports the submitted snapshot through its own save
            // result. Reloading the pending route retrieves durable media paths.
            if (routeContext.mounted) {
              Navigator.pop(routeContext, PendingReviewOutcome(saved: result));
            }
          },
          onConfirmPending: (review) async {
            try {
              final saved = await review.savePending();
              controller.acceptSaved(saved, review.draft);
              return await controller.confirm();
            } catch (failure) {
              await handleFailure(failure, review);
              rethrow;
            }
          },
          onSaved: (result) {
            if (routeContext.mounted) {
              Navigator.pop(
                routeContext,
                PendingReviewOutcome(confirmed: result),
              );
            }
          },
        );
      },
    ),
  );
}
