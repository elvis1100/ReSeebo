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
  String get previewPath => recognitionPath ?? originalPath;
}
