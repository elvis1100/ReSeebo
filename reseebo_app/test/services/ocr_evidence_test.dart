import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';

void main() {
  test('draft snapshot isolates page evidence and token containers', () {
    final tokens = [
      const OcrTextToken(
        text: '144.00',
        left: 220,
        top: 90,
        width: 60,
        height: 18,
      ),
    ];
    final lines = [OcrTextLine(text: 'ITEM 144.00', tokens: tokens)];
    final pages = [
      ReceiptOcrPage(
        imagePath: 'original.jpg',
        recognitionImagePath: 'cropped.jpg',
        textLines: lines,
      ),
    ];
    final source = ReceiptDraft(
      imagePath: 'original.jpg',
      textLines: lines,
      ocrPages: pages,
    );
    final saved = source.snapshot();
    tokens.clear();
    lines.clear();
    pages.clear();
    expect(saved.ocrPages.single.imagePath, 'original.jpg');
    expect(saved.ocrPages.single.recognitionImagePath, 'cropped.jpg');
    expect(saved.ocrPages.single.textLines.single.tokens.single.text, '144.00');
    expect(saved.ocrPages.single.textLines.single.tokens.single.left, 220);
    expect(saved.textLines.single.tokens.single.width, 60);
  });
}
