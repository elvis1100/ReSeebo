import 'package:uuid/uuid.dart';

/// Originals stay fixed while a separate recognition copy may be edited.
class CapturePage {
  CapturePage({required this.originalPath, this.originalHash})
    : id = const Uuid().v4();
  final String id;
  final String originalPath;
  String? originalHash;
  String? recognitionPath;
  String? preparedPath;
  String? originalPreparedPath;
  bool useOriginal = false;
  bool enhance = true;
  double contrast = 1;
  String get editedPath => recognitionPath ?? originalPath;
  String get previewPath => useOriginal
      ? originalPath
      : preparedPath ?? editedPath;
}
