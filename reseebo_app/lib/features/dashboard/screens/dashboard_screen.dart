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
import '../widgets/pending_receipt_list_item.dart';
import '../../receipts/screens/pending_receipt_screen.dart';
import '../widgets/stat_header.dart';
import '../../insights/screens/insights_screen.dart';

/// Main hub of Reseebo providing store owners quick access to recent
/// scanned receipts, tracked product prices, and fast scanning actions.
class DashboardScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final VoidCallback? onSettingsPressed;
  final ValueChanged<Receipt>? onReceiptSelected;
  final ValueChanged<String>? onPendingReceiptSelected;
  final ValueChanged<Product>? onProductSelected;
  final int refreshRevision;

  const DashboardScreen({
    super.key,
    required this.dataAdapter,
    this.onSettingsPressed,
    this.onReceiptSelected,
    this.onPendingReceiptSelected,
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
  List<LedgerEntry> _ledgerEntries = [];
  List<LedgerEntry>? _searchedEntries;
  List<Product> _products = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Map<String, LatestProductCost> _costs = {};
  Object? _error;
  bool _loadedOnce = false;
  int _request = 0;
  Future<void>? _refreshing;
  int _searchRequest = 0;

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
    _searchRequest++;
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
      _searchedEntries = null;
    });
    _searchLedger();
  }

  Future<void> _searchLedger() async {
    final request = ++_searchRequest;
    final query = _searchQuery;
    if (query.isEmpty) return;
    try {
      final entries = await widget.dataAdapter.getLedgerEntries(query: query);
      final receipts = await _receiptsForEntries(entries, _receipts);
      if (!mounted || request != _searchRequest || query != _searchQuery) {
        return;
      }
      setState(() {
        _searchedEntries = entries;
        _receipts = receipts;
      });
    } catch (failure) {
      if (mounted && request == _searchRequest) {
        setState(() => _error = failure);
      }
    }
  }

  Future<List<Receipt>> _receiptsForEntries(
    List<LedgerEntry> entries,
    List<Receipt> existing,
  ) async {
    final receipts = {for (final receipt in existing) receipt.id: receipt};
    for (final entry in entries) {
      final id = entry.confirmedReceiptId;
      if (entry.pendingId == null && id != null && !receipts.containsKey(id)) {
        receipts[id] = (await widget.dataAdapter.getReceipt(id)).receipt;
      }
    }
    return receipts.values.toList();
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
      final entries = await widget.dataAdapter.getLedgerEntries();
      final receipts = await _receiptsForEntries(
        entries,
        await widget.dataAdapter.getRecentReceipts(),
      );
      final products = await widget.dataAdapter.getProducts();
      final costs = await widget.dataAdapter.getLatestProductCosts(
        products.map((p) => p.id),
      );
      if (!mounted || request != _request) return;
      if (!_loadedOnce) {
        _tabController.index = entries.isEmpty && products.isNotEmpty ? 1 : 0;
        _loadedOnce = true;
      }
      setState(() {
        _storeProfile = profile;
        _receipts = receipts;
        _ledgerEntries = entries;
        _products = products;
        _costs = costs;
      });
      if (_searchQuery.isNotEmpty) await _searchLedger();
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

  List<LedgerEntry> get _visibleEntries {
    if (_searchQuery.isEmpty) return _ledgerEntries;
    if (_searchedEntries != null) return _searchedEntries!;
    return _ledgerEntries.where((entry) {
      final receipt = _receipts
          .where((r) => r.id == entry.confirmedReceiptId)
          .firstOrNull;
      return entry.supplierDisplay.toLowerCase().contains(_searchQuery) ||
          (receipt?.receiptNumber.toLowerCase().contains(_searchQuery) ??
              false);
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
                          if (_tabController.index == 0) ...[
                            Wrap(
                              spacing: 16,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '${_ledgerEntries.where((entry) => entry.confirmedReceiptId != null).length} confirmed',
                                ),
                                Text(
                                  '${_ledgerEntries.where((entry) => entry.status == LedgerEntryStatus.needsReview).length} needs review',
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s),
                          ],
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
                              height:
                                  40 *
                                  MediaQuery.textScalerOf(
                                    context,
                                  ).scale(1).clamp(1.0, 2.0),
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
                                          'Receipts (${_visibleEntries.length})',
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
    if (_visibleEntries.isEmpty) {
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
      itemCount: _visibleEntries.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.s),
      itemBuilder: (context, index) {
        final entry = _visibleEntries[index];
        if (entry.pendingId != null) {
          return PendingReceiptListItem(
            entry: entry,
            onTap: () async {
              final callback = widget.onPendingReceiptSelected;
              if (callback != null) {
                callback(entry.pendingId!);
                return;
              }
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PendingReceiptScreen(
                    adapter: widget.dataAdapter,
                    pendingId: entry.pendingId!,
                  ),
                ),
              );
              if (mounted) await _loadData();
            },
          );
        }
        final receipt = _receipts
            .where((r) => r.id == entry.confirmedReceiptId)
            .first;
        return ReceiptListItem(
          receipt: receipt,
          supplier: receipt.supplier,
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
