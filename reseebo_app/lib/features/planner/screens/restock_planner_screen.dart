import 'package:flutter/material.dart';
import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/models/product.dart';
import '../../../core/models/restock_estimate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../widgets/profit_tubo_card.dart';
import '../widgets/restock_planner_card.dart';

/// Screen enabling store owners to plan restock purchases, round up to whole
/// packs, factor in travel fares, and evaluate gross profit (*tubo*).
class RestockPlannerScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final String productId;
  final VoidCallback? onBack;

  const RestockPlannerScreen({
    super.key,
    required this.dataAdapter,
    required this.productId,
    this.onBack,
  });

  @override
  State<RestockPlannerScreen> createState() => _RestockPlannerScreenState();
}

class _RestockPlannerScreenState extends State<RestockPlannerScreen> {
  Product? _product;
  RestockEstimate? _estimate;
  ProfitCalculation? _profitCalc;

  int _targetPieces = 50;
  double _additionalCost = 50.0; // Standard local tricycle/jeep round-trip fare
  double _markupPercentage = 15.0;
  double? _customPrice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final product = await widget.dataAdapter.getProductById(widget.productId);
    final profile = await widget.dataAdapter.getStoreProfile();

    _product = product;
    _markupPercentage =
        product?.markupPercentageOverride ?? profile.defaultMarkupPercentage;
    _customPrice = product?.ownerSetSellingPrice;

    await _recalculate();
  }

  Future<void> _recalculate() async {
    final estimate = await widget.dataAdapter.calculateRestock(
      productId: widget.productId,
      targetPieces: _targetPieces,
      additionalCost: _additionalCost,
    );

    final bestCostPerPiece =
        estimate.recommendedSupplier != null && estimate.recommendedSupplier!.piecesPerPack > 0
            ? estimate.recommendedSupplier!.packCost / estimate.recommendedSupplier!.piecesPerPack
            : 8.0;

    final profit = await widget.dataAdapter.calculateProfit(
      productId: widget.productId,
      costPerPiece: bestCostPerPiece,
      customMarkupPercentage: _markupPercentage,
      customSellingPrice: _customPrice,
    );

    if (mounted) {
      setState(() {
        _estimate = estimate;
        _profitCalc = profit;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _product?.displayTitle ?? 'Restock & Profit Planner',
          style: AppTypography.headingMedium.copyWith(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Target pieces selection & Travel cost inputs
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target Inventory Pieces',
                          style: AppTypography.headingSmall.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'How many pieces do you want to restock for your store?',
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.s),

                        // Quick piece amount selector chips
                        Row(
                          children: [20, 50, 100, 150].map((count) {
                            final isSelected = _targetPieces == count;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                child: InkWell(
                                  onTap: () {
                                    setState(() => _targetPieces = count);
                                    _recalculate();
                                  },
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.radiusS),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.surfaceSubtle,
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusS,
                                      ),
                                    ),
                                    child: Text(
                                      '$count pcs',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppSpacing.m),

                        // Travel fare input (tricycle / jeepney pamasahe)
                        Row(
                          children: [
                            const Icon(
                              Icons.directions_bus_rounded,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: AppSpacing.s),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Travel Fare / Pamasahe (₱)',
                                    style: AppTypography.caption.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Tricycle or jeep fare to and from market',
                                    style: AppTypography.caption,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              height: 38,
                              child: TextFormField(
                                initialValue:
                                    _additionalCost.toStringAsFixed(0),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: AppTypography.tableCellNumber,
                                decoration: InputDecoration(
                                  prefixText: '₱',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.all(8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusXs,
                                    ),
                                  ),
                                ),
                                onChanged: (val) {
                                  final d = double.tryParse(val) ?? 0.0;
                                  setState(() => _additionalCost = d);
                                  _recalculate();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),

                  // Profit & Tubo Simulation Card
                  if (_profitCalc != null) ...[
                    ProfitTuboCard(
                      calculation: _profitCalc!,
                      batchPieces: _targetPieces,
                      onMarkupChanged: (newRate) {
                        setState(() => _markupPercentage = newRate);
                        _recalculate();
                      },
                      onCustomPriceChanged: (newPrice) {
                        setState(() => _customPrice = newPrice);
                        _recalculate();
                      },
                    ),
                    const SizedBox(height: AppSpacing.m),
                  ],

                  // Supplier Comparison Restock Cards
                  Text(
                    'Supplier Restock Options',
                    style: AppTypography.headingMedium,
                  ),
                  const SizedBox(height: AppSpacing.s),
                  if (_estimate != null && _estimate!.supplierOptions.isNotEmpty) ...[
                    ..._estimate!.supplierOptions.map((opt) {
                      final isRec =
                          _estimate!.recommendedSupplier?.supplierId ==
                              opt.supplierId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s),
                        child: RestockPlannerCard(
                          option: opt,
                          isRecommended: isRec,
                          targetPieces: _targetPieces,
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
    );
  }
}
