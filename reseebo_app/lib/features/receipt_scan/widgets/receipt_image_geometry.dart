import 'dart:math' as math;
import 'package:flutter/painting.dart';

/// Recognition pixels map into a contain-fitted scene. Image and overlays
/// share the InteractiveViewer transform, including its pan and zoom.
Rect fitReceiptBounds(
  Rect bounds, {
  required Size imageSize,
  required Size viewport,
}) {
  if (imageSize.isEmpty || viewport.isEmpty) return Rect.zero;
  final scale = math.min(
    viewport.width / imageSize.width,
    viewport.height / imageSize.height,
  );
  final offset = Offset(
    (viewport.width - imageSize.width * scale) / 2,
    (viewport.height - imageSize.height * scale) / 2,
  );
  return Rect.fromLTWH(
    offset.dx + bounds.left * scale,
    offset.dy + bounds.top * scale,
    bounds.width * scale,
    bounds.height * scale,
  );
}
