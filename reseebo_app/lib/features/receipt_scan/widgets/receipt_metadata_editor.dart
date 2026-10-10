import 'package:flutter/material.dart';
import 'purchase_date_candidates.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/theme/app_theme.dart';

class ReceiptMetadataEditor extends StatefulWidget {
  const ReceiptMetadataEditor({
    super.key,
    required this.draft,
    required this.suppliers,
    required this.onChanged,
    required this.onEditSupplier,
    this.enabled = true,
    this.onDateCandidate,
    this.onSupplierChanged,
  });
  final ReceiptDraft draft;
  final List<Supplier> suppliers;
  final VoidCallback onChanged;
  final ValueChanged<Supplier?> onEditSupplier;
  final bool enabled;
  final Future<void> Function(PurchaseDateCandidate, bool)? onDateCandidate;
  final VoidCallback? onSupplierChanged;
  @override
  State<ReceiptMetadataEditor> createState() => _ReceiptMetadataEditorState();
}

class _ReceiptMetadataEditorState extends State<ReceiptMetadataEditor> {
  late final TextEditingController _supplier;

  @override
  void initState() {
    super.initState();
    _supplier = TextEditingController(text: widget.draft.supplierName);
  }

  Future<void> _chooseSupplier() async {
    final supplier = await showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Choose supplier',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (widget.suppliers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No suppliers yet. Enter the supplier name on the receipt.',
                        ),
                      ),
                    ...widget.suppliers.map(
                      (supplier) => ListTile(
                        title: Text(supplier.label),
                        subtitle: supplier.notes.isEmpty
                            ? null
                            : Text(supplier.notes),
                        trailing: IconButton(
                          tooltip: 'Edit supplier',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onEditSupplier(supplier);
                          },
                        ),
                        onTap: () => Navigator.pop(context, supplier),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (supplier != null && mounted) {
      _supplier.text = supplier.name;
      widget.draft.supplierName = supplier.name;
      widget.draft.supplierId = supplier.id;
      widget.draft.supplierBranch = supplier.branch;
      widget.draft.supplierNotes = '';
      widget.onSupplierChanged?.call();
      widget.onChanged();
    }
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: widget.draft.purchasedAt ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    final previous = widget.draft.purchasedAt;
    widget.draft.purchasedAt = DateTime(
      selected.year,
      selected.month,
      selected.day,
      widget.draft.hasPurchaseTime ? previous?.hour ?? 0 : 0,
      widget.draft.hasPurchaseTime ? previous?.minute ?? 0 : 0,
    );
    widget.draft.dateConfirmed = false;
    widget.draft.dateManuallyEdited = true;
    widget.draft.dateFromReceipt = false;
    widget.onChanged();
  }

  @override
  void didUpdateWidget(covariant ReceiptMetadataEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_supplier.text != widget.draft.supplierName) {
      _supplier.text = widget.draft.supplierName;
    }
  }

  void _clearSupplierSelection() {
    widget.draft.supplierId = null;
    // A typed new supplier must not inherit a hidden branch from the old match.
    widget.draft.supplierBranch = '';
    widget.draft.supplierNotes = '';
  }

  @override
  void dispose() {
    for (final controller in [_supplier]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: Theme.of(
          context,
        ).inputDecorationTheme.copyWith(fillColor: AppColors.fieldSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Purchase details',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Where and when did you buy these items?',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppField(
            controller: _supplier,
            enabled: widget.enabled,
            label: 'Supplier name',
            hint: 'Grocery store or wholesaler',
            onChanged: (value) {
              _clearSupplierSelection();
              draft.supplierName = value;
              widget.onSupplierChanged?.call();
              widget.onChanged();
            },
            validator: (value) =>
                value!.trim().isEmpty ? 'Enter supplier name.' : null,
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                onPressed: widget.enabled ? _chooseSupplier : null,
                icon: const Icon(Icons.storefront),
                label: const Text('Saved suppliers'),
              ),
              TextButton.icon(
                onPressed: widget.enabled
                    ? () => widget.onEditSupplier(null)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add supplier'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Purchase date', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.enabled ? _chooseDate : null,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                draft.purchasedAt == null
                    ? 'Choose purchase date'
                    : purchaseDate(draft.purchasedAt!, withTime: false),
              ),
            ),
          ),
          if (draft.purchasedAt == null &&
              draft.dateCandidates.isNotEmpty &&
              widget.onDateCandidate != null)
            PurchaseDateCandidates(
              candidates: draft.dateCandidates,
              canRemember: draft.supplierId != null,
              enabled: widget.enabled,
              onChoose: widget.onDateCandidate!,
            ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              draft.dateFromReceipt
                  ? 'Filled from receipt — check the purchase date.'
                  : 'Check the purchase date.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I checked the purchase date'),
            value: draft.dateConfirmed,
            onChanged: widget.enabled && draft.purchasedAt != null
                ? (value) {
                    draft.dateConfirmed = value ?? false;
                    widget.onChanged();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
