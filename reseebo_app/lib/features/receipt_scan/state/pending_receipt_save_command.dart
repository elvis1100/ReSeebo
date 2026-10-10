import 'package:uuid/uuid.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';

/// One immutable storage request. Transport failures and unchanged repeated
/// taps reuse every payload/context field, even after a successful response.
/// A caller creates another command only when the owner changes the draft.
class PendingReceiptSaveCommand {
  PendingReceiptSaveCommand({
    required ReceiptDraft draft,
    this.pendingId,
    this.expectedRevision,
    this.correctionOfReceiptId,
    this.expectedConfirmedRevision,
  }) : _draft = draft.snapshot(),
       operationId = const Uuid().v4();

  final ReceiptDraft _draft;
  final String operationId;
  final String? pendingId;
  final int? expectedRevision;
  final String? correctionOfReceiptId;
  final int? expectedConfirmedRevision;

  Future<PendingSaveResult> submit(IReseeboDataAdapter adapter) =>
      adapter.savePendingReceipt(
        _draft.snapshot(),
        operationId: operationId,
        pendingId: pendingId,
        expectedRevision: expectedRevision,
        correctionOfReceiptId: correctionOfReceiptId,
        expectedConfirmedRevision: expectedConfirmedRevision,
      );
}
