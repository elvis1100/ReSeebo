import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../suppliers/screens/supplier_editor_screen.dart';
import '../state/receipt_review_state.dart';
import '../widgets/duplicate_review_dialog.dart';
import '../widgets/line_item_editor.dart';
import '../widgets/receipt_image_viewer.dart';
import '../widgets/receipt_metadata_editor.dart';
import '../widgets/overlap_review_card.dart';
import '../widgets/recognized_text_card.dart';

class ReviewMatchScreen extends StatefulWidget {
  const ReviewMatchScreen({
    super.key,
    required this.adapter,
    required this.draft,
  });
  final IReseeboDataAdapter adapter;
  final ReceiptDraft draft;
  @override
  State<ReviewMatchScreen> createState() => _ReviewMatchScreenState();
}

class _ReviewMatchScreenState extends State<ReviewMatchScreen> {
  late final ReceiptReviewState _state;
  final _form = GlobalKey<FormState>();
  bool _saveFlowBusy = false;
  bool _canLeave = false;
  bool _exitDialogOpen = false;
  String? _saveError;
  final _metadataKey = GlobalKey();
  final _lineKeys = <String, GlobalKey>{};

  Future<void> _showProblem() async {
    FocusScope.of(context).unfocus();
    var target = _metadataKey.currentContext;
    if (_state.draft.supplierName.trim().isNotEmpty &&
        _state.draft.dateConfirmed) {
      for (final line in _state.draft.lines) {
        if (_state.lineProblem(line) != null) {
          target = _lineKeys[line.id]?.currentContext;
          break;
        }
      }
    }
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _state = ReceiptReviewState(adapter: widget.adapter, draft: widget.draft);
    _state.load();
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    if (_saveFlowBusy || _state.loading) return;
    final fieldsValid = _form.currentState!.validate();
    final issue = _state.problem;
    if (!fieldsValid || issue != null) {
      _message(issue ?? 'Check the highlighted receipt fields.');
      await _showProblem();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saveFlowBusy = true;
      _saveError = null;
    });
    try {
      while (mounted) {
        try {
          final saved = await _state.save();
          if (!mounted) return;
          setState(() {
            _canLeave = true;
            _saveFlowBusy = false;
          });
          Navigator.pop(context, saved);
          return;
        } on DuplicateReceiptException catch (duplicate) {
          if (!mounted) return;
          final separate = await showDialog<bool>(
            context: context,
            builder: (_) => DuplicateReviewDialog(
              adapter: widget.adapter,
              receiptIds: duplicate.receiptIds,
            ),
          );
          if (separate != true || !mounted) break;
          _state.draft.allowDuplicate = true;
        }
      }
    } catch (error) {
      if (mounted) setState(() => _saveError = userMessage(error));
    } finally {
      if (mounted) setState(() => _saveFlowBusy = false);
    }
  }

  Future<void> _requestExit() async {
    if (_saveFlowBusy || _exitDialogOpen) return;
    _exitDialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard receipt review?'),
        content: const Text(
          'Your review edits have not been saved. You can return to the photo and recognize it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard review'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (discard == true && mounted) {
      setState(() => _canLeave = true);
      Navigator.pop(context);
    }
  }

  Future<void> _removeLine(ParsedLineItem line) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove purchase line?'),
        content: Text(
          line.description.isEmpty
              ? 'This line will be removed from the draft.'
              : '“${line.description}” will be removed from this draft. It will not become purchase history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep line'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove line'),
          ),
        ],
      ),
    );
    if (remove == true && mounted) _state.removeLine(line);
  }

  Future<void> _editSupplier(Supplier? supplier) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SupplierEditorScreen(adapter: widget.adapter, supplier: supplier),
      ),
    );
    if (saved == true && mounted) await _state.load();
  }

  Widget _overlap(ParsedLineItem line, bool busy) {
    final earlier = _state.draft.lines
        .where((item) => item.id == line.possibleDuplicateOf)
        .firstOrNull;
    return OverlapReviewCard(
      line: line,
      earlier: earlier,
      enabled: !busy,
      onKeepBoth: () {
        line.possibleDuplicateOf = null;
        _state.changed(line: line, affectsTotal: true);
      },
      onRemove: () => _removeLine(line),
    );
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final draft = _state.draft;
      final busy = _saveFlowBusy || _state.saving;
      return PopScope(
        canPop: _canLeave && !busy,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _requestExit();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back to receipt photo',
              onPressed: busy ? null : _requestExit,
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('Review & match'),
            actions: [
              IconButton(
                tooltip: 'View original receipt',
                onPressed: busy
                    ? null
                    : () => openReceiptImages(context, draft.imagePaths),
                icon: const Icon(Icons.image_outlined),
              ),
            ],
          ),
          body: _state.loading
              ? const Center(child: CircularProgressIndicator())
              : _state.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_state.error!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _state.load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Notice(
                        message:
                            '${draft.lines.where((line) => line.confirmed).length} of ${draft.lines.length} purchase lines confirmed · ${draft.imagePaths.length} original photos',
                      ),
                      if (_state.problem != null) ...[
                        const SizedBox(height: 8),
                        Notice(message: _state.problem!, warning: true),
                        TextButton(
                          onPressed: busy ? null : _showProblem,
                          child: const Text('Go to first field to check'),
                        ),
                      ],
                      ReceiptImagesPreview(
                        paths: draft.imagePaths,
                        enabled: !busy,
                      ),
                      RecognizedTextCard(text: draft.rawText, enabled: !busy),
                      const SizedBox(height: 8),
                      if (draft.warnings.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              draft.warnings.join('\n'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Recognition creates a draft. Check the original and explicitly confirm each purchase line before saving.',
                        ),
                      ),
                      ReceiptMetadataEditor(
                        key: _metadataKey,
                        draft: draft,
                        suppliers: _state.suppliers,
                        enabled: !busy,
                        onChanged: _state.changed,
                        onEditSupplier: _editSupplier,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Purchase lines',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (draft.lines.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'No purchase lines recognized. Add them from the original receipt.',
                          ),
                        ),
                      for (
                        var index = 0;
                        index < draft.lines.length;
                        index++
                      ) ...[
                        if (draft.lines[index].possibleDuplicateOf != null)
                          _overlap(draft.lines[index], busy),
                        LineItemEditor(
                          key: _lineKeys.putIfAbsent(
                            draft.lines[index].id,
                            () => GlobalKey(),
                          ),
                          adapter: widget.adapter,
                          line: draft.lines[index],
                          index: index,
                          pageCount: draft.imagePaths.length,
                          problem: _state.lineProblem(draft.lines[index]),
                          product: _state.productFor(
                            draft.lines[index].productId,
                          ),
                          enabled: !busy,
                          onChanged: () => _state.changed(
                            line: draft.lines[index],
                            affectsTotal: true,
                          ),
                          onProductSelected: (product) {
                            if (_state.productFor(product.id) == null) {
                              _state.products.add(product);
                            }
                            draft.lines[index].productId = product.id;
                            _state.changed(line: draft.lines[index]);
                          },
                          onRemove: () => _removeLine(draft.lines[index]),
                          onConfirmationChanged: (confirmed) {
                            final line = draft.lines[index];
                            if (!confirmed) {
                              _state.changed(line: line);
                              return;
                            }
                            final issue = _state.lineProblem(
                              line,
                              requireConfirmation: false,
                            );
                            if (issue != null) {
                              _message(issue);
                            } else {
                              _state.confirmLine(line);
                            }
                          },
                        ),
                      ],
                      OutlinedButton.icon(
                        onPressed: busy ? null : _state.addLine,
                        icon: const Icon(Icons.add),
                        label: const Text('Add purchase line'),
                      ),
                      const SizedBox(height: 20),
                      if (_state.lineTotalCents != null)
                        Text(
                          'Reviewed net total: ${pesos(_state.lineTotalCents!)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      if (draft.detectedTotalCents != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Detected receipt total: ${pesos(draft.detectedTotalCents!)}',
                          ),
                        ),
                      if (_state.hasTotalDifference)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: draft.totalDifferenceConfirmed,
                          title: const Text(
                            'I checked the difference. The confirmed line amounts are correct.',
                          ),
                          subtitle: const Text(
                            'Receipt charges, taxes or discounts may need manual review.',
                          ),
                          onChanged: busy
                              ? null
                              : (value) {
                                  draft.totalDifferenceConfirmed =
                                      value ?? false;
                                  _state.changed();
                                },
                        ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                      if (_state.problem != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _state.problem!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_saveError != null) ...[
                        Notice(message: _saveError!, warning: true),
                        const SizedBox(height: 12),
                      ],
                      AppActionButton(
                        label: 'Save confirmed purchase',
                        busyLabel: 'Saving purchase…',
                        busy: busy,
                        onPressed: _save,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      );
    },
  );
}
