import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../models/store_insights.dart';
import 'suggested_suppliers.dart';

/// Builds a snapshot exclusively from saved local purchases and bundled fonts.
/// Prices are per piece; comparisons retain dates rather than implying live offers.
class StoreInsightsPdf {
  static String periodLabel(InsightPeriod period) => switch (period) {
    InsightPeriod.last30Days => 'Last 30 days',
    InsightPeriod.thisMonth => 'This month',
    InsightPeriod.allHistory => 'All history',
  };

  static Future<Uint8List> build({
    required StoreInsights insights,
    required String storeName,
    required InsightPeriod period,
    required DateTime generatedAt,
    AssetBundle? bundle,
  }) async {
    final font = pw.Font.ttf(
      await (bundle ?? rootBundle).load('assets/fonts/Inter.ttf'),
    );
    final document = pw.Document(
      title: '$storeName · Store insights',
      author: 'Reseebo',
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    const green = PdfColor.fromInt(0xff246c46);
    const pale = PdfColor.fromInt(0xffeff6f1);
    const grey = PdfColor.fromInt(0xff65716a);
    final widgets = <pw.Widget>[
      pw.Text(
        'STORE INSIGHTS',
        style: pw.TextStyle(fontSize: 10, color: green),
      ),
      pw.SizedBox(height: 6),
      pw.Text(storeName, style: const pw.TextStyle(fontSize: 24)),
      pw.SizedBox(height: 5),
      pw.Text(
        'Generated ${purchaseDate(generatedAt, withTime: true)}',
        style: const pw.TextStyle(fontSize: 9, color: grey),
      ),
      pw.SizedBox(height: 20),
      pw.Text(
        'Price changes',
        style: const pw.TextStyle(fontSize: 16, color: green),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
        '${periodLabel(period)} · Same exact product and supplier · Cost per piece',
        style: const pw.TextStyle(fontSize: 9),
      ),
      pw.SizedBox(height: 8),
      _table(
        ['Product', 'Supplier / date', 'Previous', 'Latest', 'Change / piece'],
        [
          for (final change in insights.changes)
            [
              _identity(change.product),
              '${change.history.purchase.supplier.displayName}\n${purchaseDate(change.history.date, withTime: change.history.purchase.hasPurchaseTime)}'
                  '${change.history.orderingNote == null ? '' : '\n${change.history.orderingNote}'}',
              pesos(change.history.previousCostPerPieceCents!),
              pesos(change.history.purchase.costPerPieceCents),
              '${change.history.changeCents! > 0 ? '+' : '-'}${pesos(change.history.changeCents!.abs())}\n'
                  '${percent(change.history.changePercent!.abs())} ${change.history.changeCents! > 0 ? 'increase' : 'decrease'}',
            ],
        ],
        widths: const [2.4, 2.3, 1.2, 1.2, 1.8],
        numericColumns: const {2, 3, 4},
        changeColumn: 4,
      ),
      if (insights.changes.isEmpty)
        _note(
          'No price changes in this period. Save repeated purchases to build price history.',
        ),
      pw.SizedBox(height: 20),
      pw.Text(
        'Supplier comparisons',
        style: const pw.TextStyle(fontSize: 16, color: green),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
        'Latest recorded prices · All history · Cost per piece',
        style: const pw.TextStyle(fontSize: 9),
      ),
      _note(
        'Dates may differ. These are saved purchase prices, not guaranteed current offers. Lowest means lowest among recorded suppliers for this exact product.',
      ),
    ];
    for (final comparison in insights.comparisons) {
      final rows = [...comparison.latestPrices]
        ..sort(
          (a, b) => a.purchase.costPerPieceCents.compareTo(
            b.purchase.costPerPieceCents,
          ),
        );
      widgets.addAll([
        pw.SizedBox(height: 12),
        pw.Text(
          _identity(comparison.product),
          style: const pw.TextStyle(fontSize: 11, color: green),
        ),
        pw.SizedBox(height: 6),
        _table(
          ['Supplier', 'Date', 'Cost / piece', 'Compared with lowest'],
          [
            for (final row in rows)
              [
                row.purchase.supplier.displayName,
                purchaseDate(
                  row.latestPurchaseDate,
                  withTime: row.purchase.hasPurchaseTime,
                ),
                pesos(row.purchase.costPerPieceCents),
                rows.length == 1
                    ? 'Only recorded supplier'
                    : row.isLowest
                    ? 'Lowest recorded'
                    : '+${pesos(row.differenceCents)} / piece',
              ],
          ],
          widths: const [2.4, 1.8, 1.4, 2.3],
          numericColumns: const {2},
          highlightRows: {
            for (var i = 0; i < rows.length; i++)
              if (rows.length > 1 && rows[i].isLowest) i,
          },
        ),
      ]);
    }
    if (insights.comparisons.isEmpty) {
      widgets.addAll([
        _table(
          ['Supplier', 'Date', 'Cost / piece', 'Compared with lowest'],
          [],
          widths: const [2.4, 1.8, 1.4, 2.3],
          numericColumns: const {2},
        ),
        _note(
          'No saved purchase prices yet. Save a receipt to build supplier comparisons.',
        ),
      ]);
    }
    widgets.addAll([
      pw.SizedBox(height: 24),
      pw.Text(
        'Suggested suppliers',
        style: const pw.TextStyle(fontSize: 16, color: green),
      ),
      _note(
        'Products grouped by the supplier with the lowest latest recorded cost per piece. '
        'All history. Tied products appear under both suppliers. Prices may be out of date; '
        'availability, whole-pack quantities, and travel costs can change your buying decision.',
      ),
    ]);
    final suggestions = suggestedSuppliers(insights.comparisons);
    for (final group in suggestions) {
      widgets.addAll([
        pw.SizedBox(height: 12),
        pw.Text(
          group.supplier.displayName,
          style: const pw.TextStyle(fontSize: 12, color: green),
        ),
        pw.SizedBox(height: 6),
        _table(
          ['Product', 'Latest purchase date', 'Cost / piece', 'Status'],
          [
            for (final item in group.products)
              [
                _identity(item.product),
                purchaseDate(
                  item.price.latestPurchaseDate,
                  withTime: item.price.purchase.hasPurchaseTime,
                ),
                pesos(item.price.purchase.costPerPieceCents),
                item.tied ? 'Tied lowest' : 'Lowest recorded',
              ],
          ],
          widths: const [3, 2, 1.4, 1.8],
          numericColumns: const {2},
        ),
      ]);
    }
    if (suggestions.isEmpty) {
      widgets.add(
        _note(
          'No supplier suggestions yet. Record the same exact product from at least two suppliers.',
        ),
      );
    }
    final uncompared = insights.comparisons
        .where(
          (comparison) =>
              comparison.latestPrices
                  .map((row) => row.purchase.supplier.id)
                  .toSet()
                  .length ==
              1,
        )
        .toList();
    if (uncompared.isNotEmpty) {
      widgets.addAll([
        pw.SizedBox(height: 16),
        pw.Text(
          'No comparison yet',
          style: const pw.TextStyle(fontSize: 12, color: green),
        ),
        _note(
          'These products have only one recorded supplier and are not recommendations.',
        ),
        _table(
          ['Product', 'Recorded supplier', 'Purchase date', 'Cost / piece'],
          [
            for (final comparison in uncompared)
              [
                _identity(comparison.product),
                comparison.latestPrices.single.purchase.supplier.displayName,
                purchaseDate(
                  comparison.latestPrices.single.latestPurchaseDate,
                  withTime:
                      comparison.latestPrices.single.purchase.hasPurchaseTime,
                ),
                pesos(
                  comparison.latestPrices.single.purchase.costPerPieceCents,
                ),
              ],
          ],
          widths: const [3, 2.4, 2, 1.4],
          numericColumns: const {3},
        ),
      ]);
    }
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 1000,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(
                  '$storeName · Store insights',
                  style: const pw.TextStyle(fontSize: 9, color: grey),
                ),
              ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: pale)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Reseebo · Local purchase records',
                style: const pw.TextStyle(fontSize: 8, color: grey),
              ),
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: grey),
              ),
            ],
          ),
        ),
        build: (_) => widgets,
      ),
    );
    return document.save();
  }

  static String _identity(Product product) =>
      product.displayName == product.displayTitle
      ? product.displayTitle
      : '${product.displayName}\n${product.displayTitle}';

  static pw.Widget _note(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
  );

  static pw.Table _table(
    List<String> headers,
    List<List<String>> rows, {
    required List<double> widths,
    Set<int> highlightRows = const {},
    Set<int> numericColumns = const {},
    int? changeColumn,
  }) => pw.Table(
    border: pw.TableBorder.all(
      color: const PdfColor.fromInt(0xffdbe4de),
      width: 0.5,
    ),
    columnWidths: {
      for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i]),
    },
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xffe5f0e9)),
        children: [
          for (var i = 0; i < headers.length; i++)
            _cell(
              headers[i],
              header: true,
              numeric: numericColumns.contains(i),
            ),
        ],
      ),
      for (var i = 0; i < rows.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: highlightRows.contains(i)
                ? const PdfColor.fromInt(0xffeff6f1)
                : i.isEven
                ? PdfColors.white
                : const PdfColor.fromInt(0xfffafbfa),
          ),
          children: [
            for (var j = 0; j < rows[i].length; j++)
              _cell(
                rows[i][j],
                numeric: numericColumns.contains(j),
                color: j == changeColumn
                    ? rows[i][j].startsWith('+')
                          ? const PdfColor.fromInt(0xffa23535)
                          : const PdfColor.fromInt(0xff246c46)
                    : null,
              ),
          ],
        ),
    ],
  );

  static pw.Widget _cell(
    String value, {
    bool header = false,
    bool numeric = false,
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.all(7),
    child: pw.Text(
      value,
      textAlign: numeric ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: header ? 9 : 8.5,
        color: header
            ? const PdfColor.fromInt(0xff246c46)
            : color ?? PdfColors.black,
      ),
    ),
  );
}
