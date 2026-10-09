import 'package:flutter/material.dart';
import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../widgets/product_catalog_item.dart';
import '../widgets/receipt_list_item.dart';
import '../widgets/stat_header.dart';

/// Main hub of Reseebo providing store owners quick access to recent
/// scanned receipts, tracked product prices, and fast scanning actions.
class DashboardScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final VoidCallback? onScanPressed;
  final VoidCallback? onSettingsPressed;
  final ValueChanged<Receipt>? onReceiptSelected;
  final ValueChanged<Product>? onProductSelected;

  const DashboardScreen({
    super.key,
    required this.dataAdapter,
    this.onScanPressed,
    this.onSettingsPressed,
    this.onReceiptSelected,
    this.onProductSelected,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  StoreProfile? _storeProfile;
  List<Receipt> _receipts = [];
  List<Product> _products = [];
  Map<String, Supplier> _suppliersMap = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final profile = await widget.dataAdapter.getStoreProfile();
    final receipts = await widget.dataAdapter.getRecentReceipts();
    final products = await widget.dataAdapter.getProducts();
    final suppliers = await widget.dataAdapter.getSuppliers();

    final map = <String, Supplier>{};
    for (final s in suppliers) {
      map[s.id] = s;
    }

    if (mounted) {
      setState(() {
        _storeProfile = profile;
        _receipts = receipts;
        _products = products;
        _suppliersMap = map;
        _isLoading = false;
      });
    }
  }

  List<Receipt> get _filteredReceipts {
    if (_searchQuery.isEmpty) return _receipts;
    return _receipts.where((r) {
      final supplier =
          _suppliersMap[r.supplierId]?.displayName.toLowerCase() ?? '';
      final receiptNum = r.receiptNumber.toLowerCase();
      return supplier.contains(_searchQuery) ||
          receiptNum.contains(_searchQuery);
    }).toList();
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    return _products.where((p) {
      final name = p.displayTitle.toLowerCase();
      final cat = p.category.toLowerCase();
      return name.contains(_searchQuery) || cat.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Reseebo',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh data',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.m,
                        AppSpacing.s,
                        AppSpacing.m,
                        AppSpacing.xs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_storeProfile != null)
                            StatHeader(
                              profile: _storeProfile!,
                              totalReceipts: _receipts.length,
                              totalProducts: _products.length,
                              onSettingsTap: widget.onSettingsPressed,
                            ),
                          const SizedBox(height: AppSpacing.m),
                          TextField(
                            controller: _searchController,
                            style: AppTypography.bodyRegular,
                            decoration: InputDecoration(
                              hintText: 'Search products or suppliers...',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.m),
                          // Modern segmented pill tab bar
                          Container(
                            height: 40,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              labelColor: AppColors.textPrimary,
                              unselectedLabelColor: AppColors.textSecondary,
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(AppSpacing.radiusXs + 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              labelStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              unselectedLabelStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              tabs: [
                                Tab(
                                  text: 'Recent Receipts (${_filteredReceipts.length})',
                                ),
                                Tab(
                                  text: 'Products (${_filteredProducts.length})',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: true,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildReceiptsTab(),
                        _buildProductsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.document_scanner_rounded, size: 20),
        label: const Text(
          'Scan Receipt',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
        onPressed: widget.onScanPressed,
      ),
    );
  }

  Widget _buildReceiptsTab() {
    if (_filteredReceipts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.receipt_outlined,
                size: 40,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.s),
              const Text(
                'No receipts recorded yet',
                style: AppTypography.headingSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Scan wholesale delivery receipts to start comparing prices.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      itemCount: _filteredReceipts.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.s),
      itemBuilder: (context, index) {
        final receipt = _filteredReceipts[index];
        final supplier = _suppliersMap[receipt.supplierId];
        return ReceiptListItem(
          receipt: receipt,
          supplier: supplier,
          onTap: () => widget.onReceiptSelected?.call(receipt),
        );
      },
    );
  }

  Widget _buildProductsTab() {
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 40,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.s),
              const Text(
                'No products in catalog',
                style: AppTypography.headingSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Products and prices are automatically indexed when you scan receipts.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      itemCount: _filteredProducts.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.s),
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        final latestCost = 28.50 + (index * 4.25);
        final srp = (latestCost * 1.15).ceilToDouble();

        return ProductCatalogItem(
          product: product,
          latestUnitCost: latestCost,
          suggestedPrice: srp,
          onTap: () => widget.onProductSelected?.call(product),
        );
      },
    );
  }
}
