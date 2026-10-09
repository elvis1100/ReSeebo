import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class BasketProductChooser extends StatefulWidget {
  const BasketProductChooser({super.key, required this.products});
  final List<Product> products;
  @override
  State<BasketProductChooser> createState() => _BasketProductChooserState();
}

class _BasketProductChooserState extends State<BasketProductChooser> {
  final search = TextEditingController();
  String query = '';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.products
        .where(
          (product) =>
              '${product.name} ${product.identity} ${product.category} ${product.barcode}'
                  .toLowerCase()
                  .contains(query.toLowerCase().trim()),
        )
        .toList();
    return Padding(
      padding: AppSpacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Choose a product',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close product chooser',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppField(
            controller: search,
            label: 'Search products',
            hint: 'Name, brand, variant, size or barcode',
            onChanged: (value) => setState(() => query = value),
            suffixIcon: IconButton(
              tooltip: 'Clear product search',
              onPressed: () {
                search.clear();
                setState(() => query = '');
              },
              icon: const Icon(Icons.close),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: matches.isEmpty
                ? const Center(
                    child: Text(
                      'No matching products. Try another brand or size.',
                    ),
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final product = matches[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: LocalPhoto(path: product.photoPath),
                        title: Text(product.name),
                        subtitle: Text(product.identity),
                        trailing: const Icon(
                          Icons.add,
                          color: AppColors.primary,
                        ),
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          Navigator.pop(context, product);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
