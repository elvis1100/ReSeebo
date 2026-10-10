import 'package:flutter/material.dart';

import '../state/receipt_review_state.dart';
import 'receipt_image_viewer.dart';
import 'recognized_text_card.dart';

/// Original photos and extracted text are evidence, not field assignment tools.
class ReceiptPhotoReviewPanel extends StatelessWidget {
  const ReceiptPhotoReviewPanel({super.key, required this.review});
  final ReceiptReviewState review;

  @override
  Widget build(BuildContext context) {
    final pages = review.pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    final page = pages[review.selectedPage];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pages.length > 1)
          Wrap(
            spacing: 6,
            children: pages.indexed
                .map(
                  (entry) => ChoiceChip(
                    label: Text('Photo ${entry.$1 + 1}'),
                    selected: entry.$1 == review.selectedPage,
                    onSelected: review.saving
                        ? null
                        : (_) => review.selectPage(entry.$1),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 8),
        ReceiptImageViewer(
          imagePath: page.imagePath,
          height: 280,
          imageLabel: 'Original photo',
        ),
        RecognizedTextCard(
          text: page.textLines.map((line) => line.text).join('\n'),
        ),
      ],
    );
  }
}
