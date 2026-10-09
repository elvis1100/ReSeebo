import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/state/local_editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';

class SupplierEditorScreen extends StatefulWidget {
  const SupplierEditorScreen({super.key, required this.adapter, this.supplier});
  final IReseeboDataAdapter adapter;
  final Supplier? supplier;
  @override
  State<SupplierEditorScreen> createState() => _SupplierEditorScreenState();
}

class _SupplierEditorScreenState extends State<SupplierEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final String _id;
  late final LocalEditorController<Supplier> _editor;
  late final List<String> _initial;
  List<TextEditingController> get _fields => [_name, _notes];
  bool get _dirty =>
      _fields.indexed.any((entry) => entry.$2.text != _initial[entry.$1]);
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _id = widget.supplier?.id ?? const Uuid().v4();
    _name = TextEditingController(text: widget.supplier?.name);
    _notes = TextEditingController(text: widget.supplier?.notes);
    _initial = _fields.map((field) => field.text).toList();
    _editor = LocalEditorController(write: widget.adapter.saveSupplier)
      ..addListener(_changed);
    for (final field in _fields) {
      field.addListener(_changed);
    }
  }

  Future<void> _save() async {
    if (_editor.saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await _editor.save(
      Supplier(
        id: _id,
        name: _name.text.trim(),
        branch: widget.supplier?.branch ?? '',
        notes: _notes.text.trim(),
      ),
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    dirty: _dirty,
    busy: _editor.saving,
    saved: _editor.saved,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier == null ? 'Add supplier' : 'Edit supplier'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: AppSpacing.page,
          children: [
            AppField(
              controller: _name,
              enabled: !_editor.saving,
              label: 'Supplier name',
              validator: (value) =>
                  value!.trim().isEmpty ? 'Enter the supplier name.' : null,
            ),
            const SizedBox(height: 16),
            AppField(
              controller: _notes,
              enabled: !_editor.saving,
              minLines: 3,
              maxLines: 5,
              label: 'Notes (optional)',
            ),
            const SizedBox(height: 24),
            if (_editor.error != null) ...[
              Notice(message: userMessage(_editor.error!), warning: true),
              const SizedBox(height: AppSpacing.lg),
            ],
            AppActionButton(
              label: 'Save supplier',
              busy: _editor.saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    ),
  );
}
