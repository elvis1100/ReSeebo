import 'package:flutter/material.dart';

import '../../../core/constants/formatters.dart';
import '../../../core/models/receipt_field_provenance.dart';
import '../../../core/theme/app_theme.dart';

/// Friendly origin/source wording keeps storage units and IDs out of owner UI.
class ReceiptSuggestionLabel extends StatelessWidget {
  const ReceiptSuggestionLabel({
    super.key,
    required this.provenance,
    this.fieldLabel,
    this.detail,
  });
  final ReceiptFieldProvenance? provenance;
  final String? fieldLabel;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final source = provenance;
    if (source == null) return const SizedBox.shrink();
    final origin = switch (source.origin) {
      ReceiptFieldOrigin.extracted => 'From receipt',
      ReceiptFieldOrigin.calculated => 'Calculated from receipt',
      ReceiptFieldOrigin.history => 'Estimated from confirmed history',
      ReceiptFieldOrigin.assumed => 'Suggested default · check this',
      ReceiptFieldOrigin.ownerEdited => 'Owner edited',
    };
    final supplier = source.sourceSupplierName;
    final date = source.sourcePurchasedAt;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        [
          '${fieldLabel == null ? '' : '$fieldLabel: '}$origin',
          ?detail,
          if (supplier != null && supplier.isNotEmpty) supplier,
          if (date != null) purchaseDate(date),
        ].join(' · '),
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
