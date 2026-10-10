import '../../../core/models/models.dart';
import '../../../core/models/ocr_engine.dart';

/// One completed engine run. Editable drafts never escape the private cache.
class ScanResult {
  ScanResult({
    required this.key,
    required this.engineId,
    ReceiptDraft? draft,
    this.error,
    required this.elapsedMs,
  }) : _draft = draft?.snapshot();

  final String key;
  final OcrEngineId engineId;
  final ReceiptDraft? _draft;
  final String? error;
  final int elapsedMs;

  ReceiptDraft? get draft => _draft?.snapshot();
}
