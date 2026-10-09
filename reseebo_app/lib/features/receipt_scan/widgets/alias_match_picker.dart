import 'package:flutter/material.dart';
import '../../../core/models/product.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';

/// Modal dialog/bottom sheet for resolving raw OCR strings to known catalog products
/// and training local aliases.
class AliasMatchPicker extends StatefulWidget {
  final String rawOcrText;
  final List<Product> availableProducts;
  final List<ProductMatchSuggestion> suggestions;
  final Product? currentlySelected;
  final ValueChanged<Product> onProductConfirmed;

  const AliasMatchPicker({
    super.key,
    required this.rawOcrText,
    required this.availableProducts,
    required this.suggestions,
    this.currentlySelected,
    required this.onProductConfirmed,
  });

  static Future<Product?> show(
    BuildContext context, {
    required String rawOcrText,
    required List<Product> availableProducts,
    required List<ProductMatchSuggestion> suggestions,
    Product? currentlySelected,
  }) {
    return showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AliasMatchPicker(
        rawOcrText: rawOcrText,
        availableProducts: availableProducts,
        suggestions: suggestions,
        currentlySelected: currentlySelected,
        onProductConfirmed: (p) => Navigator.of(context).pop(p),
      ),
    );
  }

  @override
  State<AliasMatchPicker> createState() => _AliasMatchPickerState();
}

class _AliasMatchPickerState extends State<AliasMatchPicker> {
  final TextEditingController _searchController = TextEditingController();
  Product? _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.currentlySelected;
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    if (_query.isEmpty) return widget.availableProducts;
    return widget.availableProducts.where((p) {
      return p.displayTitle.toLowerCase().contains(_query) ||
          p.category.toLowerCase().contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSpacing.radiusL),
          topRight: Radius.circular(AppSpacing.radiusL),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: AppSpacing.s),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.m,
              AppSpacing.s,
              AppSpacing.m,
              AppSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Match Product', style: AppTypography.headingMedium),
                    const SizedBox(height: 2),
                    Text(
                      'OCR says: "${widget.rawOcrText}"',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(),

          // Search input
          Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search product catalog...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),

          // Product list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              itemCount: _filteredProducts.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
                final isSelected = _selected?.id == product.id;

                // Check if this product was among suggested aliases
                final match = widget.suggestions.cast<ProductMatchSuggestion?>().firstWhere(
                      (s) => s?.product.id == product.id,
                      orElse: () => null,
                    );

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: 2,
                  ),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: isSelected ? Colors.white : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    product.displayTitle,
                    style: AppTypography.headingSmall.copyWith(
                      fontSize: 14,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      if (match != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.priceCheaperBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Suggested (${(match.confidence * 100).toInt()}%)',
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.priceCheaper,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s),
                      ],
                      Text(
                        product.sizeUnit,
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      _selected = product;
                    });
                  },
                );
              },
            ),
          ),

          // Confirm button footer
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: AppButton(
                label: _selected != null
                    ? 'Confirm & Remember Alias'
                    : 'Select a Product',
                icon: Icons.check_rounded,
                isFullWidth: true,
                onPressed: _selected != null
                    ? () => widget.onProductConfirmed(_selected!)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
