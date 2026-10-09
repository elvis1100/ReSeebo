import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo/core/constants/formatters.dart';
import 'package:reseebo/core/models/models.dart';

void main() {
  test('peso entry remains exact integer centavos', () {
    expect(parsePesos('1,234.56'), 123456);
    expect(parsePesos('₱0.01'), 1);
    expect(parsePesos('12.5'), 1250);
    expect(parsePesos('0'), 0);
    expect(parsePesos('1000000000.00'), maxAmountCents);
    for (final invalid in [
      '1,00',
      '₱1₱2',
      '',
      '-1',
      'NaN',
      'Infinity',
      '1e4',
      '12.345',
      '1.2.3',
      '1000000000.01',
    ]) {
      expect(parsePesos(invalid), isNull, reason: invalid);
    }
  });
  test('dates format on first use without locale downloads or setup', () {
    expect(purchaseDate(DateTime(2026, 10, 9)), '9 Oct 2026');
    expect(
      purchaseDate(DateTime(2026, 10, 9, 13, 5), withTime: true),
      '9 Oct 2026 · 1:05 PM',
    );
  });
  test('unset, zero and invalid markup remain distinct', () {
    expect(parseMarkup(''), isNull);
    expect(parseMarkup('0'), 0);
    expect(parseMarkup('20.5'), 20.5);
    for (final invalid in ['NaN', 'Infinity', '-1', '10001']) {
      expect(parseMarkup(invalid), isNull);
    }
  });
  test('whole pieces and packs reject decimals and nonpositive values', () {
    expect(parseQuantity('10'), 10);
    for (final invalid in ['', '0', '-1', '1.5', 'NaN', '1000001']) {
      expect(parseQuantity(invalid), isNull);
    }
  });
  test('unresolved quantities do not fabricate unit costs', () {
    final line = ParsedLineItem(
      description: 'COFFEE',
      quantity: 2,
      grossAmountCents: 16800,
    );
    expect(line.costPerPieceCents, isNull);
    line.unit = PurchaseUnit.pack;
    expect(line.costPerPieceCents, isNull);
    line.piecesPerPack = 10;
    expect(line.costPerPieceCents, 840);
    line.discountCents = 800;
    expect(line.costPerPieceCents, 800);
    line.discountCents = 16800;
    expect(line.costPerPieceCents, isNull);
  });
}
