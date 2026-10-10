import 'models.dart';

/// Revision is the optimistic concurrency token for saving a pending correction.
/// Each access returns private editable evidence, never the stored snapshot.
class ConfirmedReceiptEdit {
  ConfirmedReceiptEdit({
    required this.receiptId,
    required this.revision,
    required ReceiptDraft draft,
  }) : _draft = draft.snapshot();
  final String receiptId;
  final int revision;
  final ReceiptDraft _draft;
  ReceiptDraft get draft => _draft.snapshot();
}

/// Prior evidence is immutable; recordedAt is the time this revision was archived.
class ReceiptRevision {
  ReceiptRevision({
    required this.revision,
    required this.recordedAt,
    required ReceiptDraft draft,
  }) : _draft = draft.snapshot();
  final int revision;
  final DateTime recordedAt;
  final ReceiptDraft _draft;
  ReceiptDraft get draft => _draft.snapshot();
}
