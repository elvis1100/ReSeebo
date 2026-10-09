import 'package:flutter/material.dart';

import 'shared_widgets.dart';

/// Shared app identity until the final brand logo is available.
class StoreHeader extends StatelessWidget {
  const StoreHeader({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      LocalPhoto(size: 38, icon: Icons.receipt_long_rounded),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'Reseebo',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
    ],
  );
}
