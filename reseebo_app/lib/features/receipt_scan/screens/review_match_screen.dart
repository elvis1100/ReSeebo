import 'package:flutter/material.dart';
import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/models/product.dart';
import '../../../core/models/purchase_line.dart';
import '../../../core/models/receipt.dart';
import '../../../core/models/supplier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_button.dart';
import '../widgets/alias_match_picker.dart';
import '../widgets/line_item_editor_row.dart';
import '../widgets/receipt_image_viewer.dart';

/// Screen allowing sari-sari store owners to inspect on-device OCR results,
/// verify pack-to-piece conversions, associate product aliases, and commit
/// atomically to the local SQLite ledger.
class ReviewMatchScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final ReceiptDraft initialDraft;
  final ValueChanged<SaveReceiptResult>? onSaved;
  final VoidCallback? onBack;

  const ReviewMatchScreen({
    super.key,
    required this.dataAdapter,
    required this.initialDraft,
    this.onSaved,
    this.onBack,
  });

  @override
  State<ReviewMatchScreen> createState() => _ReviewMatchScreenState();
}

class _ReviewMatchScreenState extends State<ReviewMatchScreen> {
  late List<ParsedLineItem> _lines;
  late DateTime _purchaseDate;
  late TextEditingController _receiptNumberController;
  late double _scannedTotal;
  Supplier? _selectedSupplier;
  List<Supplier> _allSuppliers = [];
  List<Product> _allProducts = [];
  Map<String, Product> _productsMap = {};
  bool _isSaving = false;
  bool _showReceiptImage = true;

  @override
  void initState() {
    super.initState();
    _lines = List.from(widget.initialDraft.lines);
    _purchaseDate = widget.initialDraft.purchaseDate;
    _receiptNumberController = TextEditingController(
      text: widget.initialDraft.receiptNumber ?? '',
    );
    _scannedTotal = widget.initialDraft.totalAmount;
    _loadSuppliersAndProducts();
  }

