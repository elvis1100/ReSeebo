import 'package:flutter/material.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../widgets/receipt_scan_steps.dart';
import '../widgets/receipt_save_preview.dart';
import '../../suppliers/screens/supplier_editor_screen.dart';
import '../state/receipt_review_state.dart';
import '../widgets/duplicate_review_dialog.dart';
import '../widgets/line_item_editor_row.dart';
import '../widgets/overlap_review_card.dart';
import '../widgets/product_match_picker.dart';
import '../widgets/receipt_photo_review_panel.dart';
import '../widgets/receipt_metadata_editor.dart';
import '../widgets/receipt_suggestion_label.dart';
import '../widgets/ocr_result_summary.dart';

class ReviewMatchScreen extends StatefulWidget {
  const ReviewMatchScreen({
    super.key,
    required this.dataAdapter,
    required this.initialDraft,
    this.onSaved,
    this.onPendingSaved,
    this.onDraftChanged,
    this.pendingId,
    this.expectedRevision,
    this.correctionOfReceiptId,
    this.expectedConfirmedRevision,
    this.onConfirmPending,
    this.onOpenPendingReceipt,
    this.preserveSuggestions,
    this.onPendingSaveError,
    this.importedAt,
    this.onBack,
  });
  final IReseeboDataAdapter dataAdapter;
  final ReceiptDraft initialDraft;
  final ValueChanged<SaveReceiptResult>? onSaved;
  final ValueChanged<PendingSaveResult>? onPendingSaved;

  /// Called once on returning to Photos, with a private editable snapshot.
  final ValueChanged<ReceiptDraft>? onDraftChanged;
  final String? pendingId;
  final int? expectedRevision;
  final String? correctionOfReceiptId;
  final int? expectedConfirmedRevision;

  /// Pending/correction confirmation must persist the current owner snapshot,
  /// then confirm that saved revision with its own frozen confirmation command.
  /// The screen holds competing edits/actions disabled until this hook finishes.
  final Future<SaveReceiptResult> Function(ReceiptReviewState)?
  onConfirmPending;
  final ValueChanged<String>? onOpenPendingReceipt;
  final bool? preserveSuggestions;

  /// Return true after handling a pending-save error to suppress the default
  /// notice. The screen remains busy while conflict resolution is open.
  final Future<bool> Function(Object, ReceiptReviewState)? onPendingSaveError;
  final DateTime? importedAt;
  final VoidCallback? onBack;
  @override
  State<ReviewMatchScreen> createState() => _ReviewMatchScreenState();
}

class _ReviewMatchScreenState extends State<ReviewMatchScreen> {
  late final ReceiptReviewState _review;
  final ScrollController _scroll = ScrollController();
  bool _photosExpanded = false;
  bool _confirming = false;
  bool _returnedSnapshot = false;
  bool _savedComplete = false;
  bool _savingConfirmed = false;
  bool _savingPending = false;
  bool get _isSaving => _review.saving || _savingConfirmed || _savingPending;

  bool get _requiresPendingConfirmation =>
      widget.pendingId != null || widget.correctionOfReceiptId != null;

  void _returnSnapshot() {
    if (_returnedSnapshot || _savedComplete) return;
    _returnedSnapshot = true;
    widget.onDraftChanged?.call(_review.draft.snapshot());
  }

  void _back() {
    if (_isSaving) return;
    if (_confirming) {
      setState(() => _confirming = false);
    } else {
      _returnSnapshot();
      (widget.onBack ?? () => Navigator.maybePop(context))();
    }
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    final issue = _review.problem;
    if (issue != null) {
      _message(issue);
      return;
    }
    setState(() => _confirming = true);
  }

