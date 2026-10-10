import 'package:flutter/material.dart';

import 'digital_receipt_preview.dart';
import '../state/receipt_review_state.dart';
import 'receipt_scan_steps.dart';

class ReceiptSavePreview extends StatelessWidget {
  const ReceiptSavePreview({
    super.key,
    required this.review,
    required this.onBack,
  });

  final ReceiptReviewState review;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ReceiptScanSteps(activeStep: 2),
        const SizedBox(height: 20),
        Text(
          'Ready to save?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Check your digital receipt before saving.'),
        const SizedBox(height: 16),
        DigitalReceiptPreview(review: review),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: review.saving ? null : onBack,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Back to review'),
        ),
        const SizedBox(height: 8),
        const Text('Save to this device', textAlign: TextAlign.center),
      ],
    );
  }
}
