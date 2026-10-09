import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../catalog/screens/product_editor_screen.dart';

class ProductMatchPicker extends StatefulWidget {
  const ProductMatchPicker({
    super.key,
    required this.adapter,
    required this.description,
  });
  final IReseeboDataAdapter adapter;
  final String description;
  @override
  State<ProductMatchPicker> createState() => _ProductMatchPickerState();
}

class _ProductMatchPickerState extends State<ProductMatchPicker> {
  List<Product>? _products;
  List<ProductMatchSuggestion> _suggestions = [];
  String _query = '';
  String? _error;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await widget.adapter.getProducts();
      final suggestions = await widget.adapter.matchAliases(widget.description);
      if (mounted) {
        setState(() {
          _products = products;
          _suggestions = suggestions;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductEditorScreen(adapter: widget.adapter),
      ),
    );
    if (!mounted) return;
    if (created == true) await _load();
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final suggestedIds = _suggestions
        .map((suggestion) => suggestion.product.id)
        .toSet();
    final products = (_products ?? [])
        .where(
          (product) => '${product.name} ${product.identity}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Match exact product',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              widget.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search brand, variant, size',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _adding ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add a new product'),
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ] else if (_products == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_query.isEmpty && _suggestions.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Suggested matches · check before choosing'),
                ),
                ..._suggestions.map(
                  (suggestion) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link),
                    title: Text(suggestion.product.name),
                    subtitle: Text(
                      '${suggestion.product.identity}\n${suggestion.reason}',
                    ),
                    isThreeLine: true,
                    onTap: () => Navigator.pop(context, suggestion.product),
                  ),
                ),
                const Divider(),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Your product catalog'),
              ),
              if (products.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No matching products. Add the exact product above.',
                  ),
                ),
              ...products
                  .where(
                    (product) =>
                        _query.isNotEmpty || !suggestedIds.contains(product.id),
                  )
                  .map(
                    (product) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(product.name),
                      subtitle: Text(product.identity),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, product),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
