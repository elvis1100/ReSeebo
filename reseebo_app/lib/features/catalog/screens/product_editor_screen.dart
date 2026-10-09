import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/state/local_editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../profile/widgets/photo_editor.dart';
import '../widgets/alias_manager.dart';

class ProductEditorScreen extends StatefulWidget {
  const ProductEditorScreen({super.key, required this.adapter, this.product});
  final IReseeboDataAdapter adapter;
  final Product? product;
  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  late final TextEditingController _name,
      _brand,
      _variant,
      _size,
      _category,
      _barcode,
      _markup,
      _selling;
  String? _photoPath;
  late final LocalEditorController<Product> _editor;
  late final List<String> _initial;
  List<TextEditingController> get _fields => [
    _name,
    _brand,
    _variant,
    _size,
    _category,
    _barcode,
    _markup,
    _selling,
  ];
  bool get _dirty =>
      _photoPath != widget.product?.photoPath ||
      _fields.indexed.any((entry) => entry.$2.text != _initial[entry.$1]);
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _id = product?.id ?? const Uuid().v4();
    _name = TextEditingController(text: product?.name);
    _brand = TextEditingController(text: product?.brand);
    _variant = TextEditingController(text: product?.variant);
    _size = TextEditingController(text: product?.size);
    _category = TextEditingController(text: product?.category);
    _barcode = TextEditingController(text: product?.barcode);
    _markup = TextEditingController(text: product?.markupPercent?.toString());
    _selling = TextEditingController(
      text: editablePesos(product?.sellingPriceCents),
    );
    _photoPath = product?.photoPath;
    _initial = _fields.map((field) => field.text).toList();
    _editor = LocalEditorController(write: widget.adapter.saveProduct)
      ..addListener(_changed);
    for (final field in _fields) {
      field.addListener(_changed);
    }
  }

  Future<void> _save() async {
    if (_editor.saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await _editor.save(
      Product(
        id: _id,
        name: _name.text.trim(),
        brand: _brand.text.trim(),
        variant: _variant.text.trim(),
        size: _size.text.trim(),
        category: _category.text.trim(),
        barcode: _barcode.text.trim(),
        photoPath: _photoPath,
        markupPercent: _markup.text.trim().isEmpty
            ? null
            : parseMarkup(_markup.text),
        sellingPriceCents: _selling.text.trim().isEmpty
            ? null
            : parsePesos(_selling.text),
      ),
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _brand,
      _variant,
      _size,
      _category,
      _barcode,
      _markup,
      _selling,
    ]) {
      controller.dispose();
    }
    _editor.dispose();
    super.dispose();
  }

  Widget _identityField(
    TextEditingController controller,
    String label, {
    String? helper,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AppField(
      controller: controller,
      enabled: !_editor.saving,
      label: label,
      helper: helper,
      hint: hint,
      validator: (value) => value!.trim().isEmpty ? 'Enter $label.' : null,
    ),
  );

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    dirty: _dirty,
    busy: _editor.saving,
    saved: _editor.saved,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Add product' : 'Edit product'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: AppSpacing.page,
          children: [
            PhotoEditor(
              path: _photoPath,
              enabled: !_editor.saving,
              label: 'Product photo',
              onChanged: (path) => setState(() => _photoPath = path),
            ),
            const SizedBox(height: 20),
            _identityField(_name, 'Product name', hint: 'Coffee sachet'),
            _identityField(_brand, 'Brand', hint: 'Exact brand on the product'),
            _identityField(
              _variant,
              'Variant',
              hint: 'Original / Regular',
              helper:
                  'Use “Regular” explicitly when there is no special variant.',
            ),
            _identityField(
              _size,
              'Size / unit',
              hint: '26g / 250ml',
              helper:
                  'Different sizes stay separate. Use “Not applicable” when appropriate.',
            ),
            AppField(
              controller: _category,
              enabled: !_editor.saving,
              label: 'Category (optional)',
            ),
            const SizedBox(height: 16),
            AppField(
              controller: _barcode,
              enabled: !_editor.saving,
              label: 'Barcode (optional)',
            ),
            const SizedBox(height: 24),
            Text(
              'Selling settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            AppField(
              controller: _markup,
              enabled: !_editor.saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: 'Product markup override (%)',
              helper: 'Blank uses store default. 0% means at cost.',
              validator: (value) =>
                  value!.trim().isEmpty || parseMarkup(value) != null
                  ? null
                  : 'Enter a markup from 0 to 10,000%.',
            ),
            const SizedBox(height: 16),
            AppField(
              controller: _selling,
              enabled: !_editor.saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              label: 'Your selling price per piece (₱)',
              helper: 'Optional; saved separately from calculated suggestions.',
              validator: (value) =>
                  value!.trim().isEmpty || parsePesos(value) != null
                  ? null
                  : 'Enter a valid peso amount, up to 2 decimals.',
            ),
            const SizedBox(height: 24),
            if (widget.product != null)
              AliasManager(
                adapter: widget.adapter,
                productId: _id,
                enabled: !_editor.saving,
              ),
            const SizedBox(height: 16),
            if (_editor.error != null) ...[
              Notice(message: userMessage(_editor.error!), warning: true),
              const SizedBox(height: AppSpacing.lg),
            ],
            AppActionButton(
              label: 'Save product',
              busy: _editor.saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    ),
  );
}
