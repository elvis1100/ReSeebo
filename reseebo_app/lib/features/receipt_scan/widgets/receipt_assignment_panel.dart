import 'package:flutter/material.dart';
import '../state/receipt_review_state.dart';
import 'receipt_image_viewer.dart';
import 'recognized_text_card.dart';

class ReceiptAssignmentPanel extends StatelessWidget {
  const ReceiptAssignmentPanel({
    super.key,
    required this.review,
    required this.showOriginal,
    required this.onOriginalChanged,
    required this.onApply,
    required this.onReturn,
  });
  final ReceiptReviewState review;
  final bool showOriginal;
  final ValueChanged<bool> onOriginalChanged;
  final VoidCallback onApply, onReturn;

  @override
  Widget build(BuildContext context) {
    final pages = review.pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    final page = pages[review.selectedPage];
    final selecting = review.targetField != null && !review.saving;
    final tokens = review.pageTokens;
    final targetIndex = review.draft.lines.indexWhere(
      (line) => line.id == review.targetLineId,
    );
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            showOriginal ? 'Original photo' : 'Photo used for recognition',
          ),
          subtitle: Text(
            showOriginal
                ? 'Check the preserved receipt image.'
                : 'Tap outlined words to fill the selected field.',
          ),
          value: showOriginal,
          onChanged: review.saving ? null : onOriginalChanged,
        ),
        ReceiptImageViewer(
          imagePath: showOriginal
              ? page.imagePath
              : page.recognitionImagePath ?? page.imagePath,
          height: 280,
          tokens: tokens,
          selectedTokens: review.selectedTokens,
          onTokenSelected: selecting && !showOriginal
              ? review.toggleToken
              : null,
          imageLabel: showOriginal ? 'Original photo' : 'Recognition photo',
        ),
        if (selecting) ...[
          const SizedBox(height: 8),
          Text(
            'Fill item ${targetIndex + 1} · ${review.targetField!.label}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            review.selectedText.isEmpty
                ? 'Select words or one number on the photo or in recognized text.'
                : 'Selected: ${review.selectedText}',
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: review.selectedTokens.isEmpty ? null : onApply,
                child: const Text('Apply to field'),
              ),
              TextButton(
                onPressed: onReturn,
                child: const Text('Return to item'),
              ),
            ],
          ),
        ],
        RecognizedTextCard(
          text: page.textLines.map((line) => line.text).join('\n'),
          enabled: !review.saving,
          tokens: tokens,
          selectedTokens: review.selectedTokens,
          onTokenSelected: selecting ? review.toggleToken : null,
        ),
      ],
    );
  }
}
