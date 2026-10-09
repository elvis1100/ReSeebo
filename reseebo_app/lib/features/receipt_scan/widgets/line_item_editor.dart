import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/widgets/shared_widgets.dart';
import 'product_match_picker.dart';

class LineItemEditor extends StatefulWidget {
  const LineItemEditor({
    super.key,
    required this.adapter,
    required this.line,
    required this.index,
    required this.product,
    required this.onChanged,
    required this.onProductSelected,
    required this.onRemove,
    required this.onConfirmationChanged,
    this.enabled = true,
    this.pageCount = 1,
    this.problem,
  });
  final IReseeboDataAdapter adapter;
  final ParsedLineItem line;
  final int index;
  final Product? product;
  final VoidCallback onChanged;
  final ValueChanged<Product> onProductSelected;
  final VoidCallback onRemove;
  final ValueChanged<bool> onConfirmationChanged;
  final bool enabled;
  final int pageCount;
  final String? problem;
  @override
  State<LineItemEditor> createState() => _LineItemEditorState();
}

class _LineItemEditorState extends State<LineItemEditor> {
  late final TextEditingController _description,
      _quantity,
      _pieces,
      _gross,
      _discount;
  bool _choosingProduct = false;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    _description = TextEditingController(text: line.description);
    _quantity = TextEditingController(text: line.quantity?.toString());
    _pieces = TextEditingController(text: line.piecesPerPack?.toString());
    _gross = TextEditingController(text: editablePesos(line.grossAmountCents));
    _discount = TextEditingController(text: editablePesos(line.discountCents));
  }

  Future<void> _chooseProduct() async {
    if (_choosingProduct) return;
    setState(() => _choosingProduct = true);
    final selected = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ProductMatchPicker(
          adapter: widget.adapter,
          description: widget.line.description,
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) widget.onProductSelected(selected);
    setState(() => _choosingProduct = false);
  }

  @override
  void dispose() {
    for (final controller in [
      _description,
      _quantity,
      _pieces,
      _gross,
      _discount,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final enabled = widget.enabled && !_choosingProduct;
    final net = line.netAmountCents;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Line ${widget.index + 1} · Photo ${line.sourcePage + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove purchase line',
                  onPressed: enabled ? widget.onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (widget.pageCount > 1) ...[
              DropdownButtonFormField<int>(
                initialValue: line.sourcePage,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Original photo for this line',
                ),
                items: List.generate(
                  widget.pageCount,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text('Photo ${index + 1}'),
                  ),
                ),
                onChanged: enabled
                    ? (page) {
                        if (page != null) {
                          line.sourcePage = page;
                          widget.onChanged();
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            if (!line.confirmed && line.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  line.warnings.join('\n'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            AppField(
              controller: _description,
              enabled: enabled,
              label: 'Original receipt description',
              onChanged: (value) {
                line.description = value;
                widget.onChanged();
              },
              validator: (value) => value!.trim().isEmpty
                  ? 'Enter the receipt description.'
                  : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: enabled ? _chooseProduct : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.product?.name ?? 'Choose exact product'),
                          if (widget.product != null)
                            Text(
                              widget.product!.identity,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppField(
                    controller: _quantity,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    label: 'Quantity',
                    onChanged: (value) {
                      line.quantity = parseQuantity(value);
                      widget.onChanged();
                    },
                    validator: (value) => parseQuantity(value!) == null
                        ? 'Enter whole quantity.'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<PurchaseUnit>(
                    initialValue: line.unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Bought as'),
                    items: const [
                      DropdownMenuItem(
                        value: PurchaseUnit.piece,
                        child: Text('Pieces'),
                      ),
                      DropdownMenuItem(
                        value: PurchaseUnit.pack,
                        child: Text('Packs'),
                      ),
                    ],
                    onChanged: enabled
                        ? (unit) {
                            line.unit = unit;
                            line.piecesPerPack = unit == PurchaseUnit.piece
                                ? 1
                                : null;
                            _pieces.text = unit == PurchaseUnit.piece
                                ? '1'
                                : '';
                            widget.onChanged();
                          }
                        : null,
                    validator: (value) => value == null ? 'Choose unit.' : null,
                  ),
                ),
              ],
            ),
            if (line.unit == PurchaseUnit.pack) ...[
              const SizedBox(height: 16),
              AppField(
                controller: _pieces,
                enabled: enabled,
                keyboardType: TextInputType.number,
                label: 'Pieces per pack',
                helper: 'Check the exact pack size. Do not guess.',
                onChanged: (value) {
                  line.piecesPerPack = parseQuantity(value);
                  widget.onChanged();
                },
                validator: (value) => parseQuantity(value!) == null
                    ? 'Enter confirmed pieces per pack.'
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            AppField(
              controller: _gross,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: 'Total line amount before discount (₱)',
              helper: 'Amount for the entire line, not the unit price.',
              onChanged: (value) {
                line.grossAmountCents = parsePesos(value);
                widget.onChanged();
              },
              validator: (value) => (parsePesos(value!) ?? 0) <= 0
                  ? 'Enter a positive line amount.'
                  : null,
            ),
            const SizedBox(height: 16),
            AppField(
              controller: _discount,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: 'Line discount (₱)',
              helper: 'Use 0 when this line has no discount.',
              onChanged: (value) {
                line.discountCents = parsePesos(value) ?? -1;
                widget.onChanged();
              },
              validator: (value) {
                final discount = parsePesos(value!);
                return discount == null ||
                        (line.grossAmountCents != null &&
                            discount >= line.grossAmountCents!)
                    ? 'Enter a discount below the line amount.'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            Text(
              net == null || net <= 0 || line.discountCents < 0
                  ? 'Net line amount needs checking'
                  : 'Net line amount: ${pesos(net)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (widget.problem != null) ...[
              Notice(message: widget.problem!, warning: true),
              const SizedBox(height: 8),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: line.confirmed,
              onChanged: enabled
                  ? (value) => widget.onConfirmationChanged(value ?? false)
                  : null,
              title: const Text(
                'I checked the exact product, quantity, pack size and amounts',
              ),
            ),
            if (line.confirmed && line.costPerPieceCents != null)
              Text(
                '${line.totalPieces} pieces · ${pesos(line.costPerPieceCents!)} / piece',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
