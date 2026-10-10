import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class OverlapReviewCard extends StatelessWidget {
  const OverlapReviewCard({
    super.key,
    required this.line,
    required this.earlier,
    required this.enabled,
    required this.onKeepBoth,
    required this.onRemove,
  });
  final ParsedLineItem line;
  final ParsedLineItem? earlier;
  final bool enabled;
  final VoidCallback onKeepBoth, onRemove;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Notice(
            message:
                'Possible photo overlap: “${line.description}” on photo ${line.sourcePage + 1} matches a row on photo ${(earlier?.sourcePage ?? 0) + 1}. Check both originals before deciding.',
            warning: true,
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: enabled ? onKeepBoth : null,
                child: const Text('Keep both purchases'),
              ),
              OutlinedButton(
                onPressed: enabled ? onRemove : null,
                child: const Text('Remove overlapping row'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
