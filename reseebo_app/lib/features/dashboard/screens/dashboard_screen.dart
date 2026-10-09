import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../catalog/screens/product_editor_screen.dart';
import '../../comparison/screens/product_comparison_screen.dart';
import '../../planner/screens/basket_planner_screen.dart';
import '../../profile/screens/store_profile_screen.dart';
import '../../receipt_scan/screens/capture_screen.dart';
import '../../receipts/screens/receipt_detail_screen.dart';
import '../../suppliers/screens/supplier_editor_screen.dart';
import '../state/dashboard_controller.dart';
import '../widgets/ledger_items.dart';
import '../widgets/store_header.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.adapter});
  final IReseeboDataAdapter adapter;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController controller;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = DashboardController(widget.adapter)..load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPickerResult());
  }

  // Android can recreate the activity while an external camera/gallery runs.
  // The result has no reliable feature identity, so the owner chooses its use.
  Future<void> _recoverPickerResult() async {
    if (!Platform.isAndroid) return;
    try {
      final response = await ImagePicker().retrieveLostData();
      if (!mounted || response.isEmpty) return;
      final files = response.files;
      if (files == null || files.isEmpty) {
        if (response.exception != null) {
          showAppError(
            context,
            const AppException(
              'The camera result could not be recovered. Please take the photo again.',
            ),
          );
        }
        return;
      }
      final path = files.first.path;
      final useAsReceipt = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recovered photo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LocalPhoto(path: path, size: 120),
              const SizedBox(height: 12),
              const Text(
                'Your camera or gallery was interrupted. Use this recovered photo as a receipt?',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ignore'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use as receipt'),
            ),
          ],
        ),
      );
      if (!mounted || useAsReceipt != true) return;
      await _open(
        CaptureScreen(adapter: widget.adapter, initialImagePath: path),
      );
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  Future<void> _open(Widget screen) async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute<Object?>(builder: (_) => screen));
    if (mounted) await controller.load();
    if (mounted && result is SaveReceiptResult) {
      await _open(
        ReceiptDetailScreen(
          adapter: widget.adapter,
          receiptId: result.receiptId,
          justSaved: true,
        ),
      );
    }
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'profile':
        await _open(StoreProfileScreen(adapter: widget.adapter));
      case 'supplier':
        await _open(SupplierEditorScreen(adapter: widget.adapter));
      case 'basket':
        await _open(BasketPlannerScreen(adapter: widget.adapter));
    }
  }

  @override
  void dispose() {
    search.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Reseebo'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Store options',
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: Text('Store profile'),
              ),
              const PopupMenuItem(
                value: 'supplier',
                child: Text('Add supplier'),
              ),
              const PopupMenuItem(
                value: 'basket',
                child: Text('Buying basket'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(CaptureScreen(adapter: widget.adapter)),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan receipt'),
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            StoreHeader(
              profile: controller.profile,
              onBasket: () =>
                  _open(BasketPlannerScreen(adapter: widget.adapter)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: search,
              onChanged: controller.search,
              decoration: InputDecoration(
                labelText: controller.tab == DashboardTab.receipts
                    ? 'Search receipts or suppliers'
                    : 'Search products',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    search.clear();
                    controller.search('');
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<DashboardTab>(
              segments: const [
                ButtonSegment(
                  value: DashboardTab.receipts,
                  icon: Icon(Icons.receipt_long_outlined),
                  label: Text('Receipts'),
                ),
                ButtonSegment(
                  value: DashboardTab.products,
                  icon: Icon(Icons.inventory_2_outlined),
                  label: Text('Products'),
                ),
              ],
              selected: {controller.tab},
              onSelectionChanged: (values) =>
                  controller.selectTab(values.first),
            ),
            const SizedBox(height: 14),
            if (controller.tab == DashboardTab.products)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      _open(ProductEditorScreen(adapter: widget.adapter)),
                  icon: const Icon(Icons.add),
                  label: const Text('Add product'),
                ),
              ),
            if (controller.loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading your local records',
                  ),
                ),
              )
            else if (controller.error != null)
              ErrorState(
                message: userMessage(controller.error!),
                onRetry: controller.load,
              )
            else if (controller.tab == DashboardTab.receipts)
              ..._receiptList()
            else
              ..._productList(),
          ],
        ),
      ),
    ),
  );

  List<Widget> _receiptList() => controller.receipts.isEmpty
      ? [
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: controller.query.trim().isEmpty
                ? 'Your receipt ledger starts here'
                : 'No matching receipts',
            message: controller.query.trim().isEmpty
                ? 'Scan or import a receipt, confirm the details, and keep your buying history on this phone.'
                : 'Try another supplier, receipt number, or search phrase.',
            action: controller.query.trim().isEmpty
                ? FilledButton.icon(
                    onPressed: () =>
                        _open(CaptureScreen(adapter: widget.adapter)),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add first receipt'),
                  )
                : null,
          ),
        ]
      : [
          for (final receipt in controller.receipts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ReceiptLedgerItem(
                receipt: receipt,
                onTap: () => _open(
                  ReceiptDetailScreen(
                    adapter: widget.adapter,
                    receiptId: receipt.id,
                  ),
                ),
              ),
            ),
        ];

  List<Widget> _productList() => controller.products.isEmpty
      ? [
          EmptyState(
            icon: Icons.inventory_2_outlined,
            title: controller.query.trim().isEmpty
                ? 'Build your product catalog'
                : 'No matching products',
            message:
                'Keep each brand, variant, and size separate so your price comparisons stay useful.',
            action: FilledButton.icon(
              onPressed: () =>
                  _open(ProductEditorScreen(adapter: widget.adapter)),
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
          ),
        ]
      : [
          for (final product in controller.products)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ProductCatalogItem(
                product: product,
                latestCostCents: controller.latestCosts[product.id],
                latestCostDate: controller.latestCostDates[product.id],
                onTap: () => _open(
                  ProductComparisonScreen(
                    adapter: widget.adapter,
                    productId: product.id,
                  ),
                ),
              ),
            ),
        ];
}
