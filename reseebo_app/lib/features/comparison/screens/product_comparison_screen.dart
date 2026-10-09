import 'package:flutter/material.dart';
import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/shared_widgets.dart' show LocalPhoto;
import '../../catalog/screens/product_editor_screen.dart';
import '../../../core/widgets/app_card.dart';
import '../widgets/price_history_timeline.dart';
import '../widgets/supplier_comparison_table.dart';
import '../../receipts/screens/receipt_detail_screen.dart';

/// Screen allowing sari-sari store owners to compare prices for an identical
/// product across suppliers and track cost trends over time.
class ProductComparisonScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final String productId;
  final ValueChanged<String>? onReceiptTap;
  final VoidCallback? onBack;

  const ProductComparisonScreen({
    super.key,
    required this.dataAdapter,
    required this.productId,
    this.onReceiptTap,
    this.onBack,
  });

  @override
  State<ProductComparisonScreen> createState() =>
      _ProductComparisonScreenState();
}

class _ProductComparisonScreenState extends State<ProductComparisonScreen> {
  ProductComparisonData? _comparisonData;
  bool _isLoading = true;
  String? _errorMessage;
  bool _reading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadComparison();
  }

  void _openReceipt(String receiptId) {
    final callback = widget.onReceiptTap;
    if (callback != null) {
      callback(receiptId);
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptDetailScreen(
          adapter: widget.dataAdapter,
          receiptId: receiptId,
        ),
      ),
    );
  }

  Future<void> _loadComparison({bool refresh = false}) async {
    if (_reading) return;
    _reading = true;
    final request = ++_request;
    setState(() {
      if (!refresh) _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await widget.dataAdapter.getProductComparison(
        widget.productId,
      );
      if (mounted && request == _request) {
        setState(() {
          _comparisonData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _errorMessage = userMessage(e);
          _isLoading = false;
        });
      }
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _editProduct() async {
    final product = _comparisonData?.product;
    if (product == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProductEditorScreen(adapter: widget.dataAdapter, product: product),
      ),
    );
    if (mounted && saved == true) await _loadComparison();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _comparisonData?.product.displayName ?? 'Product details',
          style: AppTypography.headingMedium.copyWith(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (_comparisonData != null)
            IconButton(
              tooltip: 'Edit product',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editProduct,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: () => _loadComparison(refresh: true),
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null || _comparisonData == null) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.priceIncrease,
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                'Failed to load comparison',
                style: AppTypography.headingSmall,
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                _errorMessage ?? 'Product details not found.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: AppSpacing.m),
              AppButton(label: 'Retry', onPressed: _loadComparison),
            ],
          ),
        ),
      );
    }

    final data = _comparisonData!;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Details & Historical Best Banner
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalPhoto(
                      path: data.product.photoPath,
                      size: 68,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.product.displayName,
                            style: AppTypography.headingLarge.copyWith(
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Size: ${data.product.sizeUnit} • ${data.product.category.isEmpty ? "General Store Item" : data.product.category}',
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),

                // Lowest Historical Price Pill
                if (data.lowestHistoricalPrice != null)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s + 2),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.s),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lowest Historical Unit Cost: ${CurrencyFormatter.format(data.lowestHistoricalPrice!)} / pc',
                                style: AppTypography.tableCellNumber.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (data.lowestHistoricalSupplierName != null &&
                                  data.lowestHistoricalDate != null)
                                Text(
                                  'At ${data.lowestHistoricalSupplierName} on ${DateFormatter.format(data.lowestHistoricalDate!)}',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Multi-Supplier Comparison Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Supplier Prices',
                style: AppTypography.headingMedium,
              ),
              Text(
                '${data.supplierRows.length} suppliers',
                style: AppTypography.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          SupplierComparisonTable(
            rows: data.supplierRows,
            onReceiptTap: _openReceipt,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Price History Section
          Text('Purchase Price History', style: AppTypography.headingMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Track price hikes and drops recorded from your receipts',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.m),
          PriceHistoryTimeline(
            records: data.historyRows,
            onReceiptTap: _openReceipt,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
