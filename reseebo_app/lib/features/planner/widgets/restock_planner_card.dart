import 'package:flutter/material.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../comparison/state/comparison_controller.dart';

class RestockPlannerCard extends StatefulWidget {
  const RestockPlannerCard({super.key, required this.controller});
  final ComparisonController controller;
  @override
  State<RestockPlannerCard> createState() => _RestockPlannerCardState();
}

class _RestockPlannerCardState extends State<RestockPlannerCard> {
  late final quantity = TextEditingController(
    text: widget.controller.quantityInput,
  );
  final extras = <String, TextEditingController>{};
  @override
  void dispose() {
    quantity.dispose();
    for (final field in extras.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final rows = controller.data!.latestPrices;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optional restock estimate',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Use dated recorded prices to plan a purchase. Whole packs are rounded up; supplier availability is unknown.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          AppField(
            controller: quantity,
            label: 'Pieces to restock',
            keyboardType: TextInputType.number,
            helper:
                'Enter a whole quantity. Extra obtained pieces remain visible.',
            enabled: !controller.calculating,
            validator: (value) =>
                value!.trim().isEmpty || parseQuantity(value) != null
                ? null
                : 'Enter a whole quantity from 1 to $maxQuantity.',
            onChanged: (value) => controller.changeRestock(quantity: value),
          ),
          const SizedBox(height: 16),
          Text(
            'Travel / delivery costs per supplier',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppField(
                controller: extras.putIfAbsent(
                  row.purchase.supplier.id,
                  () => TextEditingController(
                    text:
                        controller.extraInputs[row.purchase.supplier.id] ?? '',
                  ),
                ),
                label: '${row.purchase.supplier.label} extra cost (₱)',
                hint: '0.00',
                enabled: !controller.calculating,
                validator: (value) =>
                    value!.trim().isEmpty || parsePesos(value) != null
                    ? null
                    : 'Enter a peso amount with up to two decimals.',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (value) => controller.changeRestock(
                  supplierId: row.purchase.supplier.id,
                  extra: value,
                ),
              ),
            ),
          AppActionButton(
            label: 'Calculate buying costs',
            busy: controller.calculating,
            busyLabel: 'Calculating…',
            icon: Icons.calculate_outlined,
            onPressed: () {
              FocusScope.of(context).unfocus();
              controller.calculateRestock();
            },
          ),
          if (controller.restockError != null) ...[
            const SizedBox(height: 12),
            Notice(message: controller.restockError!, warning: true),
          ],
          if (controller.restock != null) ...[
            const SizedBox(height: 20),
            if (controller.restock!.suppliers.isEmpty)
              const Notice(
                message: 'No comparable purchase prices are recorded yet.',
                warning: true,
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: controller.baselineSupplierId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Savings baseline supplier',
                ),
                items: controller.restock!.suppliers
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
                  if (id != null) controller.chooseBaseline(id);
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Compare each estimate with ${controller.baseline?.purchase.supplier.label ?? 'the chosen supplier'}. Savings may be negative.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              for (final estimate in controller.restock!.suppliers)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _EstimateRow(
                    estimate: estimate,
                    controller: controller,
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EstimateRow extends StatelessWidget {
  const _EstimateRow({required this.estimate, required this.controller});
  final RestockSupplierEstimate estimate;
  final ComparisonController controller;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          estimate.purchase.supplier.label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Price recorded ${purchaseDate(estimate.purchase.purchasedAt, withTime: estimate.purchase.hasPurchaseTime)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          estimate.purchase.unit == PurchaseUnit.pack
              ? '${estimate.packsToBuy} packs × ${estimate.purchase.piecesPerPack} pcs = ${estimate.purchasedPieces} obtained pieces'
              : '${estimate.purchasedPieces} pieces to buy',
        ),
        Text('Target ${estimate.targetPieces} pcs'),
        const SizedBox(height: 8),
        _CostLine('Product subtotal', estimate.subtotalCents),
        _CostLine('Travel / delivery', estimate.additionalCostCents),
        _CostLine('Estimated total', estimate.totalCents, bold: true),
        const Divider(height: 20),
        _CostLine(
          'Product-price savings vs baseline',
          controller.productSavings(estimate),
        ),
        _CostLine(
          'Net savings including both extra costs',
          controller.netSavings(estimate),
          bold: true,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () =>
              controller.chooseSupplier(estimate.purchase.supplier.id),
          child: const Text('Use this cost in tubo calculator'),
        ),
      ],
    ),
  );
}

class _CostLine extends StatelessWidget {
  const _CostLine(this.label, this.cents, {this.bold = false});
  final String label;
  final int cents;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text('$label:'),
        CurrencyText(
          cents: cents,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
