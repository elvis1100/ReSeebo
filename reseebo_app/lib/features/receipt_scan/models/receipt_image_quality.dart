/// Pixel-variance measurements for conservative pre-OCR photo triage.
/// These values are not probabilities of recognition accuracy.
class ReceiptImageQuality {
  const ReceiptImageQuality({
    required this.width,
    required this.height,
    required this.sharpness,
    required this.contrast,
  });
  final int width;
  final int height;
  final double sharpness;
  final double contrast;

  // The owner can override triage or enter details manually for a faded print.
  bool get needsRetake =>
      width < 240 || height < 240 || contrast < 16 || sharpness < 12;
}
