import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/utils/currency_formatter.dart';

void main() {
  group('Restock Whole-Pack Ceil Calculations', () {
    test('exact multiple of pack size buys exact packs needed', () {
      const targetPieces = 20;
      const piecesPerPack = 10;
      final packsNeeded = (targetPieces / piecesPerPack).ceil();
      final totalPurchased = packsNeeded * piecesPerPack;

      expect(packsNeeded, equals(2));
      expect(totalPurchased, equals(20));
      expect(totalPurchased >= targetPieces, isTrue);
    });

    test('fractional pack requirement rounds UP to whole pack to never short-change store', () {
      const targetPieces = 25;
      const piecesPerPack = 10;
      final packsNeeded = (targetPieces / piecesPerPack).ceil();
      final totalPurchased = packsNeeded * piecesPerPack;

      // 25 / 10 = 2.5 -> ceil is 3 packs (30 pieces).
      // Must NOT round to nearest (which would be 2 packs = 20 pieces, leaving the store 5 short).
      expect(packsNeeded, equals(3));
      expect(totalPurchased, equals(30));
      expect(totalPurchased >= targetPieces, isTrue);
    });

    test('small target pieces for large pack rounds up to 1 pack', () {
      const targetPieces = 1;
      const piecesPerPack = 24;
      final packsNeeded = (targetPieces / piecesPerPack).ceil();
      final totalPurchased = packsNeeded * piecesPerPack;

      expect(packsNeeded, equals(1));
      expect(totalPurchased, equals(24));
      expect(totalPurchased >= targetPieces, isTrue);
    });
  });

  group('Profit & Tubo Math', () {
    test('computes suggested SRP and gross profit (tubo) correctly with default markup', () {
      final profit = ProfitCalculation.compute(
        costPerPiece: 8.00,
        markupPercentage: 25.0,
      );

      // 8.00 * (1 + 0.25) = 10.00
      expect(profit.suggestedSellingPrice, closeTo(10.00, 0.001));
      // 10.00 - 8.00 = 2.00
      expect(profit.estimatedGrossProfit, closeTo(2.00, 0.001));
      // 2.00 / 10.00 = 20.0%
      expect(profit.grossMarginPercentage, closeTo(20.0, 0.001));
    });

    test('owner custom selling price overrides suggested price in tubo calculation', () {
      final profit = ProfitCalculation.compute(
        costPerPiece: 8.40,
        markupPercentage: 15.0,
        ownerSetSellingPrice: 10.50,
      );

      expect(profit.ownerSetSellingPrice, equals(10.50));
      // 10.50 - 8.40 = 2.10
      expect(profit.estimatedGrossProfit, closeTo(2.10, 0.001));
      // 2.10 / 10.50 = 20.0%
      expect(profit.grossMarginPercentage, closeTo(20.0, 0.001));
    });
  });

  group('Currency Formatter', () {
    test('formats standard Philippine Peso values', () {
      expect(CurrencyFormatter.format(1180.50), equals('₱1,180.50'));
      expect(CurrencyFormatter.format(8.0), equals('₱8.00'));
      expect(CurrencyFormatter.format(0.0), equals('₱0.00'));
    });

    test('formats positive and negative price differences with signs', () {
      expect(CurrencyFormatter.formatDifference(0.40), equals('+₱0.40'));
      expect(CurrencyFormatter.formatDifference(-0.30), equals('-₱0.30'));
      expect(CurrencyFormatter.formatDifference(0.0), equals('₱0.00'));
      expect(CurrencyFormatter.formatDifference(null), equals('₱0.00'));
    });

    test('formats percentages cleanly', () {
      expect(CurrencyFormatter.formatPercentage(15.0), equals('15%'));
      expect(CurrencyFormatter.formatPercentage(25.0), equals('25%'));
      expect(CurrencyFormatter.formatPercentage(null), equals('0%'));
    });
  });
}
