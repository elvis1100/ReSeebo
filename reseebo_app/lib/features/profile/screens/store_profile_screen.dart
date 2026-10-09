import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/state/local_editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../widgets/photo_editor.dart';

class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({super.key, required this.adapter});
  final IReseeboDataAdapter adapter;
  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _markup = TextEditingController();
  late final LocalEditorController<StoreProfile> _editor;
  List<String> _initial = ['', '', ''];
  String? _photoPath;
  String? _initialPhoto;
  List<TextEditingController> get _fields => [_name, _owner, _markup];
  bool get _dirty =>
      _photoPath != _initialPhoto ||
      _fields.indexed.any((entry) => entry.$2.text != _initial[entry.$1]);

  @override
  void initState() {
    super.initState();
    _editor = LocalEditorController(
      read: widget.adapter.getStoreProfile,
      write: widget.adapter.updateStoreProfile,
    )..addListener(_changed);
    for (final field in _fields) {
      field.addListener(_changed);
    }
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _editor.load();
    if (!mounted || _editor.error != null) return;
    final profile = _editor.value!;
    _name.text = profile.name;
    _owner.text = profile.ownerName;
    _markup.text = profile.defaultMarkupPercent?.toString() ?? '';
    setState(() {
      _photoPath = _initialPhoto = profile.photoPath;
      _initial = _fields.map((field) => field.text).toList();
    });
  }

  Future<void> _save() async {
    if (_editor.saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final saved = await _editor.save(
      StoreProfile(
        name: _name.text.trim(),
        ownerName: _owner.text.trim(),
        photoPath: _photoPath,
        defaultMarkupPercent: _markup.text.trim().isEmpty
            ? null
            : parseMarkup(_markup.text),
      ),
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    dirty: _dirty,
    busy: _editor.saving,
    saved: _editor.saved,
    child: Scaffold(
      appBar: AppBar(title: const Text('Your tindahan')),
      body: _editor.loading
          ? const Center(child: CircularProgressIndicator())
          : _editor.value == null && _editor.error != null
          ? ErrorState(message: userMessage(_editor.error!), onRetry: _load)
          : Form(
              key: _form,
              child: ListView(
                padding: AppSpacing.page,
                children: [
                  const Text(
                    'Profile setup is optional. Enter a store name when saving these details.',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PhotoEditor(
                    path: _photoPath,
                    enabled: !_editor.saving,
                    label: 'Store logo or photo',
                    onChanged: (path) => setState(() => _photoPath = path),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppField(
                    controller: _name,
                    enabled: !_editor.saving,
                    label: 'Store name',
                    validator: (value) =>
                        value!.trim().isEmpty ? 'Enter your store name.' : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppField(
                    controller: _owner,
                    enabled: !_editor.saving,
                    label: 'Owner name (optional)',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppField(
                    controller: _markup,
                    enabled: !_editor.saving,
                    label: 'Default markup (%)',
                    helper:
                        'Optional. Leave blank to decide later. 0% means at cost.',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        value!.trim().isEmpty || parseMarkup(value) != null
                        ? null
                        : 'Enter a markup from 0 to 10,000%.',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    'Product markup overrides this default when set. Changing markup keeps earlier purchases and costs intact.',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_editor.error != null) ...[
                    Notice(message: userMessage(_editor.error!), warning: true),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  AppActionButton(
                    label: 'Save store details',
                    busy: _editor.saving,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
    ),
  );
}
