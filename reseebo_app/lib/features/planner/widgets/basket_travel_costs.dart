import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class BasketTravelCosts extends StatefulWidget {
  const BasketTravelCosts({
    super.key,
    required this.suppliers,
    required this.inputs,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    required this.validator,
    required this.enabled,
    required this.anchors,
  });
  final List<Supplier> suppliers;
  final Map<String, String> inputs;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String, String) onChanged;
  final String? Function(String) validator;
  final bool enabled;
  final Map<String, GlobalKey> anchors;
  @override
  State<BasketTravelCosts> createState() => _BasketTravelCostsState();
}

class _BasketTravelCostsState extends State<BasketTravelCosts> {
  final fields = <String, TextEditingController>{};
  @override
  void didUpdateWidget(covariant BasketTravelCosts oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final entry in fields.entries) {
      final value = widget.inputs[entry.key] ?? '';
      if (entry.value.text != value) entry.value.text = value;
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: widget.enabled ? widget.onToggle : null,
          icon: Icon(widget.expanded ? Icons.expand_less : Icons.expand_more),
          label: const Text('Travel / delivery costs (optional)'),
        ),
        const Text(
          'Added once per supplier visited. Blank means ₱0.00.',
          style: TextStyle(color: AppColors.muted),
        ),
        if (!widget.expanded &&
            widget.inputs.values.any((input) => input.trim().isNotEmpty))
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text('Your entered extra costs will be included.'),
          ),
        if (widget.expanded) ...[
          const SizedBox(height: AppSpacing.md),
          for (final supplier in widget.suppliers)
            Padding(
              key: widget.anchors.putIfAbsent(supplier.id, GlobalKey.new),
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppField(
                key: ValueKey('basket-extra-${supplier.id}'),
                controller: fields.putIfAbsent(
                  supplier.id,
                  () => TextEditingController(
                    text: widget.inputs[supplier.id] ?? '',
                  ),
                ),
                label: '${supplier.label} extra cost (₱)',
                hint: '0.00',
                enabled: widget.enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (_) => widget.validator(supplier.id),
                onChanged: (value) => widget.onChanged(supplier.id, value),
              ),
            ),
        ],
      ],
    ),
  );
}
