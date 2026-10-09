import 'package:flutter/material.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../catalog/screens/product_editor_screen.dart';
import '../../planner/widgets/profit_calculator_card.dart';
import '../../planner/widgets/restock_planner_card.dart';
import '../../receipts/screens/receipt_detail_screen.dart';
import '../state/comparison_controller.dart';
import '../widgets/comparison_sections.dart';
import '../widgets/supplier_comparison.dart';

class ProductComparisonScreen extends StatefulWidget {
  const ProductComparisonScreen({
    super.key,
    required this.adapter,
    required this.productId,
  });
  final IReseeboDataAdapter adapter;
  final String productId;
  @override
  State<ProductComparisonScreen> createState() =>
      _ProductComparisonScreenState();
}

class _ProductComparisonScreenState extends State<ProductComparisonScreen> {
  late final controller = ComparisonController(
    widget.adapter,
    widget.productId,
  );
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final product = controller.data?.product;
    if (product == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProductEditorScreen(adapter: widget.adapter, product: product),
      ),
    );
    if (mounted && saved == true) await controller.load(resetPricing: true);
  }

  Future<void> _receipt(String id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReceiptDetailScreen(adapter: widget.adapter, receiptId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Compare & calculate'),
          actions: [
            IconButton(
              tooltip: 'Edit product and pricing',
              onPressed: controller.loading || controller.data == null
                  ? null
                  : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Prices & history'),
              Tab(text: 'Pricing & restock'),
            ],
          ),
        ),
        body: controller.loading
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading recorded prices',
                ),
              )
            : controller.error != null
            ? ErrorState(
                message: userMessage(controller.error!),
                onRetry: controller.load,
              )
            : TabBarView(children: [_prices(context), _calculations(context)]),
      ),
    ),
  );

  Widget _empty() => const EmptyState(
    icon: Icons.compare_arrows_outlined,
    title: 'No purchase prices yet',
    message:
        'Save a confirmed receipt containing this exact brand, variant, and size to compare buying costs.',
  );

  Widget _prices(BuildContext context) {
    final data = controller.data!;
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        key: const PageStorageKey('comparison-prices'),
        padding: AppSpacing.page,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ProductSummaryCard(product: data.product, onEdit: _edit),
          const SizedBox(height: AppSpacing.xl),
          if (data.latestPrices.isEmpty)
            _empty()
          else ...[
            SupplierComparison(
              rows: data.latestPrices,
              selectedSupplierId: controller.selectedSupplierId,
              onSelect: controller.chooseSupplier,
              onReceipt: _receipt,
            ),
            if (data.lowestHistorical != null)
              HistoricalLowCard(
                purchase: data.lowestHistorical!,
                onReceipt: _receipt,
              ),
            const SizedBox(height: AppSpacing.xl),
            ComparisonHistorySection(
              controller: controller,
              onReceipt: _receipt,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _calculations(BuildContext context) {
    final data = controller.data!;
    return ListView(
      key: const PageStorageKey('comparison-calculators'),
      padding: AppSpacing.page,
      children: [
        ProductSummaryCard(product: data.product, onEdit: _edit),
        const SizedBox(height: AppSpacing.xl),
        if (data.latestPrices.isEmpty)
          _empty()
        else ...[
          DropdownButtonFormField<String>(
            key: ValueKey(controller.selectedSupplierId),
            initialValue: controller.selectedSupplierId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Supplier cost to use',
            ),
            items: data.latestPrices
                .map(
                  (row) => DropdownMenuItem(
                    value: row.purchase.supplier.id,
                    child: Text(
                      row.purchase.supplier.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id != null) controller.chooseSupplier(id);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          ProfitCalculatorCard(controller: controller),
          const SizedBox(height: AppSpacing.xl),
          RestockPlannerCard(controller: controller),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
