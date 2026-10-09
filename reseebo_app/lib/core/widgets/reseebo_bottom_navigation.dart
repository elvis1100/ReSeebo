import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Scan is an action between the two persistent tabs, never a selected tab.
class ReseeboBottomNavigation extends StatelessWidget {
  const ReseeboBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onScan,
  });
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onScan;

  Widget _tab(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    IconData selectedIcon,
  ) {
    final selected = selectedIndex == index;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: InkWell(
            onTap: () => onTabSelected(index),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 70,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? selectedIcon : icon,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96 + MediaQuery.paddingOf(context).bottom,
    child: Stack(
      children: [
        Positioned.fill(
          top: 12,
          child: const Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tab(
                  context,
                  0,
                  'Home',
                  Icons.storefront_outlined,
                  Icons.storefront_rounded,
                ),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Scan Receipt',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onScan,
                      child: Column(
                        children: [
                          Tooltip(
                            message: 'Scan Receipt',
                            child: Material(
                              key: const ValueKey('bottom-scan-action'),
                              color: AppColors.primary,
                              elevation: 4,
                              shadowColor: AppColors.primary.withValues(
                                alpha: .3,
                              ),
                              shape: const CircleBorder(
                                side: BorderSide(color: Colors.white, width: 3),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: onScan,
                                customBorder: const CircleBorder(),
                                child: const SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Icon(
                                    Icons.document_scanner_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Scan Receipt',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _tab(
                  context,
                  1,
                  'Settings',
                  Icons.settings_outlined,
                  Icons.settings_rounded,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
