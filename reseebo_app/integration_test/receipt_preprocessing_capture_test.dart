import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';

/// Diagnostic-only: identical bundled OCR for locally supplied pixel variants.
/// Receipt text stays in private evidence files, never routine test logs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const folder = String.fromEnvironment('RECEIPT_SAMPLE_DIR');
  const names = String.fromEnvironment('RECEIPT_SAMPLE_NAMES');
  testWidgets(
    'capture preprocessing variants with bundled OCR',
    (tester) async {
      expect(folder, isNotEmpty);
      expect(names, isNotEmpty);
      final support = await getApplicationSupportDirectory();
      final output = await support.createTemp('preprocessing-captures-');
      debugPrint('Preprocessing evidence directory: ${output.path}');
      final ocr = MlKitOcrService();
      try {
        for (final name in names.split(',')) {
          expect(RegExp(r'^[a-z0-9_-]+$').hasMatch(name), isTrue);
          final source = File('$folder/$name.jpg');
          expect(await source.exists(), isTrue);
          final watch = Stopwatch()..start();
          final lines = await ocr.recognize(source.path);
          watch.stop();
          await File('${output.path}/$name.json').writeAsString(
            jsonEncode({
              'id': name,
              'engine': 'bundled Android ML Kit Latin',
              'imageSha256': sha256
                  .convert(await source.readAsBytes())
                  .toString(),
              'elapsedMilliseconds': watch.elapsedMilliseconds,
              'lines': [
                for (final line in lines)
                  {
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
                  },
              ],
            }),
          );
        }
      } finally {
        await ocr.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
