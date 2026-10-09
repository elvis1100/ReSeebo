import 'package:flutter/material.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../widgets/receipt_scan_steps.dart';
import '../../suppliers/screens/supplier_editor_screen.dart';
import '../state/receipt_review_state.dart';
import '../widgets/duplicate_review_dialog.dart';
import '../widgets/line_item_editor_row.dart';
import '../widgets/overlap_review_card.dart';
import '../widgets/product_match_picker.dart';
import '../widgets/receipt_assignment_panel.dart';
import '../widgets/receipt_metadata_editor.dart';

class ReviewMatchScreen extends StatefulWidget {
  const ReviewMatchScreen({
    super.key,
    required this.dataAdapter,
    required this.initialDraft,
    this.onSaved,
    this.onBack,
  });
  final IReseeboDataAdapter dataAdapter;
  final ReceiptDraft initialDraft;
  final ValueChanged<SaveReceiptResult>? onSaved;
  final VoidCallback? onBack;
  @override
  State<ReviewMatchScreen> createState() => _ReviewMatchScreenState();
}

class _ReviewMatchScreenState extends State<ReviewMatchScreen> {
  late final ReceiptReviewState _review;
  final ScrollController _scroll = ScrollController();
  bool _showOriginal = true;
  bool _photosExpanded = false;
  double _returnOffset = 0;

  @override
  void initState() {
    super.initState();
    _review = ReceiptReviewState(
      adapter: widget.dataAdapter,
      draft: widget.initialDraft,
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
        ),
      ),
    );
    if (product == null || !mounted) return;
    await _review.load();
    if (!mounted) return;
    line.productId = product.id;
    _review.changed(line: line);
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

  void _selectTarget(ParsedLineItem line, ReceiptLineField field) {
    FocusScope.of(context).unfocus();
    _returnOffset = _scroll.hasClients ? _scroll.offset : 0;
    _showOriginal = false;
    _photosExpanded = true;
    _review.selectTarget(line.id, field);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _applySelection() {
    final issue = _review.assignText(_review.selectedText);
    if (issue != null) {
      _message(issue);
      return;
    }
    _message('Field filled. Check the item and confirm it below.');
  }

  Future<void> _save() async {
    if (_review.saving) return;
    FocusScope.of(context).unfocus();
    try {
      final result = await _review.save();
      if (!mounted) return;
      _message(
        result.alreadySaved
            ? 'Receipt already saved.'
            : 'Receipt saved to your ledger.',
      );
      widget.onSaved?.call(result);
    } on DuplicateReceiptException catch (duplicate) {
      if (!mounted) return;
      final separate = await showDialog<bool>(
        context: context,
        builder: (_) => DuplicateReviewDialog(
          adapter: widget.dataAdapter,
          receiptIds: duplicate.receiptIds,
        ),
      );
      if (separate == true && mounted) {
        _review.draft.allowDuplicate = true;
        await _save();
      }
    } catch (error) {
      if (mounted) _message(userMessage(error));
    }
  }

  Widget _photos() => ReceiptAssignmentPanel(
    review: _review,
    showOriginal: _showOriginal,
    onOriginalChanged: (value) => setState(() => _showOriginal = value),
    onApply: _applySelection,
    onReturn: () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _returnOffset.clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    },
  );

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
              enabled: !_review.saving,
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
            enabled: !_review.saving,
            selectedField: _review.targetLineId == line.id
                ? _review.targetField
                : null,
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
            onTargetSelected: (field) => _selectTarget(line, field),
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
          'Printed receipt total: ${pesos(_review.draft.detectedTotalCents!)}',
        ),
      if (_review.hasTotalDifference)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I checked the difference from the receipt total'),
          value: _review.draft.totalDifferenceConfirmed,
          onChanged: _review.saving
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review receipt'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _review.saving
              ? null
              : widget.onBack ?? () => Navigator.maybePop(context),
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
                        onTap: () =>
                            setState(() => _photosExpanded = !_photosExpanded),
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
                          'A few details need checking',
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
                    suppliers: _review.suppliers,
                    enabled: !_review.saving,
                    onChanged: () => _review.changed(),
                    onEditSupplier: _editSupplier,
                  ),
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
                      onPressed: _review.saving ? null : _review.addLine,
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
                    _review.saving || _review.loading || _review.error != null
                    ? null
                    : _save,
                icon: const Icon(Icons.save_alt),
                label: Text(_review.saving ? 'Saving...' : 'Save receipt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
