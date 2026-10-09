import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/widgets/shared_widgets.dart';

/// Category edits persist independently of the product form. Removing a
/// category also clears existing product assignments at the adapter boundary.
class ProductCategoryField extends StatefulWidget {
  const ProductCategoryField({
    super.key,
    required this.adapter,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.onBusyChanged,
  });
  final IReseeboDataAdapter adapter;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<ProductCategoryField> createState() => _ProductCategoryFieldState();
}

class _ProductCategoryFieldState extends State<ProductCategoryField> {
  List<String> _categories = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await widget.adapter.getProductCategories();
      if (mounted) {
        setState(() {
          _categories = values;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    var input = '';
    final form = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add category'),
        content: Form(
          key: form,
          child: TextFormField(
            onChanged: (value) => input = value,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Category name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a category name.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, input.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      await widget.adapter.addProductCategory(name);
      final values = await widget.adapter.getProductCategories();
      if (!mounted) return;
      setState(() {
        _categories = values;
        _error = null;
      });
      widget.onChanged(
        values.firstWhere((value) => value.toLowerCase() == name.toLowerCase()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _remove() async {
    final name = widget.value;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
          'Products in this category will become uncategorized. Products and purchase history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      await widget.adapter.removeProductCategory(name);
      if (!mounted) return;
      widget.onChanged('');
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = [..._categories];
    if (widget.value.isNotEmpty &&
        !categories.any(
          (name) => name.toLowerCase() == widget.value.toLowerCase(),
        )) {
      categories.add(widget.value);
    }
    final selected = widget.value.isEmpty
        ? ''
        : categories.firstWhere(
            (name) => name.toLowerCase() == widget.value.toLowerCase(),
          );
    final enabled = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => PopupMenuButton<String>(
            tooltip: 'Choose category',
            enabled: enabled,
            position: PopupMenuPosition.under,
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth,
              maxHeight: 320,
            ),
            onSelected: widget.onChanged,
            itemBuilder: (context) => [
              for (final name in ['', ...categories])
                CheckedPopupMenuItem<String>(
                  value: name,
                  checked: name == selected,
                  child: Text(
                    name.isEmpty ? 'Uncategorized' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Category (optional)',
                enabled: enabled,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected.isEmpty ? 'Uncategorized' : selected,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: enabled ? _add : null,
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Remove category',
              onPressed: enabled && widget.value.isNotEmpty ? _remove : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (_error != null) ...[
          Notice(message: _error!, warning: true),
          TextButton(
            onPressed: widget.enabled && !_busy
                ? () {
                    setState(() => _busy = true);
                    _load();
                  }
                : null,
            child: const Text('Retry'),
          ),
        ],
      ],
    );
  }
}
