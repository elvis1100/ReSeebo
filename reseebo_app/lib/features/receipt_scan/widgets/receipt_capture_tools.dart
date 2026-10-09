import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ReceiptCaptureTools extends StatelessWidget {
  const ReceiptCaptureTools({
    super.key,
    required this.enabled,
    required this.enhance,
    required this.onCrop,
    required this.onRotate,
    required this.onStraighten,
    required this.onReset,
    required this.onEnhanceChanged,
  });

  final bool enabled;
  final bool enhance;
  final VoidCallback onCrop, onRotate, onStraighten, onReset;
  final ValueChanged<bool> onEnhanceChanged;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: const Icon(Icons.tune_rounded, color: AppColors.primary),
      title: const Text('Adjust photo'),
      subtitle: const Text('Only if the receipt is tilted or hard to read'),
      childrenPadding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.crop),
              label: const Text('Crop'),
              onPressed: enabled ? onCrop : null,
            ),
            TextButton.icon(
              icon: const Icon(Icons.rotate_right),
              label: const Text('Rotate'),
              onPressed: enabled ? onRotate : null,
            ),
            TextButton.icon(
              icon: const Icon(Icons.straighten),
              label: const Text('Straighten'),
              onPressed: enabled ? onStraighten : null,
            ),
            TextButton.icon(
              icon: const Icon(Icons.undo),
              label: const Text('Reset edits'),
              onPressed: enabled ? onReset : null,
            ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Make faded text clearer'),
          subtitle: const Text('Your original photo is always kept.'),
          value: enhance,
          onChanged: enabled ? onEnhanceChanged : null,
        ),
      ],
    ),
  );
}
