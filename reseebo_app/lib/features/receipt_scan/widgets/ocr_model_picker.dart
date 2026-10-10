import 'package:flutter/material.dart';

import '../../../core/models/ocr_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../models/scan_result.dart';

class OcrModelPicker extends StatelessWidget {
  const OcrModelPicker({
    super.key,
    required this.engines,
    required this.selected,
    required this.results,
    required this.onSelected,
    this.enabled = true,
  });
  final List<OcrEngineDescriptor> engines;
  final OcrEngineId selected;
  final Map<OcrEngineId, ScanResult> results;
  final Future<void> Function(OcrEngineId) onSelected;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<OcrEngineId>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose OCR model',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close model selector',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  children: [
                    const Text(
                      'Selecting a model keeps your photos. Tap Read receipt to run it.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final engine in engines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Material(
                          color: engine.id == selected
                              ? AppColors.softPrimary
                              : AppColors.surfaceCard,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            enabled: engine.available,
                            selected: engine.id == selected,
                            contentPadding: const EdgeInsets.all(AppSpacing.md),
                            leading: Icon(
                              Icons.document_scanner_outlined,
                              color: engine.available
                                  ? null
                                  : AppColors.textMuted,
                            ),
                            title: Text(
                              engine.label,
                              style: engine.available
                                  ? null
                                  : const TextStyle(color: AppColors.textMuted),
                            ),
                            subtitle: Text(
                              !engine.available
                                  ? 'Unavailable in this version. Use ML Kit Latin.'
                                  : results[engine.id]?.error != null
                                  ? 'Reading failed · retry available'
                                  : results.containsKey(engine.id)
                                  ? 'Result ready for current photos'
                                  : 'Not read yet',
                              style: engine.available
                                  ? null
                                  : const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                            ),
                            trailing: engine.id == selected
                                ? const Icon(Icons.check_rounded)
                                : !engine.available
                                ? const Icon(
                                    Icons.lock_outline_rounded,
                                    color: AppColors.textMuted,
                                  )
                                : null,
                            onTap: engine.available
                                ? () => Navigator.pop(context, engine.id)
                                : null,
                          ),
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
    if (picked != null) await onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final label =
        engines.where((engine) => engine.id == selected).firstOrNull?.label ??
        'ML Kit Latin';
    return Semantics(
      label: 'Selected OCR model: $label',
      button: true,
      child: OutlinedButton(
        onPressed: enabled ? () => _open(context) : null,
        style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.document_scanner_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label)),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
