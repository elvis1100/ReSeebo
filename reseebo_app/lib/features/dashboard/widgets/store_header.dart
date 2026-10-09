import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class StoreHeader extends StatelessWidget {
  const StoreHeader({super.key, required this.profile, required this.onBasket});
  final StoreProfile profile;
  final VoidCallback onBasket;
  @override
  Widget build(BuildContext context) => Container(
    padding: AppSpacing.page,
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppRadii.hero),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalPhoto(
              path: profile.photoPath,
              icon: Icons.storefront_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name.isEmpty ? 'Your tindahan' : profile.name,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tindahan Price & Tubo Tracker',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            const _HeaderBadge(
              icon: Icons.wifi_off,
              label: 'On this phone · Offline',
            ),
            _HeaderBadge(
              icon: Icons.percent,
              label: profile.defaultMarkupPercent == null
                  ? 'Choose a markup in profile'
                  : 'Default markup ${percent(profile.defaultMarkupPercent!)}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
          ),
          onPressed: onBasket,
          icon: const Icon(Icons.shopping_basket_outlined),
          label: const Text('Plan a buying basket'),
        ),
      ],
    ),
  );
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
