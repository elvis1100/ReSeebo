import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class BasketSelectedProduct extends StatefulWidget {
  const BasketSelectedProduct({
    super.key,
    required this.product,
    required this.quantity,
    required this.onChanged,
    required this.onRemove,
    required this.validator,
    required this.enabled,
  });
  final Product product;
  final String quantity;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;
  final String? Function(String?) validator;
  final bool enabled;
  @override
  State<BasketSelectedProduct> createState() => _BasketSelectedProductState();
}

class _BasketSelectedProductState extends State<BasketSelectedProduct> {
  late final quantity = TextEditingController(text: widget.quantity);
  @override
  void didUpdateWidget(covariant BasketSelectedProduct oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (quantity.text != widget.quantity) quantity.text = widget.quantity;
  }

  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalPhoto(path: widget.product.photoPath),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    widget.product.identity,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove ${widget.product.name} from basket',
              onPressed: widget.enabled ? widget.onRemove : null,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          label: 'Restock quantity for ${widget.product.name}',
          child: AppField(
            key: ValueKey('basket-quantity-${widget.product.id}'),
            controller: quantity,
            label: 'Restock pieces',
            hint: 'Whole quantity',
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            validator: widget.validator,
            onChanged: widget.onChanged,
          ),
        ),
      ],
    ),
  );
}
