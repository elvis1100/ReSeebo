import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/services/receipt_snapshot_codec.dart';
import '../../receipt_scan/state/pending_receipt_save_command.dart';

/// Owns private editor input and optimistic revision tokens. A transport retry
/// retains the entire storage command; only changed input or explicit reload
/// creates another command. Confirmation has a separate ID bound to a revision.
class PendingReceiptController extends ChangeNotifier {
  PendingReceiptController(this.adapter);
  final IReseeboDataAdapter adapter;
  PendingReceipt? pending;
  ReceiptDraft? _draft;
  ReceiptDraft? get draft => _draft?.snapshot();
  Object? error;
  bool loading = false;
  bool saving = false;
  String? confirmedReceiptId;
  String? _pendingId;
  int? _revision;
  String? _correctionId;
  int? _baseConfirmedRevision;
  DateTime? _importedAt;
  DateTime get importedAt => _importedAt ?? DateTime.now();
  String? get pendingId => _pendingId;
  int? get expectedRevision => _revision;
  String? get correctionOfReceiptId => _correctionId;
  int? get expectedConfirmedRevision => _baseConfirmedRevision;
  PendingReceiptSaveCommand? _saveCommand;
  String? _saveFingerprint;
  String? _confirmationId;
  String? _confirmationPendingId;
  int? _confirmationRevision;
  bool _disposed = false;
  int _request = 0;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _clearCommands() {
    _saveCommand = null;
    _saveFingerprint = null;
    _confirmationId = null;
    _confirmationPendingId = null;
    _confirmationRevision = null;
  }

  Future<void> load(String id) async {
    if (_disposed || saving) return;
    final request = ++_request;
    loading = true;
    error = null;
    _changed();
    try {
      PendingReceipt? result;
      String? resolved;
      try {
        result = await adapter.getPendingReceipt(id);
      } on ValidationException {
        // Links also exist for active corrections. Only an absent pending row
        // permits using its retained confirmed link as the route destination.
        resolved = await adapter.resolveConfirmedReceiptId(id);
        if (resolved == null) rethrow;
      }
      if (_disposed || request != _request) return;
      pending = result;
      _draft = result?.draft;
      _pendingId = id;
      _revision = result?.revision;
      _correctionId = result?.correctionOfReceiptId;
      _baseConfirmedRevision = result?.baseConfirmedRevision;
      _importedAt = result?.createdAt;
      confirmedReceiptId = resolved;
      _clearCommands();
    } catch (failure) {
      if (!_disposed && request == _request) error = failure;
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        _changed();
      }
    }
  }

  void beginCorrection(
    ConfirmedReceiptEdit edit, {
    required DateTime importedAt,
  }) {
    if (_disposed || saving) return;
    _request++;
    pending = null;
    _pendingId = null;
    _revision = null;
    _correctionId = edit.receiptId;
    _baseConfirmedRevision = edit.revision;
    _draft = edit.draft;
    _importedAt = importedAt;
    confirmedReceiptId = null;
    error = null;
    loading = false;
    _clearCommands();
    _changed();
  }

  void retainDraft(ReceiptDraft value) {
    if (_disposed) return;
    _draft = value.snapshot();
    _changed();
  }

  void recordFailure(Object failure, ReceiptDraft value) {
    if (_disposed) return;
    _draft = value.snapshot();
    error = failure;
    _changed();
  }

  /// Adopts a successful Review save without regenerating its proposals. The
  /// next confirmation must use the storage result's ID/revision, not stale UI
  /// constructor context. Review retains its own frozen save command on retry.
  void acceptSaved(PendingSaveResult result, ReceiptDraft value) {
    if (_disposed) return;
    final now = DateTime.now();
    _draft = value.snapshot();
    _pendingId = result.id;
    _revision = result.revision;
    pending = PendingReceipt(
      id: result.id,
      revision: result.revision,
      createdAt: _importedAt ?? now,
      updatedAt: now,
      draft: value,
      correctionOfReceiptId: _correctionId,
      baseConfirmedRevision: _baseConfirmedRevision,
    );
    error = null;
    _changed();
  }

  Future<PendingSaveResult> save(ReceiptDraft value) async {
    if (_disposed || loading || saving) {
      throw const ValidationException(
        'Wait for this receipt to finish saving.',
      );
    }
    _draft = value.snapshot();
    final fingerprint = ReceiptSnapshotCodec().encode(_draft!);
    if (_saveCommand == null || fingerprint != _saveFingerprint) {
      _saveFingerprint = fingerprint;
      _saveCommand = PendingReceiptSaveCommand(
        draft: _draft!,
        pendingId: _pendingId,
        expectedRevision: _revision,
        correctionOfReceiptId: _correctionId,
        expectedConfirmedRevision: _baseConfirmedRevision,
      );
    }
    saving = true;
    error = null;
    _changed();
    try {
      final result = await _saveCommand!.submit(adapter);
      acceptSaved(result, value);
      return result;
    } catch (failure) {
      if (!_disposed) error = failure;
      rethrow;
    } finally {
      if (!_disposed) {
        saving = false;
        _changed();
      }
    }
  }

  Future<SaveReceiptResult> confirm() async {
    if (_disposed ||
        loading ||
        saving ||
        _pendingId == null ||
        _revision == null) {
      throw const ValidationException(
        'Save this receipt as Needs review first.',
      );
    }
    final id = _pendingId!;
    final revision = _revision!;
    if (_confirmationId == null ||
        _confirmationPendingId != id ||
        _confirmationRevision != revision) {
      _confirmationId = const Uuid().v4();
      _confirmationPendingId = id;
      _confirmationRevision = revision;
    }
    saving = true;
    error = null;
    _changed();
    try {
      final result = await adapter.confirmPendingReceipt(
        id,
        expectedRevision: revision,
        operationId: _confirmationId!,
      );
      if (!_disposed) confirmedReceiptId = result.receiptId;
      return result;
    } catch (failure) {
      if (!_disposed) error = failure;
      rethrow;
    } finally {
      if (!_disposed) {
        saving = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
