import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/adapters/mock_reseebo_data_adapter.dart';
import 'core/adapters/reseebo_data_adapter.dart';
import 'core/adapters/sqlite_reseebo_data_adapter.dart';
import 'core/theme/app_theme.dart';
import 'features/comparison/screens/product_comparison_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/planner/screens/restock_planner_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/receipt_scan/screens/capture_screen.dart';
import 'features/receipt_scan/screens/review_match_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  IReseeboDataAdapter adapter;
  if (kIsWeb) {
    adapter = MockReseeboDataAdapter();
  } else {
    try {
      adapter = await SqliteReseeboDataAdapter.open();
    } catch (_) {
      adapter = MockReseeboDataAdapter();
    }
  }
  runApp(ReseeboApp(dataAdapter: adapter));
}

/// Root application widget for Reseebo (Offline-First Tindahan Ledger).
class ReseeboApp extends StatefulWidget {
  final IReseeboDataAdapter? dataAdapter;

  const ReseeboApp({super.key, this.dataAdapter});

  @override
  State<ReseeboApp> createState() => _ReseeboAppState();
}

class _ReseeboAppState extends State<ReseeboApp> {
  late final IReseeboDataAdapter _adapter;

  @override
  void initState() {
    super.initState();
    _adapter = widget.dataAdapter ?? MockReseeboDataAdapter();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reseebo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: ReseeboRootNavigation(dataAdapter: _adapter),
    );
  }
}

/// Bottom navigation container managing primary offline tindahan workflows.
class ReseeboRootNavigation extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;

  const ReseeboRootNavigation({
    super.key,
    required this.dataAdapter,
  });

  @override
  State<ReseeboRootNavigation> createState() => _ReseeboRootNavigationState();
}

class _ReseeboRootNavigationState extends State<ReseeboRootNavigation> {
  void _openCaptureScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CaptureScreen(
          dataAdapter: widget.dataAdapter,
          onDraftReady: (draft) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ReviewMatchScreen(
                  dataAdapter: widget.dataAdapter,
                  initialDraft: draft,
                  onSaved: (result) {
                    Navigator.of(context).pop();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          dataAdapter: widget.dataAdapter,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openProductComparison(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductComparisonScreen(
          dataAdapter: widget.dataAdapter,
          productId: product.id,
          onRestockPlanRequested: (prodId) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => RestockPlannerScreen(
                  dataAdapter: widget.dataAdapter,
                  productId: prodId,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openReceiptDetail(Receipt receipt) async {
    // Convert existing receipt into draft review inspect mode
    final draft = await widget.dataAdapter.processReceiptImage(receipt.localImagePath);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReviewMatchScreen(
          dataAdapter: widget.dataAdapter,
          initialDraft: draft,
          onSaved: (result) {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DashboardScreen(
      dataAdapter: widget.dataAdapter,
      onScanPressed: _openCaptureScreen,
      onSettingsPressed: _openSettings,
      onProductSelected: _openProductComparison,
      onReceiptSelected: _openReceiptDetail,
    );
  }
}