  @override
  void initState() {
    super.initState();
    _review = ReceiptReviewState(
      adapter: widget.dataAdapter,
      draft: widget.initialDraft,
      pendingId: widget.pendingId,
      expectedRevision: widget.expectedRevision,
      correctionOfReceiptId: widget.correctionOfReceiptId,
      expectedConfirmedRevision: widget.expectedConfirmedRevision,
      preserveSuggestions: widget.preserveSuggestions,
      importedAt: widget.importedAt,
    )..addListener(_refresh);
    _review.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _review.removeListener(_refresh);
    _review.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _match(ParsedLineItem line) async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ProductMatchPicker(
          adapter: widget.dataAdapter,
          description: line.description,
          supplierId: _review.draft.supplierId,
        ),
      ),
    );
    if (product == null || !mounted) return;
    await _review.load();
    if (!mounted) return;
    _review.setProduct(line, product);
  }

  Future<void> _editSupplier(Supplier? supplier) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierEditorScreen(
          adapter: widget.dataAdapter,
          supplier: supplier,
        ),
      ),
    );
    if (saved == true && mounted) await _review.load();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_requiresPendingConfirmation && widget.onConfirmPending == null) {
      _message('Save Needs review, then confirm from the saved receipt.');
      return;
    }
    setState(() => _savingConfirmed = true);
    FocusScope.of(context).unfocus();
    try {
      final result = _requiresPendingConfirmation
          ? await widget.onConfirmPending!(_review)
          : await _review.save();
      if (!mounted) return;
      _message(
        result.alreadySaved
            ? 'Receipt already saved.'
            : 'Receipt saved to your ledger.',
      );
      _savedComplete = true;
      widget.onSaved?.call(result);
    } on DuplicateReceiptException catch (duplicate) {
      if (!mounted) return;
      final separate = await showDialog<bool>(
        context: context,
        builder: (_) => DuplicateReviewDialog(
          adapter: widget.dataAdapter,
          receiptIds: duplicate.receiptIds,
          onOpenPendingReceipt: widget.onOpenPendingReceipt,
        ),
      );
      if (separate == true && mounted) {
        _review.allowPendingDuplicate();
        setState(() => _savingConfirmed = false);
        await _save();
      }
    } catch (error) {
      if (mounted) _message(userMessage(error));
    } finally {
      if (mounted) setState(() => _savingConfirmed = false);
    }
  }

  Future<void> _savePending() async {
    if (_isSaving || _review.loading) return;
    setState(() => _savingPending = true);
    FocusScope.of(context).unfocus();
    try {
      final result = await _review.savePending();
      if (mounted) _message('Receipt saved · Needs review');
      if (mounted) {
        _savedComplete = true;
        widget.onPendingSaved?.call(result);
      }
    } on DuplicateReceiptException catch (duplicate) {
      if (!mounted) return;
      final separate = await showDialog<bool>(
        context: context,
        builder: (_) => DuplicateReviewDialog(
          adapter: widget.dataAdapter,
          receiptIds: duplicate.receiptIds,
          onOpenPendingReceipt: widget.onOpenPendingReceipt,
        ),
      );
      if (separate == true && mounted) {
        _review.allowPendingDuplicate();
        setState(() => _savingPending = false);
        await _savePending();
      }
    } catch (failure) {
      if (!mounted) return;
      try {
        final handled =
            await widget.onPendingSaveError?.call(failure, _review) ?? false;
        if (mounted && !handled) _message(userMessage(failure));
      } catch (hookFailure) {
        if (mounted) _message(userMessage(hookFailure));
      }
    } finally {
      if (mounted) setState(() => _savingPending = false);
    }
  }

  Widget _photos() => ReceiptPhotoReviewPanel(review: _review);

  Widget _line(ParsedLineItem line, int index) {
    final problem = _review.lineProblem(line);
    final earlier = _review.draft.lines
        .where((candidate) => candidate.id == line.possibleDuplicateOf)
        .firstOrNull;
    return Padding(
      key: ValueKey(line.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          if (line.possibleDuplicateOf != null)
            OverlapReviewCard(
              line: line,
              earlier: earlier,
              enabled: !_isSaving,
              onKeepBoth: () {
                line.possibleDuplicateOf = null;
                _review.changed(line: line);
              },
              onRemove: () => _review.removeLine(line),
            ),
          LineItemEditorRow(
            key: ValueKey('editor-${line.id}'),
            line: line,
            index: index,
            matchedProduct: _review.productFor(line.productId),
            problem: problem,
            enabled: !_isSaving,
            onSelectProduct: () => _match(line),
            onQuantityChanged: (quantity) => _review.editText(
              line,
              ReceiptLineField.quantity,
              quantity.toInt().toString(),
            ),
            onPiecesPerPackChanged: (pieces) => _review.editText(
              line,
              ReceiptLineField.piecesPerPack,
              pieces.toString(),
            ),
            onLineTotalChanged: (amount) => _review.editText(
              line,
              ReceiptLineField.amount,
              amount.toStringAsFixed(2),
            ),
            onFieldEdited: (field, value) =>
                _review.editText(line, field, value),
            onUnitChanged: (unit) => _review.setUnit(line, unit),
            onRemove: () => _review.removeLine(line),
            onConfirm: () {
              if (line.confirmed) {
                line.confirmed = false;
                _review.changed(line: line);
              } else {
                final issue = _review.lineProblem(
                  line,
                  requireConfirmation: false,
                );
                if (issue != null) {
                  _message(issue);
                  return;
                }
                _review.confirmLine(line);
              }
            },
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.product],
            fieldLabel: 'Product',
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.quantity],
            fieldLabel: 'Quantity',
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.unit],
            fieldLabel: 'Unit',
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.piecesPerPack],
            fieldLabel: 'Pack contents',
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.amount],
            fieldLabel: 'Amount',
            detail:
                line.extractedUnitPriceCents != null && line.quantity != null
                ? '${pesos(line.extractedUnitPriceCents!)} × ${line.quantity}'
                : null,
          ),
          if (!line.confirmed && line.costPerPieceCents != null)
            Text(
              'Provisional cost per piece: ${pesos(line.costPerPieceCents!)}',
            ),
        ],
      ),
    );
  }

  Widget _totals() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Total paid: ${_review.lineTotalCents == null ? 'Check line amounts' : pesos(_review.lineTotalCents!)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (_review.draft.detectedTotalCents != null)
        Text(
          '${receiptTotalLabel(_review.draft)}: ${pesos(_review.draft.detectedTotalCents!)}',
        ),
      ReceiptSuggestionLabel(
        provenance: _review.draft.provenance[ReceiptMetadataField.total],
      ),
      if (_review.hasTotalDifference)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I checked the difference from the receipt total'),
          value: _review.draft.totalDifferenceConfirmed,
          onChanged: _isSaving
              ? null
              : (value) {
                  _review.draft.totalDifferenceConfirmed = value ?? false;
                  _review.changed();
                },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final draft = _review.draft;
    return PopScope(
      canPop: !_confirming && !_isSaving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _returnSnapshot();
        } else if (!_isSaving) {
          _back();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_confirming ? 'Confirm receipt' : 'Review receipt'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _isSaving ? null : _back,
          ),
        ),
        body: _review.loading
            ? const Center(child: CircularProgressIndicator())
            : _review.error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_review.error!),
                    TextButton(
                      onPressed: _review.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _confirming
            ? ReceiptSavePreview(review: _review, onBack: _back)
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  const ReceiptScanSteps(activeStep: 1),
                  const SizedBox(height: 20),
                  Text(
                    'Let’s check your receipt',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Check where you bought the items, then confirm each product and amount.',
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.receipt_long_outlined,
                            color: AppColors.primary,
                          ),
                          title: const Text('Receipt photos'),
                          subtitle: Text(
                            '${_review.pages.length} photo${_review.pages.length == 1 ? '' : 's'} · Check the original anytime',
                          ),
                          trailing: Icon(
                            _photosExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          onTap: () => setState(
                            () => _photosExpanded = !_photosExpanded,
                          ),
                        ),
                        if (_photosExpanded) _photos(),
                      ],
                    ),
                  ),
                  if (draft.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    AppCard(
                      backgroundColor: AppColors.softAmber,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Please check',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          for (final warning in draft.warnings)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                warning,
                                style: const TextStyle(
                                  color: AppColors.amberText,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppCard(
                    child: ReceiptMetadataEditor(
                      draft: draft,
                      onSupplierChanged: _review.refreshDateSuggestion,
                      onDateCandidate: (candidate, remember) => _review
                          .chooseDateCandidate(candidate, remember: remember),
                      suppliers: _review.suppliers,
                      enabled: !_isSaving,
                      onChanged: () => _review.changed(),
                      onEditSupplier: _editSupplier,
                    ),
                  ),
                  ReceiptSuggestionLabel(
                    provenance: draft.provenance[ReceiptMetadataField.supplier],
                    fieldLabel: 'Supplier',
                  ),
                  ReceiptSuggestionLabel(
                    provenance:
                        draft.provenance[ReceiptMetadataField.purchasedAt],
                    fieldLabel: 'Purchase date',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Items (${draft.lines.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _isSaving ? null : _review.addLine,
                        icon: const Icon(Icons.add),
                        label: const Text('Add item'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '${_review.confirmedCount} of ${draft.lines.length} items checked',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Unmatched items are added to your catalog when saved.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  if (draft.lines.isEmpty)
                    const AppCard(
                      child: Column(
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            size: 36,
                            color: AppColors.primary,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No items found yet',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap Add item to enter a product from your receipt.',
                          ),
                        ],
                      ),
                    ),
                  ...draft.lines.indexed.map(
                    (entry) => _line(entry.$2, entry.$1),
                  ),
                  AppCard(
                    backgroundColor: AppColors.softPrimary,
                    child: _totals(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_review.loading && _review.problem != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _review.problem!,
                      style: const TextStyle(color: AppColors.amberText),
                    ),
                  ),
                FilledButton.icon(
                  onPressed:
                      _isSaving ||
                          _review.loading ||
                          _review.error != null ||
                          (_confirming &&
                              _requiresPendingConfirmation &&
                              widget.onConfirmPending == null)
                      ? null
                      : _confirming
                      ? _save
                      : _continue,
                  icon: Icon(
                    _confirming ? Icons.save_alt : Icons.arrow_forward,
                  ),
                  label: Text(
                    _isSaving
                        ? 'Saving...'
                        : _confirming
                        ? 'Save receipt'
                        : 'Continue to save',
                  ),
                ),
                if (_confirming &&
                    _requiresPendingConfirmation &&
                    widget.onConfirmPending == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Save Needs review, then confirm from the saved receipt.',
                    ),
                  ),
                if (!_confirming) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _isSaving || _review.loading || _review.error != null
                        ? null
                        : _savePending,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Save Needs review'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
