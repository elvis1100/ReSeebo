import 'package:flutter/material.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../catalog/screens/product_editor_screen.dart';
import '../../receipts/screens/receipt_detail_screen.dart';
import '../state/basket_controller.dart';
import '../widgets/basket_product_chooser.dart';
import '../widgets/basket_results.dart';
import '../widgets/basket_selected_product.dart';
import '../widgets/basket_travel_costs.dart';

class BasketPlannerScreen extends StatefulWidget {
  const BasketPlannerScreen({super.key, required this.adapter});
  final IReseeboDataAdapter adapter;
  @override
  State<BasketPlannerScreen> createState() => _BasketPlannerScreenState();
}

class _BasketPlannerScreenState extends State<BasketPlannerScreen> {
  late final controller = BasketController(widget.adapter);
  final form = GlobalKey<FormState>();
  final resultAnchor = GlobalKey();
  final errorAnchor = GlobalKey();
  final quantityAnchors = <String, GlobalKey>{};
  final extraAnchors = <String, GlobalKey>{};
  final scroll = ScrollController();
  bool travelExpanded = false;
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    scroll.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _receipt(String id) async => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          ReceiptDetailScreen(adapter: widget.adapter, receiptId: id),
    ),
  );

  Future<void> _chooseProduct() async {
    FocusScope.of(context).unfocus();
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .85,
          child: BasketProductChooser(products: controller.availableProducts),
        ),
      ),
    );
    if (!mounted || product == null) return;
    controller.addProduct(product);
    await _reveal(quantityAnchors.putIfAbsent(product.id, GlobalKey.new));
  }

  Future<void> _createProduct() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProductEditorScreen(adapter: widget.adapter),
      ),
    );
    if (mounted) await controller.load();
  }

  Future<void> _reveal(GlobalKey key) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || key.currentContext == null) return;
    await Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 250),
      alignment: .15,
    );
  }

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    final success = await controller.calculate();
    if (!mounted) return;
    if (success) {
      await _reveal(resultAnchor);
      return;
    }
    if (controller.invalidExtraSupplierIds.isNotEmpty) {
      setState(() => travelExpanded = true);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    form.currentState?.validate();
    if (controller.invalidQuantityIds.isNotEmpty) {
      final id = controller.invalidQuantityIds.first;
      await _reveal(quantityAnchors.putIfAbsent(id, GlobalKey.new));
    } else if (controller.invalidExtraSupplierIds.isNotEmpty) {
      final id = controller.invalidExtraSupplierIds.first;
      await _reveal(extraAnchors.putIfAbsent(id, GlobalKey.new));
    } else {
      await _reveal(errorAnchor);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Buying basket'),
        actions: [
          if (controller.selectedProducts.isNotEmpty)
            IconButton(
              tooltip: 'Reset basket',
              onPressed: controller.calculating
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      controller.reset();
                    },
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: controller.loading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading your product catalog',
              ),
            )
          : controller.error != null
          ? SingleChildScrollView(
              child: ErrorState(
                message: userMessage(controller.error!),
                onRetry: controller.load,
              ),
            )
          : controller.products.isEmpty
          ? SingleChildScrollView(
              child: EmptyState(
                icon: Icons.shopping_basket_outlined,
                title: 'Add products to plan a basket',
                message:
                    'Create your catalog and save confirmed receipts to calculate dated buying estimates.',
                action: AppActionButton(
                  label: 'Add product',
                  icon: Icons.add,
                  onPressed: _createProduct,
                ),
              ),
            )
          : Form(
              key: form,
              child: ListView(
                controller: scroll,
                padding: AppSpacing.page,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Text(
                    'Your restock list',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Choose exact products and enter pieces needed. Estimates use each supplier’s latest recorded purchase and round up whole packs.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed:
                        controller.calculating ||
                            controller.availableProducts.isEmpty
                        ? null
                        : _chooseProduct,
                    icon: const Icon(Icons.add),
                    label: Text(
                      controller.availableProducts.isEmpty
                          ? 'All products added'
                          : 'Add products',
                    ),
                  ),
                  if (controller.selectedProducts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Text(
                        'Your basket is empty. Add a product to start.',
                      ),
                    ),
                  for (final product in controller.selectedProducts)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: BasketSelectedProduct(
                        key: quantityAnchors.putIfAbsent(
                          product.id,
                          GlobalKey.new,
                        ),
                        product: product,
                        quantity: controller.quantities[product.id] ?? '',
                        enabled: !controller.calculating,
                        onChanged: (value) =>
                            controller.changeQuantity(product.id, value),
                        onRemove: () => controller.removeProduct(product.id),
                        validator: (_) => controller.quantityError(product.id),
                      ),
                    ),
                  if (controller.selectedProducts.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    if (controller.suppliers.isNotEmpty)
                      BasketTravelCosts(
                        suppliers: controller.suppliers,
                        inputs: controller.extraInputs,
                        expanded: travelExpanded,
                        enabled: !controller.calculating,
                        onToggle: () =>
                            setState(() => travelExpanded = !travelExpanded),
                        onChanged: controller.changeExtra,
                        validator: controller.extraError,
                        anchors: extraAnchors,
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    AppActionButton(
                      label: 'Calculate buying basket',
                      busy: controller.calculating,
                      busyLabel: 'Calculating…',
                      icon: Icons.calculate_outlined,
                      onPressed: _calculate,
                    ),
                  ],
                  if (controller.calculationError != null)
                    Padding(
                      key: errorAnchor,
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Notice(
                        message: controller.calculationError!,
                        warning: true,
                      ),
                    ),
                  if (controller.estimate != null)
                    Padding(
                      key: resultAnchor,
                      padding: const EdgeInsets.only(top: AppSpacing.xl),
                      child: BasketResults(
                        controller: controller,
                        onReceipt: _receipt,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
    ),
  );
}
