/// Applied photo settings. Both paths refer to generated cache files; original
/// evidence is owned by CapturePage and is never replaced by an editor result.
class ReceiptPhotoEdits {
  const ReceiptPhotoEdits({
    this.editedPath,
    required this.enhancedPath,
    required this.useOriginal,
    required this.enhance,
    required this.contrast,
  });

  final String? editedPath;
  final String enhancedPath;
  final bool useOriginal;
  final bool enhance;
  final double contrast;
}
