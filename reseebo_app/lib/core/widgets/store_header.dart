import 'package:flutter/material.dart';

import 'brand_logo.dart';

/// Shared app identity across the store and settings screens.
class StoreHeader extends StatelessWidget {
  const StoreHeader({super.key});

  @override
  Widget build(BuildContext context) =>
      Row(children: [const Flexible(child: BrandLogo())]);
}
