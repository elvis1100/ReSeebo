import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';

/// Opt-in diagnostics for exact local photos. Captures contain receipt data;
/// pull them to /tmp, never commit full customer receipts. This does not save
/// purchases or establish accuracy: score against independently read truth.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const folder = String.fromEnvironment('RECEIPT_SAMPLE_DIR');
  const names = String.fromEnvironment('RECEIPT_SAMPLE_NAMES');
  testWidgets(
    'capture native OCR evidence for accuracy comparison',
    (tester) async {
      expect(folder, isNotEmpty);
      expect(names, isNotEmpty);
      final support = await getApplicationSupportDirectory();
      final output = await support.createTemp('accuracy-captures-');
      debugPrint('OCR evidence directory: ${output.path}');
      final ocr = MlKitOcrService();
      final images = LocalReceiptImageService();
      try {
        final samples = names.split(',');
        expect(samples.toSet().length, samples.length);
        for (final name in samples) {
          expect(RegExp(r'^[a-z0-9_-]+$').hasMatch(name), isTrue);
          final original = '$folder/$name.jpg';
          expect(await File(original).exists(), isTrue);
          final originalHash = sha256
              .convert(await File(original).readAsBytes())
              .toString();
          final enhanced = await images.prepareRecognition(
            original,
            enhance: true,
          );
          try {
            for (final pass in [
              ('original', original),
              ('enhanced', enhanced),
            ]) {
              final watch = Stopwatch()..start();
              final lines = await ocr.recognize(pass.$2);
              watch.stop();
              await File(
                '${output.path}/${name}_${pass.$1}.json',
              ).writeAsString(
                jsonEncode({
                  'id': '${name}_${pass.$1}',
                  'provenance':
                      'Native Android bundled ML Kit Latin; ${pass.$1} photo; uncorrected',
                  'sourceImageSha256': originalHash,
                  'imageSha256': sha256
                      .convert(await File(pass.$2).readAsBytes())
                      .toString(),
                  'elapsedMilliseconds': watch.elapsedMilliseconds,
                  'lines': [for (final line in lines) _line(line)],
                }),
              );
            }
            // Keep the exact enhanced pixels for the alternative engine, so the
            // comparison changes the OCR engine rather than preprocessing too.
            await File(enhanced).copy('${output.path}/${name}_enhanced.jpg');
          } finally {
            if (enhanced != original) await File(enhanced).delete();
          }
        }
      } finally {
        await ocr.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Map<String, dynamic> _line(OcrTextLine line) => {
  'text': line.text,
  'left': line.left,
  'top': line.top,
  'width': line.width,
  'height': line.height,
  'tokens': [
    for (final token in line.tokens)
      {
        'text': token.text,
        'left': token.left,
        'top': token.top,
        'width': token.width,
        'height': token.height,
      },
  ],
};
