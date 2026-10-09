import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

class RecognizedTextCard extends StatelessWidget {
  const RecognizedTextCard({
    super.key,
    required this.text,
    this.enabled = true,
  });
  final String text;
  final bool enabled;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Recognized text'),
    subtitle: const Text(
      'Check the extracted words against the original photos.',
    ),
    children: [
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
