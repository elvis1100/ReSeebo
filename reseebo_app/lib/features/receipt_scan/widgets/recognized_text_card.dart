import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/models.dart';

class RecognizedTextCard extends StatelessWidget {
  const RecognizedTextCard({
    super.key,
    required this.text,
    this.enabled = true,
    this.tokens = const [],
    this.selectedTokens = const {},
    this.onTokenSelected,
  });
  final String text;
  final bool enabled;
  final List<OcrTextToken> tokens;
  final Set<int> selectedTokens;
  final ValueChanged<int>? onTokenSelected;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Recognized text'),
    subtitle: const Text(
      'Check the extracted words against the original photos.',
    ),
    children: [
      if (onTokenSelected != null && tokens.isNotEmpty) ...[
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Tap words or a number, then apply to the selected field.',
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: tokens.indexed
              .map(
                (entry) => FilterChip(
                  label: Text(entry.$2.text),
                  selected: selectedTokens.contains(entry.$1),
                  onSelected: enabled
                      ? (_) => onTokenSelected!(entry.$1)
                      : null,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: SelectableText(
          text.isEmpty
              ? 'No recognized text. Enter details from the originals.'
              : text,
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: enabled && text.isNotEmpty
              ? () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Recognized text copied.')),
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy recognized text'),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
    ],
  );
}
