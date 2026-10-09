import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

class RecognizedTextCard extends StatelessWidget {
  const RecognizedTextCard({super.key, required this.text});
  final String text;

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
        child: Text(
          text.isEmpty
              ? 'No recognized text. Enter details from the originals.'
              : text,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
    ],
  );
}