  @override
  void dispose() {
    _receiptNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliersAndProducts() async {
    final suppliers = await widget.dataAdapter.getSuppliers();
    final products = await widget.dataAdapter.getProducts();

    final pMap = <String, Product>{};
    for (final p in products) {
      pMap[p.id] = p;
    }

    Supplier? matched;
    if (widget.initialDraft.supplierName != null) {
      final target = widget.initialDraft.supplierName!.toLowerCase();
      matched = suppliers.cast<Supplier?>().firstWhere(
            (s) => s?.displayName.toLowerCase().contains(target) ?? false,
            orElse: () => null,
          );
    }

    if (mounted) {
      setState(() {
        _allSuppliers = suppliers;
        _allProducts = products;
        _productsMap = pMap;
        _selectedSupplier = matched ?? suppliers.firstOrNull;
      });
    }
  }

  double get _linesSum =>
      _lines.fold(0.0, (acc, item) => acc + (item.netAmount - item.discount));

  bool get _isBalanced => (_linesSum - _scannedTotal).abs() < 0.10;

  int get _unresolvedItemsCount =>
      _lines.where((l) => l.matchedProductId == null || l.netAmount <= 0).length;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _purchaseDate = picked);
    }
  }

  Future<void> _handleMatchProduct(int index) async {
    final currentLine = _lines[index];
    final suggestions =
        await widget.dataAdapter.matchAliases(currentLine.rawDescription);

    if (!mounted) return;

    final currentlySelected = currentLine.matchedProductId != null
        ? _productsMap[currentLine.matchedProductId]
        : null;

    final selected = await AliasMatchPicker.show(
      context,
      rawOcrText: currentLine.rawDescription,
      availableProducts: _allProducts,
      suggestions: suggestions,
      currentlySelected: currentlySelected,
    );

    if (selected != null && mounted) {
      setState(() {
        currentLine.matchedProductId = selected.id;
        currentLine.isAmbiguous = false;
        _productsMap[selected.id] = selected;
      });
    }
  }

  void _addNewBlankLine() {
    setState(() {
      _lines.add(
        ParsedLineItem(
          tempId: 'manual_${DateTime.now().millisecondsSinceEpoch}',
          rawDescription: 'MANUAL ENTRY',
          quantity: 1,
          piecesPerPack: 1,
          netAmount: 0.0,
        ),
      );
    });
  }

  Future<void> _saveReceipt() async {
    if (_unresolvedItemsCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.accent,
          content: Text(
            'Please match all items to a product before saving to your ledger.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedDraft = ReceiptDraft(
        localImagePath: widget.initialDraft.localImagePath,
        supplierId: _selectedSupplier?.id,
        supplierName: _selectedSupplier?.displayName ?? 'Saved Supplier',
        branchLocation: _selectedSupplier?.branchLocation,
        purchaseDate: _purchaseDate,
        receiptNumber: _receiptNumberController.text.trim().isEmpty
            ? null
            : _receiptNumberController.text.trim(),
        lines: _lines,
      );

      final result =
          await widget.dataAdapter.saveConfirmedReceipt(updatedDraft);

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            content: Text(
              'Receipt saved atomically! ${result.lineIds.length} prices recorded.',
            ),
          ),
        );
        widget.onSaved?.call(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.priceIncrease,
            content: Text('Failed to save receipt: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Review Scanned Receipt'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: _showReceiptImage ? 'Hide Receipt Image' : 'Show Receipt Image',
            icon: Icon(
              _showReceiptImage
                  ? Icons.photo_size_select_actual_rounded
                  : Icons.photo_size_select_actual_outlined,
            ),
            onPressed: () {
              setState(() => _showReceiptImage = !_showReceiptImage);
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Receipt image view (collapsible)
          if (_showReceiptImage)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.m,
                  AppSpacing.s,
                  AppSpacing.m,
                  0,
                ),
                child: ReceiptImageViewer(
                  imagePath: widget.initialDraft.localImagePath,
                  height: 200,
                ),
              ),
            ),

          // Header Card: Supplier, Date, Receipt Number
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt Information',
                      style: AppTypography.headingSmall.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: AppSpacing.s),

                    // Supplier selector
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.s),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Supplier>(
                              value: _selectedSupplier,
                              isExpanded: true,
                              items: _allSuppliers.map((s) {
                                return DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.displayName,
                                    style: AppTypography.bodyRegular,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() => _selectedSupplier = val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),

                    // Date & Receipt number row
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusS),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: AppSpacing.s),
                                Text(
                                  DateFormatter.format(_purchaseDate),
                                  style: AppTypography.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.tag_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: TextField(
                                  controller: _receiptNumberController,
                                  style: AppTypography.bodySmall,
                                  decoration: const InputDecoration(
                                    hintText: 'Receipt #',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 6,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Total validation & Balance banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.m,
                  vertical: AppSpacing.s,
                ),
                decoration: BoxDecoration(
                  color: _isBalanced
                      ? AppColors.priceCheaperBg
                      : AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                  border: Border.all(
                    color: _isBalanced
                        ? AppColors.priceCheaper.withValues(alpha: 0.3)
                        : AppColors.warning,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isBalanced
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      size: 18,
                      color: _isBalanced
                          ? AppColors.priceCheaper
                          : AppColors.accentDark,
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        _isBalanced
                            ? 'Lines sum matches scanned total: ${CurrencyFormatter.format(_linesSum)}'
                            : 'Lines sum: ${CurrencyFormatter.format(_linesSum)} (Scanned total: ${CurrencyFormatter.format(_scannedTotal)})',
                        style: AppTypography.caption.copyWith(
                          color: _isBalanced
                              ? AppColors.priceCheaper
                              : AppColors.accentDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Section header for lines
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.m,
                AppSpacing.m,
                AppSpacing.m,
                AppSpacing.s,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Line Items (${_lines.length})',
                    style: AppTypography.headingSmall,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Item'),
                    onPressed: _addNewBlankLine,
                  ),
                ],
              ),
            ),
          ),

          // Line items list
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final line = _lines[index];
                  final matchedProd = line.matchedProductId != null
                      ? _productsMap[line.matchedProductId]
                      : null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s),
                    child: LineItemEditorRow(
                      line: line,
                      matchedProduct: matchedProd,
                      index: index,
                      onSelectProduct: () => _handleMatchProduct(index),
                      onQuantityChanged: (q) {
                        setState(() {
                          line.quantity = q;
                        });
                      },
                      onPiecesPerPackChanged: (pcs) {
                        setState(() {
                          line.piecesPerPack = pcs;
                        });
                      },
                      onLineTotalChanged: (total) {
                        setState(() {
                          line.netAmount = total;
                        });
                      },
                      onRemove: () {
                        setState(() => _lines.removeAt(index));
                      },
                    ),
                  );
                },
                childCount: _lines.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

      // Bottom bar action guard
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              offset: const Offset(0, -4),
              blurRadius: 8,
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_unresolvedItemsCount > 0) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_unresolvedItemsCount unconfirmed or unassigned ${(_unresolvedItemsCount == 1) ? 'item' : 'items'}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.accentDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Total Amount', style: AppTypography.caption),
                        Text(
                          CurrencyFormatter.format(_linesSum),
                          style: AppTypography.priceHighlight,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AppButton(
                      label: _isSaving ? 'Saving...' : 'Save to Ledger',
                      icon: Icons.save_alt_rounded,
                      isLoading: _isSaving,
                      onPressed: _saveReceipt,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
