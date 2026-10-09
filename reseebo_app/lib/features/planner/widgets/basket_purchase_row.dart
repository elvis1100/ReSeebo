import 'package:flutter/material.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class BasketPurchaseRow extends StatelessWidget {
  const BasketPurchaseRow({
    super.key,
    required this.item,
    required this.onReceipt,
  });
  final BasketItem item;
  final ValueChanged<String> onReceipt;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.product.name, style: Theme.of(context).textTheme.titleSmall),
        Text(
          item.product.identity,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          item.estimate.purchase.unit == PurchaseUnit.pack
              ? 'Target ${item.estimate.targetPieces} pcs → ${item.estimate.packsToBuy} packs × ${item.estimate.purchase.piecesPerPack} = ${item.estimate.purchasedPieces} pcs'
              : '${item.estimate.purchasedPieces} pcs to buy',
        ),
        CurrencyText(
          cents: item.estimate.subtotalCents,
          prefix: 'Product cost ',
        ),
        Text(
          'Price from ${purchaseDate(item.estimate.purchase.purchasedAt, withTime: item.estimate.purchase.hasPurchaseTime)}',
          style: const TextStyle(color: AppColors.muted),
        ),
        TextButton.icon(
          onPressed: () => onReceipt(item.estimate.purchase.receiptId),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Source receipt'),
        ),
      ],
    ),
  );
}
