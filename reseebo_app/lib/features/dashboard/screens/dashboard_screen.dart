import 'package:flutter/material.dart';
import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../widgets/product_catalog_item.dart';
import '../../../core/services/pricing_service.dart';
import '../../../core/widgets/store_header.dart';
import '../../../core/widgets/shared_widgets.dart' show ErrorState;
import '../../catalog/screens/product_editor_screen.dart';
import '../widgets/receipt_list_item.dart';
import '../widgets/stat_header.dart';
import '../../insights/screens/insights_screen.dart';

/// Main hub of Reseebo providing store owners quick access to recent
/// scanned receipts, tracked product prices, and fast scanning actions.
class DashboardScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final VoidCallback? onSettingsPressed;
  final ValueChanged<Receipt>? onReceiptSelected;
  final ValueChanged<Product>? onProductSelected;
  final int refreshRevision;

  const DashboardScreen({
    super.key,
    required this.dataAdapter,
    this.onSettingsPressed,
    this.onReceiptSelected,
    this.onProductSelected,
    this.refreshRevision = 0,
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
  Map<String, LatestProductCost> _costs = {};
  Object? _error;
  bool _loadedOnce = false;
  int _request = 0;
  Future<void>? _refreshing;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision) _loadData();
  }

  @override
  void dispose() {
    _request++;
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _refreshData() => _refreshing ??= _loadData(
    refresh: true,
  ).whenComplete(() => _refreshing = null);

  Future<void> _loadData({bool refresh = false}) async {
    final request = ++_request;
    setState(() {
      if (!refresh) _isLoading = true;
      _error = null;
    });
    try {
      final profile = await widget.dataAdapter.getStoreProfile();
      final receipts = await widget.dataAdapter.getRecentReceipts();
      final products = await widget.dataAdapter.getProducts();
      final costs = await widget.dataAdapter.getLatestProductCosts(
        products.map((p) => p.id),
      );
      if (!mounted || request != _request) return;
      if (!_loadedOnce) {
        _tabController.index = receipts.isEmpty && products.isNotEmpty ? 1 : 0;
        _loadedOnce = true;
      }
      final suppliers = {
        for (final receipt in receipts) receipt.supplierId: receipt.supplier,
      };
      setState(() {
        _storeProfile = profile;
        _receipts = receipts;
        _products = products;
        _costs = costs;
        _suppliersMap = suppliers;
      });
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _isLoading = false);
    }
  }

  Future<void> _addProduct() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductEditorScreen(adapter: widget.dataAdapter),
      ),
    );
    if (!mounted || saved != true) return;
    _tabController.index = 1;
    _searchController.clear();
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product added to your catalog.')),
    );
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
      final name = '${p.displayName} ${p.displayTitle}'.toLowerCase();
      final cat = p.category.toLowerCase();
      return name.contains(_searchQuery) || cat.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(toolbarHeight: 64, title: const StoreHeader()),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
          ? SingleChildScrollView(
              child: ErrorState(
                message: userMessage(_error!),
                onRetry: _loadData,
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _refreshData,
              // TabBarView adds a viewport: its primary lists report depth 2.
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.vertical &&
                  notification.depth <= 2,
              child: NestedScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                key: const ValueKey('dashboard-scroll'),
                floatHeaderSlivers: true,
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
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
                              onSettingsTap: widget.onSettingsPressed,
                              onInsightsTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => InsightsScreen(
                                    adapter: widget.dataAdapter,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.m),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('dashboard-search'),
                                  controller: _searchController,
                                  style: AppTypography.bodyRegular,
                                  decoration: InputDecoration(
                                    hintText: _tabController.index == 1
                                        ? 'Search products...'
                                        : 'Search suppliers or receipts...',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      color: AppColors.textMuted,
                                      size: 20,
                                    ),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.clear_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                            },
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              if (_tabController.index == 1) ...[
                                const SizedBox(width: AppSpacing.s),
                                Tooltip(
                                  message: 'Add product',
                                  child: Semantics(
                                    label: 'Add product',
                                    child: OutlinedButton.icon(
                                      clipBehavior: Clip.antiAlias,
                                      key: const ValueKey(
                                        'dashboard-add-product',
                                      ),
                                      onPressed: _addProduct,
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 20,
                                      ),
                                      label: const Text('Add'),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 48),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.m),
                          // Modern segmented pill tab bar
                          Material(
                            key: const ValueKey('dashboard-tabs-surface'),
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusS,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              height: 40,
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: TabBar(
                                  controller: _tabController,
                                  dividerHeight: 0,
                                  dividerColor: Colors.transparent,
                                  labelPadding: EdgeInsets.zero,
                                  labelColor: AppColors.textPrimary,
                                  unselectedLabelColor: AppColors.textSecondary,
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  automaticIndicatorColorAdjustment: false,
                                  splashBorderRadius: BorderRadius.circular(
                                    AppSpacing.radiusXs + 2,
                                  ),
                                  indicator: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusXs + 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 3,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  labelStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  unselectedLabelStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  tabs: [
                                    Tab(
                                      text:
                                          'Receipts (${_filteredReceipts.length})',
                                    ),
                                    Tab(
                                      text:
                                          'Products (${_filteredProducts.length})',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [_buildReceiptsTab(), _buildProductsTab()],
                ),
              ),
            ),
    );
  }

  Widget _scrollableEmpty(String storageKey, Widget child) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      key: PageStorageKey(storageKey),
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: constraints.maxHeight, child: child)],
    ),
  );

  Widget _buildReceiptsTab() {
    if (_filteredReceipts.isEmpty) {
      return _scrollableEmpty(
        'dashboard-receipts-list',
        Center(
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
                Text(
                  _searchQuery.isEmpty
                      ? 'No receipts recorded yet'
                      : 'No matching receipts',
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
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey('dashboard-receipts-list'),
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
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
      return _scrollableEmpty(
        'dashboard-products-list',
        Center(
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
                Text(
                  _searchQuery.isEmpty
                      ? 'No products in catalog'
                      : 'No matching products',
                  style: AppTypography.headingSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add a product here or while reviewing a receipt. Recorded prices appear after saving purchases.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey('dashboard-products-list'),
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      itemCount: _filteredProducts.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.s),
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        final cost = _costs[product.id];
        final markup =
            product.markupPercent ?? _storeProfile?.defaultMarkupPercent;
        final srp = cost == null || markup == null
            ? null
            : PricingService.suggestedSellingPriceCents(
                    cost.costPerPieceCents,
                    markup,
                  ) /
                  100;

        return ProductCatalogItem(
          product: product,
          latestUnitCost: cost == null ? null : cost.costPerPieceCents / 100,
          latestPurchaseDate: cost?.purchasedAt,
          suggestedPrice: srp,
          onTap: () => widget.onProductSelected?.call(product),
        );
      },
    );
  }
}
