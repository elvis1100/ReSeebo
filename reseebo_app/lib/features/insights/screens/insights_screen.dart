import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../models/store_insights.dart';
import '../services/store_insights_pdf.dart';
import '../services/store_insights_service.dart';

/// Opens a locally generated PDF. Native mobile viewing uses bundled resources.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.adapter});
  final IReseeboDataAdapter adapter;
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightPeriod _period = InsightPeriod.last30Days;
  Uint8List? _bytes;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final period = _period;
    setState(() {
      _bytes = null;
      _error = null;
    });
    try {
      final data = await StoreInsightsService(widget.adapter).load();
      final profile = await widget.adapter.getStoreProfile();
      final now = DateTime.now();
      final bytes = await StoreInsightsPdf.build(
        insights: StoreInsightsService.summarize(data, period, now),
        storeName: profile.name,
        period: period,
        generatedAt: now,
      );
      if (mounted && request == _request) setState(() => _bytes = bytes);
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store insights PDF'),
        actions: [
          IconButton(
            tooltip: 'Refresh report',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<InsightPeriod>(
              initialValue: _period,
              decoration: const InputDecoration(
                labelText: 'Price-change period',
              ),
              items: [
                for (final period in InsightPeriod.values)
                  DropdownMenuItem(
                    value: period,
                    child: Text(StoreInsightsPdf.periodLabel(period)),
                  ),
              ],
              onChanged: (period) {
                if (period == null) return;
                _period = period;
                _load();
              },
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(userMessage(_error!)),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : bytes == null
                ? const Center(child: CircularProgressIndicator())
                : PdfPreview(
                    key: ValueKey(bytes),
                    build: (_) async => bytes,
                    pdfFileName: 'reseebo-store-insights.pdf',
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: true,
                    allowSharing: true,
                    onError: (_, error) =>
                        Center(child: Text('Unable to preview PDF: $error')),
                  ),
          ),
        ],
      ),
    );
  }
}
