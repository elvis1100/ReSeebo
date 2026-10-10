import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/state/local_editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../profile/widgets/photo_editor.dart';
import '../widgets/alias_manager.dart';
import '../widgets/product_category_field.dart';

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
  late final TextEditingController _name, _size, _category;
  String? _photoPath;
  bool _categoryBusy = false;
  late final LocalEditorController<Product> _editor;
  late final List<String> _initial;
  List<TextEditingController> get _fields => [_name, _size, _category];
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
    _size = TextEditingController(text: product?.size);
    _category = TextEditingController(text: product?.category);
    _photoPath = product?.photoPath;
    _initial = _fields.map((field) => field.text).toList();
    _editor = LocalEditorController(write: widget.adapter.saveProduct)
      ..addListener(_changed);
    for (final field in _fields) {
      field.addListener(_changed);
    }
  }

  Future<void> _save() async {
    if (_editor.saving || _categoryBusy || !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final saved = await _editor.save(
      Product(
        id: _id,
        name: _name.text.trim(),
        nameOnly: widget.product?.nameOnly ?? true,
        brand: widget.product?.brand ?? '',
        variant: widget.product?.variant ?? '',
        size: _size.text.trim(),
        category: _category.text.trim(),
        barcode: widget.product?.barcode ?? '',
        photoPath: _photoPath,
        markupPercent: widget.product?.markupPercent,
        sellingPriceCents: widget.product?.sellingPriceCents,
      ),
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    for (final controller in [_name, _size, _category]) {
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
      enabled: !_editor.saving && !_categoryBusy,
      label: label,
      helper: helper,
      hint: hint,
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Enter $label.' : null,
    ),
  );

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    dirty: _dirty,
    busy: _editor.saving || _categoryBusy,
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
              enabled: !_editor.saving && !_categoryBusy,
              label: 'Product photo',
              onChanged: (path) => setState(() => _photoPath = path),
            ),
            const SizedBox(height: 20),
            _identityField(
              _name,
              'Product name',
              hint: 'Bear Brand Fortified Milk',
            ),
            _identityField(
              _size,
              'Size / unit',
              hint: '26g / 250ml',
            ),
            ProductCategoryField(
              adapter: widget.adapter,
              value: _category.text,
              enabled: !_editor.saving && !_categoryBusy,
              onChanged: (value) => setState(() => _category.text = value),
              onBusyChanged: (value) => setState(() => _categoryBusy = value),
            ),
            const SizedBox(height: 24),
            if (widget.product != null)
              AliasManager(
                adapter: widget.adapter,
                productId: _id,
                enabled: !_editor.saving && !_categoryBusy,
              ),
            const SizedBox(height: 16),
            if (_editor.error != null) ...[
              Notice(message: userMessage(_editor.error!), warning: true),
              const SizedBox(height: AppSpacing.lg),
            ],
            AppActionButton(
              label: 'Save product',
              busy: _editor.saving || _categoryBusy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    ),
  );
}
