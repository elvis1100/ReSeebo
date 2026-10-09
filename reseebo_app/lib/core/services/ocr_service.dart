import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../errors/app_exception.dart';
import '../models/models.dart';

abstract class OcrService {
  Future<List<OcrTextLine>> recognize(String imagePath);
  Future<void> close();
}

/// The Android Latin recognizer is packaged by the native ML Kit dependency.
/// Recognition remains separate from heuristic parsing and owner confirmation.
class MlKitOcrService implements OcrService {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  @override
  Future<List<OcrTextLine>> recognize(String imagePath) async {
    final result = await _recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    final lines = <OcrTextLine>[
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrTextLine(
            text: line.text,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            width: line.boundingBox.width,
            height: line.boundingBox.height,
          ),
    ];
    if (lines.isEmpty) {
      throw const ValidationException(
        'No readable receipt text was found. Try a clearer photo or enter the purchase manually.',
      );
    }
    return lines;
  }

  @override
  Future<void> close() => _recognizer.close();
}
