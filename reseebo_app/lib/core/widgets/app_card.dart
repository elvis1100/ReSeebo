import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Reusable card container with standard borders, paddings, and optional header.
class AppCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);

    if (title != null || trailing != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.horizontal / 2,
              padding.vertical / 2,
              padding.horizontal / 2,
              AppSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ?trailing,
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.horizontal / 2,
              AppSpacing.s,
              padding.horizontal / 2,
              padding.vertical / 2,
            ),
            child: child,
          ),
        ],
      );
    }

    final card = Material(
      color: backgroundColor ?? AppColors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        side: const BorderSide(color: AppColors.border),
      ),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
              child: content,
            ),
    );
    return card;
  }
}
