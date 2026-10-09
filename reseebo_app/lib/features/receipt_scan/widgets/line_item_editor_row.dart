import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../state/receipt_review_state.dart';

class LineItemEditorRow extends StatefulWidget {
  const LineItemEditorRow({
    super.key,
    required this.line,
    this.matchedProduct,
    required this.index,
    required this.onSelectProduct,
    required this.onQuantityChanged,
    required this.onPiecesPerPackChanged,
    required this.onLineTotalChanged,
    required this.onRemove,
    this.onFieldEdited,
    this.onUnitChanged,
    this.onTargetSelected,
    this.onConfirm,
    this.selectedField,
    this.problem,
    this.enabled = true,
  });
  final ParsedLineItem line;
  final Product? matchedProduct;
  final int index;
  final VoidCallback onSelectProduct, onRemove;
  final ValueChanged<double> onQuantityChanged, onLineTotalChanged;
  final ValueChanged<int> onPiecesPerPackChanged;
  final void Function(ReceiptLineField, String)? onFieldEdited;
  final ValueChanged<PurchaseUnit>? onUnitChanged;
  final ValueChanged<ReceiptLineField>? onTargetSelected;
  final VoidCallback? onConfirm;
  final ReceiptLineField? selectedField;
  final String? problem;
  final bool enabled;

  @override
  State<LineItemEditorRow> createState() => _LineItemEditorRowState();
}

class _LineItemEditorRowState extends State<LineItemEditorRow> {
  final Map<ReceiptLineField, TextEditingController> _controllers = {};
  final Map<ReceiptLineField, FocusNode> _focus = {};

  String _value(ReceiptLineField field) => switch (field) {
    ReceiptLineField.description => widget.line.description,
    ReceiptLineField.quantity => widget.line.quantity?.toString() ?? '',
    ReceiptLineField.piecesPerPack =>
      widget.line.piecesPerPack?.toString() ?? '',
    ReceiptLineField.amount => editablePesos(widget.line.grossAmountCents),
  };

  @override
  void initState() {
    super.initState();
    for (final field in ReceiptLineField.values) {
      _controllers[field] = TextEditingController(text: _value(field));
      _focus[field] = FocusNode();
    }
  }

  @override
  void didUpdateWidget(covariant LineItemEditorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final field in ReceiptLineField.values) {
      final value = _value(field);
      if (!_focus[field]!.hasFocus && _controllers[field]!.text != value) {
        _controllers[field]!.text = value;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _edit(ReceiptLineField field, String value) {
    if (widget.onFieldEdited != null) {
      widget.onFieldEdited!(field, value);
      return;
    }
    switch (field) {
      case ReceiptLineField.quantity:
        final number = parseQuantity(value);
        if (number != null) widget.onQuantityChanged(number.toDouble());
      case ReceiptLineField.piecesPerPack:
        final number = parseQuantity(value);
        if (number != null) widget.onPiecesPerPackChanged(number);
      case ReceiptLineField.amount:
        final amount = parsePesos(value);
        if (amount != null) widget.onLineTotalChanged(amount / 100);
      case ReceiptLineField.description:
        break;
    }
  }

  bool _needsReview(ReceiptLineField field) => switch (field) {
    ReceiptLineField.description =>
      widget.line.description.trim().isEmpty || widget.matchedProduct == null,
    ReceiptLineField.quantity => widget.line.quantity == null,
    ReceiptLineField.piecesPerPack =>
      widget.line.unit == PurchaseUnit.pack &&
          widget.line.piecesPerPack == null,
    ReceiptLineField.amount =>
      widget.line.grossAmountCents == null ||
          widget.line.grossAmountCents! <= 0,
  };

  Widget _field(ReceiptLineField field) {
    final numeric = field != ReceiptLineField.description;
    final amount = field == ReceiptLineField.amount;
    final warning = !widget.line.confirmed || _needsReview(field);
    return TextFormField(
      key: ValueKey(field.name),
      controller: _controllers[field],
      focusNode: _focus[field],
      enabled: widget.enabled,
      keyboardType: numeric
          ? TextInputType.numberWithOptions(decimal: amount)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: field == ReceiptLineField.quantity
            ? (widget.line.unit == PurchaseUnit.pack
                  ? 'Number of packs'
                  : 'Number of pieces')
            : '${field.label}${amount ? ' (₱)' : ''}',
        filled: warning,
        fillColor: AppColors.warningBg,
        helperText: amount ? 'Total for this item' : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => _edit(field, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    return AppCard(
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Item ${widget.index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item ${widget.index + 1}',
                  onPressed: widget.enabled ? widget.onRemove : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                widget.matchedProduct?.displayTitle ?? 'Match exact product',
              ),
              subtitle: Text(
                widget.matchedProduct?.name ?? 'Check brand, variant and size',
                style: TextStyle(
                  color: widget.matchedProduct == null
                      ? AppColors.amberText
                      : null,
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: widget.enabled ? widget.onSelectProduct : null,
            ),
            const SizedBox(height: 8),
            SegmentedButton<PurchaseUnit>(
              segments: const [
                ButtonSegment(value: PurchaseUnit.piece, label: Text('Pcs')),
                ButtonSegment(value: PurchaseUnit.pack, label: Text('Packs')),
              ],
              showSelectedIcon: false,
              selected: {line.unit ?? PurchaseUnit.piece},
              onSelectionChanged: widget.enabled && widget.onUnitChanged != null
                  ? (values) {
                      if (values.isNotEmpty) {
                        widget.onUnitChanged!(values.single);
                      }
                    }
                  : null,
            ),
            if (line.unit == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Check whether this quantity is pieces or packs.',
                  style: TextStyle(color: AppColors.amberText),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _field(ReceiptLineField.quantity)),
                const SizedBox(width: 12),
                Expanded(child: _field(ReceiptLineField.amount)),
              ],
            ),
            if (line.unit == PurchaseUnit.pack) ...[
              const SizedBox(height: 12),
              _field(ReceiptLineField.piecesPerPack),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: const Text('Receipt details'),
              subtitle: Text(
                line.description.isEmpty
                    ? 'Enter the name printed on your receipt'
                    : line.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                _field(ReceiptLineField.description),
                if (widget.onTargetSelected != null) ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Copy a value from the receipt'),
                  ),
                  Wrap(
                    spacing: 6,
                    children: ReceiptLineField.values
                        .where(
                          (field) =>
                              field != ReceiptLineField.piecesPerPack ||
                              line.unit == PurchaseUnit.pack,
                        )
                        .map(
                          (field) => ChoiceChip(
                            label: Text(field.label),
                            selected: widget.selectedField == field,
                            onSelected: widget.enabled
                                ? (_) => widget.onTargetSelected!(field)
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
            if (widget.problem != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  widget.problem!,
                  style: const TextStyle(color: AppColors.amberText),
                ),
              ),
            if (line.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Check these details',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final warning in line.warnings.toSet())
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    warning,
                    style: const TextStyle(color: AppColors.amberText),
                  ),
                ),
            ],
            if (line.confirmed &&
                widget.matchedProduct != null &&
                widget.problem == null &&
                line.costPerPieceCents != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${line.totalPieces} total pieces · ${pesos(line.costPerPieceCents!)} / piece',
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I checked this item'),
              subtitle: const Text(
                'Product, quantity and amount paid are correct',
              ),
              value: line.confirmed,
              onChanged: widget.enabled && widget.onConfirm != null
                  ? (_) => widget.onConfirm!()
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
