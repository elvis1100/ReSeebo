import 'package:flutter/material.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../comparison/state/comparison_controller.dart';

class ProfitCalculatorCard extends StatefulWidget {
  const ProfitCalculatorCard({super.key, required this.controller});
  final ComparisonController controller;
  @override
  State<ProfitCalculatorCard> createState() => _ProfitCalculatorCardState();
}

class _ProfitCalculatorCardState extends State<ProfitCalculatorCard> {
  late final markup = TextEditingController(
    text: widget.controller.markupInput,
  );
  late final addition = TextEditingController(
    text: widget.controller.additionInput,
  );
  late final selling = TextEditingController(
    text: widget.controller.sellingInput,
  );
  @override
  void dispose() {
    markup.dispose();
    addition.dispose();
    selling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final data = controller.data!;
    final purchase = controller.selectedPurchase;
    final result = controller.profit;
    final suggested = controller.suggestedPriceCents;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selling price & estimated tubo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Cost source: ${purchase?.supplier.label ?? 'Select a supplier'}',
            style: const TextStyle(color: AppColors.muted),
          ),
          if (purchase != null)
            Text(
              purchaseDate(
                purchase.purchasedAt,
                withTime: purchase.hasPurchaseTime,
              ),
              style: const TextStyle(color: AppColors.muted),
            ),
          const SizedBox(height: 12),
          if (controller.costUsedCents != null)
            Text(
              'Purchase cost used ${pesos(controller.costUsedCents!)} / pc',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Markup %')),
              ButtonSegment(value: true, label: Text('Add pesos')),
            ],
            selected: {controller.pesoAddition},
            onSelectionChanged: (value) =>
                controller.changePricing(usePeso: value.first),
          ),
          const SizedBox(height: 16),
          if (!controller.pesoAddition)
            AppField(
              controller: markup,
              label: 'Scenario markup (%)',
              validator: (value) => parseMarkup(value!) != null
                  ? null
                  : 'Choose a markup from 0 to 10,000%.',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (value) => controller.changePricing(markup: value),
              helper: data.effectiveMarkupPercent == null
                  ? 'Choose a percentage; 0% is valid.'
                  : '${data.product.markupPercent != null ? 'Product override' : 'Store default'}: ${percent(data.effectiveMarkupPercent!)}. Scenario changes are not saved.',
            )
          else
            AppField(
              controller: addition,
              label: 'Scenario addition (₱ / pc)',
              validator: (value) => parsePesos(value!) != null
                  ? null
                  : 'Enter a valid peso addition, including 0.00.',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (value) => controller.changePricing(addition: value),
              helper: 'Enter 0.00 or a positive peso addition.',
            ),
          if (controller.selectedEstimate != null) ...[
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.includeExtraInProfit,
              onChanged: (value) =>
                  controller.changePricing(includeExtra: value),
              title: const Text('Include this supplier’s travel cost'),
              subtitle: Text(
                'Allocate ${pesos(controller.selectedEstimate!.additionalCostCents)} over ${controller.selectedEstimate!.purchasedPieces} obtained pieces.',
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Calculated suggested selling price',
            style: TextStyle(color: AppColors.muted),
          ),
          Text(
            suggested == null
                ? 'Choose your pricing input'
                : '${pesos(suggested)} / pc',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.product.sellingPriceCents == null
                ? 'Owner-set selling price: not set'
                : 'Owner-set selling price: ${pesos(data.product.sellingPriceCents!)} / pc',
          ),
          const SizedBox(height: 16),
          AppField(
            controller: selling,
            label: 'Scenario selling price (₱ / pc)',
            validator: (value) =>
                value!.trim().isEmpty || parsePesos(value) != null
                ? null
                : 'Enter a peso amount with up to two decimals.',
            hint: 'Use calculated suggestion',
            helper:
                'Optional. Clear to use the suggestion; edit the product to save an owner-set price.',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) => controller.changePricing(selling: value),
          ),
          if (controller.pricingError != null) ...[
            const SizedBox(height: 12),
            Notice(message: controller.pricingError!, warning: true),
          ],
          if (result != null) ...[
            const SizedBox(height: 16),
            Text(
              'Estimated gross profit ${pesos(result.grossProfitCents)} / pc',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: result.grossProfitCents < 0
                    ? AppColors.danger
                    : AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text('At ${pesos(result.sellingPriceCents)} selling price'),
            Text('Markup on cost: ${percent(result.markupPercent)}'),
            Text(
              'Gross margin on selling price: ${result.marginPercent == null ? 'undefined at ₱0.00' : percent(result.marginPercent!)}',
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Estimated gross profit is before rent, electricity, losses, and other operating costs.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
