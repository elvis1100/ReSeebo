import 'package:flutter/material.dart';

class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .06),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: ClipPath(
      clipper: const ReceiptPaperClipper(),
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
          child: child,
        ),
      ),
    ),
  );
}

class ReceiptPaperClipper extends CustomClipper<Path> {
  const ReceiptPaperClipper();
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - 7);
    final teeth = (size.width / 16).ceil();
    final step = size.width / teeth;
    for (var index = teeth; index > 0; index--) {
      path
        ..lineTo((index - .5) * step, size.height)
        ..lineTo((index - 1) * step, size.height - 7);
    }
    return path..close();
  }

  @override
  bool shouldReclip(ReceiptPaperClipper oldClipper) => false;
}
