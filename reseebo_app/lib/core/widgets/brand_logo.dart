import 'package:flutter/material.dart';

/// Displays the original bundled wordmark with its transparent margins fitted
/// to a compact slot; the source artwork and colors remain unchanged.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 150});
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Reseebo',
    image: true,
    child: ExcludeSemantics(
      child: Image.asset(
        'assets/brand/reseebo_logo.png',
        width: width,
        height: width / 4.2,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}
