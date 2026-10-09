import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/capture_page.dart';

class CapturePageStrip extends StatelessWidget {
  const CapturePageStrip({
    super.key,
    required this.pages,
    required this.selectedIndex,
    required this.onSelected,
    required this.enabled,
  });
  final List<CapturePage> pages;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool enabled;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 124,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: pages.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (context, index) => Semantics(
        selected: index == selectedIndex,
        button: true,
        child: InkWell(
          onTap: enabled ? () => onSelected(index) : null,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Container(
            key: ValueKey(pages[index].id),
            width: 108,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(
                color: index == selectedIndex
                    ? AppColors.primary
                    : AppColors.border,
                width: index == selectedIndex ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Image.file(
                    File(pages[index].previewPath),
                    fit: BoxFit.cover,
                    cacheWidth: 220,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.receipt_long_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Page ${index + 1}'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
