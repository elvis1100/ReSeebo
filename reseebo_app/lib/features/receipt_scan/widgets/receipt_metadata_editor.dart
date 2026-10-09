import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/widgets/shared_widgets.dart';

class ReceiptMetadataEditor extends StatefulWidget {
  const ReceiptMetadataEditor({
    super.key,
    required this.draft,
    required this.suppliers,
    required this.onChanged,
    required this.onEditSupplier,
    this.enabled = true,
  });
  final ReceiptDraft draft;
  final List<Supplier> suppliers;
  final VoidCallback onChanged;
  final ValueChanged<Supplier?> onEditSupplier;
  final bool enabled;
  @override
  State<ReceiptMetadataEditor> createState() => _ReceiptMetadataEditorState();
}

class _ReceiptMetadataEditorState extends State<ReceiptMetadataEditor> {
  late final TextEditingController _supplier, _branch, _number, _notes;

  @override
  void initState() {
    super.initState();
    _supplier = TextEditingController(text: widget.draft.supplierName);
    _branch = TextEditingController(text: widget.draft.supplierBranch);
    _number = TextEditingController(text: widget.draft.receiptNumber);
    _notes = TextEditingController(text: widget.draft.notes);
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
                  'Choose supplier branch',
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
                          'No suppliers yet. Enter a name and branch on the receipt.',
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
      _branch.text = supplier.branch;
      widget.draft.supplierName = supplier.name;
      widget.draft.supplierId = supplier.id;
      widget.draft.supplierBranch = supplier.branch;
      widget.draft.supplierNotes = '';
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
    widget.onChanged();
  }

  Future<void> _chooseTime() async {
    final date = widget.draft.purchasedAt;
    if (date == null) return;
    final selected = await showTimePicker(
      context: context,
      initialTime: widget.draft.hasPurchaseTime
          ? TimeOfDay.fromDateTime(date)
          : const TimeOfDay(hour: 12, minute: 0),
    );
    if (selected == null || !mounted) return;
    widget.draft.purchasedAt = DateTime(
      date.year,
      date.month,
      date.day,
      selected.hour,
      selected.minute,
    );
    widget.draft.hasPurchaseTime = true;
    widget.draft.dateConfirmed = false;
    widget.onChanged();
  }

  @override
  void didUpdateWidget(covariant ReceiptMetadataEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_supplier.text != widget.draft.supplierName) {
      _supplier.text = widget.draft.supplierName;
    }
    if (_branch.text != widget.draft.supplierBranch) {
      _branch.text = widget.draft.supplierBranch;
    }
  }

  void _clearSupplierSelection() {
    widget.draft.supplierId = null;
    widget.draft.supplierNotes = '';
  }

  @override
  void dispose() {
    for (final controller in [_supplier, _branch, _number, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Purchase details', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        AppField(
          controller: _supplier,
          enabled: widget.enabled,
          label: 'Supplier name',
          onChanged: (value) {
            _clearSupplierSelection();
            draft.supplierName = value;
            widget.onChanged();
          },
          validator: (value) =>
              value!.trim().isEmpty ? 'Enter supplier name.' : null,
        ),
        const SizedBox(height: 16),
        AppField(
          controller: _branch,
          enabled: widget.enabled,
          label: 'Branch / location (optional)',
          onChanged: (value) {
            _clearSupplierSelection();
            draft.supplierBranch = value;
            widget.onChanged();
          },
        ),
        Wrap(
          spacing: 8,
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.enabled ? _chooseDate : null,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            draft.purchasedAt == null
                ? 'Choose purchase date'
                : purchaseDate(
                    draft.purchasedAt!,
                    withTime: draft.hasPurchaseTime,
                  ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: widget.enabled && draft.purchasedAt != null
                  ? _chooseTime
                  : null,
              child: Text(
                draft.hasPurchaseTime
                    ? 'Change purchase time'
                    : 'Add time from receipt',
              ),
            ),
            if (draft.hasPurchaseTime)
              TextButton(
                onPressed: widget.enabled
                    ? () {
                        final date = draft.purchasedAt!;
                        draft.purchasedAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                        );
                        draft.hasPurchaseTime = false;
                        draft.dateConfirmed = false;
                        widget.onChanged();
                      }
                    : null,
                child: const Text('Time unknown'),
              ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            draft.hasPurchaseTime
                ? 'I checked the purchase date and time'
                : 'I checked the purchase date; time is unknown',
          ),
          value: draft.dateConfirmed,
          onChanged: widget.enabled && draft.purchasedAt != null
              ? (value) {
                  draft.dateConfirmed = value ?? false;
                  widget.onChanged();
                }
              : null,
        ),
        const SizedBox(height: 12),
        AppField(
          controller: _number,
          enabled: widget.enabled,
          label: 'Receipt number (optional)',
          onChanged: (value) {
            draft.receiptNumber = value;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        AppField(
          controller: _notes,
          enabled: widget.enabled,
          maxLines: 3,
          label: 'Receipt notes (optional)',
          onChanged: (value) {
            draft.notes = value;
            widget.onChanged();
          },
        ),
      ],
    );
  }
}
