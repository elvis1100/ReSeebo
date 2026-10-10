import 'models.dart';

/// Pixel bounds and digest describe these exact encoded bytes, never a newly
/// regenerated crop. Preprocessing identity is retained for coordinate evidence.
class ReceiptImageReference {
  const ReceiptImageReference({
    required this.path,
    required this.sha256,
    required this.width,
    required this.height,
    required this.preprocessingIdentity,
  });
  final String path;
  final String sha256;
  final int width;
  final int height;
  final String preprocessingIdentity;
}

class ReceiptPageMedia {
  const ReceiptPageMedia({
    required this.original,
    this.recognition,
    this.comparison,
  });
  final ReceiptImageReference original;
  final ReceiptImageReference? recognition;
  final ReceiptImageReference? comparison;
}

/// Returning a private draft prevents consumers from mutating a stored revision.
class PendingReceipt {
  PendingReceipt({
    required this.id,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required ReceiptDraft draft,
    this.correctionOfReceiptId,
    this.baseConfirmedRevision,
  }) : _draft = draft.snapshot();
  final String id;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ReceiptDraft _draft;
  ReceiptDraft get draft => _draft.snapshot();
  final String? correctionOfReceiptId;
  final int? baseConfirmedRevision;
}

class PendingSaveResult {
  const PendingSaveResult({
    required this.id,
    required this.revision,
    this.alreadySaved = false,
  });
  final String id;
  final int revision;
  final bool alreadySaved;
}

enum LedgerEntryStatus { confirmed, needsReview }

/// A pending correction keeps the confirmed entry's ID and recorded time;
/// pendingId routes to its edit while confirmedReceiptId identifies the purchase.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.status,
    required this.recordedAt,
    required this.supplierDisplay,
    this.provisionalTotalCents,
    this.confirmedReceiptId,
    this.pendingId,
  });
  final String id;
  final LedgerEntryStatus status;
  final DateTime recordedAt;
  final String supplierDisplay;
  final int? provisionalTotalCents;
  final String? confirmedReceiptId;
  final String? pendingId;
}
