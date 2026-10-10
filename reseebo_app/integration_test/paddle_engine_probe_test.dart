import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';

import 'fixtures/paddle_receipt_truth.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('reseebo/ocr');
  for (final engineId in ['ppocr_v5_mobile', 'ppocr_v6_medium']) {
    testWidgets('$engineId genuine bundled inference and invalid image error', (
      tester,
    ) async {
      final manifest =
          jsonDecode(
                await rootBundle.loadString('assets/ocr/model_manifest.json'),
              )
              as Map<String, dynamic>;
      final engine = (manifest['engines'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['id'] == engineId);
      for (final artifact
          in (engine['artifacts'] as List).cast<Map<String, dynamic>>()) {
        final bytes = await rootBundle.load(artifact['path'] as String);
        expect(
          sha256
              .convert(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              )
              .toString(),
          artifact['sha256'],
        );
      }
      final directory = await getTemporaryDirectory();
      final receipt = File('${directory.path}/paddle-probe-$engineId.png');
      final invalid = File('${directory.path}/paddle-invalid-$engineId.png');
      final image = img.Image(width: 1600, height: 500);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      const truth = ['SUPPLIER A', '2 PC COFFEE 168.00', 'TOTAL 168.00'];
      for (var row = 0; row < truth.length; row++) {
        img.drawString(
          image,
          truth[row],
          font: img.arial48,
          x: 60,
          y: 50 + row * 130,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
      await receipt.writeAsBytes(img.encodePng(image));
      await invalid.writeAsBytes([1, 2, 3]);
      try {
        for (var run = 0; run < 3; run++) {
          final response = await channel.invokeMapMethod<String, dynamic>(
            'recognize',
            {'engineId': engineId, 'imagePath': receipt.path},
          );
          expect(response, isNotNull);
          expect(response!['engineId'], engineId);
          expect(response['modelVersion'], engine['modelVersion']);
          expect(response['runtimeVersion'], engine['runtimeVersion']);
          expect(response['imageWidth'], 1600);
          expect(response['imageHeight'], 500);
          final lines = (response['lines'] as List).cast<Map>();
          expect(lines, isNotEmpty);
          final text = lines.map((line) => line['text']).join('\n');
          for (final expected in truth) {
            expect(text, contains(expected));
          }
          for (final line in lines) {
            expect(line['left'] as num, greaterThanOrEqualTo(0));
            expect(line['top'] as num, greaterThanOrEqualTo(0));
            expect(line['width'] as num, greaterThan(0));
            expect(line['height'] as num, greaterThan(0));
            expect(
              (line['left'] as num) + (line['width'] as num),
              lessThanOrEqualTo(1600),
            );
            expect(
              (line['top'] as num) + (line['height'] as num),
              lessThanOrEqualTo(500),
            );
          }
          final overlay = img.Image.from(image);
          for (final line in lines) {
            final left = (line['left'] as num).round();
            final top = (line['top'] as num).round();
            img.drawRect(
              overlay,
              x1: left,
              y1: top,
              x2: (left + (line['width'] as num)).round(),
              y2: (top + (line['height'] as num)).round(),
              color: img.ColorRgb8(255, 0, 0),
              thickness: 3,
            );
          }
          final overlayPath =
              '${directory.path}/$engineId-run-$run-overlay.png';
          await File(overlayPath).writeAsBytes(img.encodePng(overlay));
          // Test output records exact fields/timings; it is not an accuracy score.
          debugPrint(
            jsonEncode({
              'probe': engineId,
              'run': run,
              'overlayPath': overlayPath,
              ...response,
            }),
          );
        }
        await expectLater(
          channel.invokeMethod<void>('recognize', {
            'engineId': engineId,
            'imagePath': invalid.path,
          }),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'invalid_image',
            ),
          ),
        );
      } finally {
        await channel.invokeMethod<void>('release');
        await receipt.delete();
        await invalid.delete();
      }
    });
  }
  for (final engineId in ['ppocr_v5_mobile', 'ppocr_v6_medium']) {
    testWidgets('$engineId genuine bundled inference on photographed receipts', (
      tester,
    ) async {
      final directory = await getTemporaryDirectory();
      // Host observer supplies developer-only photographs through run-as for
      // this exact verification package. No application network/download path.
      debugPrint(jsonEncode({'fixtureDirectory': directory.path}));
      try {
        for (final truth in paddleReceiptTruth) {
          final receipt = File(
            '${directory.path}/paddle-truth-${truth.id}.jpg',
          );
          final deadline = DateTime.now().add(const Duration(seconds: 60));
          while (!await receipt.exists() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          expect(
            await receipt.exists(),
            isTrue,
            reason: 'Host fixture missing',
          );
          final bytes = await receipt.readAsBytes();
          expect(sha256.convert(bytes).toString(), truth.sha256);
          final image = img.decodeImage(bytes)!;
          for (var run = 0; run < 3; run++) {
            final response = (await channel.invokeMapMethod<String, dynamic>(
              'recognize',
              {'engineId': engineId, 'imagePath': receipt.path},
            ))!;
            final lines = (response['lines'] as List).cast<Map>();
            expect(response['engineId'], engineId);
            expect(response['imageWidth'], image.width);
            expect(response['imageHeight'], image.height);
            final text = lines.map((line) => line['text']).join('\n');
            String normalize(String value) =>
                value.toLowerCase().replaceAll(RegExp(r'\s'), '');
            final lexicalPresence = truth.fields.map(
              (field, terms) => MapEntry(
                field,
                terms.every(
                  (term) => normalize(text).contains(normalize(term)),
                ),
              ),
            );
            final draft = ReceiptParser().parse(
              imagePath: receipt.path,
              textLines: [
                for (final line in lines)
                  OcrTextLine(
                    text: line['text'] as String,
                    left: (line['left'] as num).toDouble(),
                    top: (line['top'] as num).toDouble(),
                    width: (line['width'] as num).toDouble(),
                    height: (line['height'] as num).toDouble(),
                  ),
              ],
            );
            final parsedAgreement = <String, Object?>{
              'supplier': normalize(
                draft.supplierName,
              ).contains(normalize(truth.supplier)),
              'transactionDate':
                  draft.purchasedAt?.toIso8601String().substring(0, 10) ==
                  truth.date,
              'total': draft.detectedTotalCents == truth.totalCents,
            };
            for (final item in truth.items) {
              final matches = draft.lines
                  .where(
                    (line) => normalize(
                      line.description,
                    ).contains(normalize(item.description)),
                  )
                  .toList();
              parsedAgreement[item.description] = {
                'matchingRows': matches.length,
                'quantity':
                    matches.length == 1 &&
                    matches.single.quantity == item.quantity,
                'grossAmount':
                    matches.length == 1 &&
                    matches.single.grossAmountCents == item.cents,
              };
            }
            final overlay = img.Image.from(image);
            for (final line in lines) {
              final left = (line['left'] as num).round();
              final top = (line['top'] as num).round();
              expect(left, greaterThanOrEqualTo(0));
              expect(top, greaterThanOrEqualTo(0));
              expect(
                (line['left'] as num) + (line['width'] as num),
                lessThanOrEqualTo(image.width),
              );
              expect(
                (line['top'] as num) + (line['height'] as num),
                lessThanOrEqualTo(image.height),
              );
              img.drawRect(
                overlay,
                x1: left,
                y1: top,
                x2: (left + (line['width'] as num)).round(),
                y2: (top + (line['height'] as num)).round(),
                color: img.ColorRgb8(255, 0, 0),
                thickness: 3,
              );
            }
            final overlayPath =
                '${directory.path}/$engineId-${truth.id}-run-$run-overlay.png';
            await File(overlayPath).writeAsBytes(img.encodePng(overlay));
            // Record disagreement too: this is OCR evidence, not a fabricated
            // parser accuracy score or an assertion of perfect recognition.
            final record = {
              'probe': engineId,
              'sample': truth.id,
              'run': run,
              'lexicalPresence': lexicalPresence,
              'parserVersion': ReceiptParser.version,
              'parsedAgreement': parsedAgreement,
              'parsedSupplier': draft.supplierName,
              'parsedDate': draft.purchasedAt?.toIso8601String(),
              'parsedTotalCents': draft.detectedTotalCents,
              'parsedLines': [
                for (final line in draft.lines)
                  {
                    'description': line.description,
                    'quantity': line.quantity,
                    'grossAmountCents': line.grossAmountCents,
                    'warnings': line.warnings,
                  },
              ],
              'overlayPath': overlayPath,
              ...response,
            };
            final resultPath =
                '${directory.path}/$engineId-${truth.id}-run-$run-result.json';
            await File(resultPath).writeAsString(jsonEncode(record));
            // Android log records have a size limit; preserve complete evidence
            // in a file and print only the path for the host observer to pull.
            debugPrint(
              jsonEncode({
                'probe': engineId,
                'sample': truth.id,
                'run': run,
                'overlayPath': overlayPath,
                'resultPath': resultPath,
              }),
            );
            expect(text.trim(), isNotEmpty);
          }
          await channel.invokeMethod<void>('release');
        }
      } finally {
        await channel.invokeMethod<void>('release');
      }
    });
  }
}
