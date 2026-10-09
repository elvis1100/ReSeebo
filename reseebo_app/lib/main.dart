import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/adapters/mock_reseebo_data_adapter.dart';
import 'core/adapters/reseebo_data_adapter.dart';
import 'core/adapters/sqlite_reseebo_data_adapter.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/reseebo_bottom_navigation.dart';
import 'features/comparison/screens/product_comparison_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/receipt_scan/screens/capture_screen.dart';
import 'features/receipt_scan/screens/review_match_screen.dart';
import 'features/receipts/screens/receipt_detail_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _StorageStartup());
}

/// Native storage errors stay visible instead of switching to disposable data.
class _StorageStartup extends StatefulWidget {
  const _StorageStartup();

  @override
  State<_StorageStartup> createState() => _StorageStartupState();
}

class _StorageStartupState extends State<_StorageStartup> {
  late Future<IReseeboDataAdapter> _opening;

  Future<IReseeboDataAdapter> _open() async =>
      kIsWeb ? MockReseeboDataAdapter() : await SqliteReseeboDataAdapter.open();

  @override
  void initState() {
    super.initState();
    _opening = _open();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<IReseeboDataAdapter>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ReseeboApp(dataAdapter: snapshot.data, demoMode: kIsWeb);
      }
      return MaterialApp(
        title: 'Reseebo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: snapshot.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.storage_rounded,
                            size: 48,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Could not open your store',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your saved records have not been reset. Try opening the local storage again.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => setState(() => _opening = _open()),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}

/// Root application widget for Reseebo (Offline Store Ledger).
class ReseeboApp extends StatefulWidget {
  final IReseeboDataAdapter? dataAdapter;
  final bool demoMode;

  const ReseeboApp({super.key, this.dataAdapter, this.demoMode = false});

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
      builder: widget.demoMode
          ? (context, child) => Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Material(
                    color: AppColors.softAmber,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: Text(
                          'Browser demo · sample data only',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: child!),
              ],
            )
          : null,
    );
  }
}

/// Bottom navigation container managing primary offline store workflows.
class ReseeboRootNavigation extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;

  const ReseeboRootNavigation({super.key, required this.dataAdapter});

  @override
  State<ReseeboRootNavigation> createState() => _ReseeboRootNavigationState();
}

class _ReseeboRootNavigationState extends State<ReseeboRootNavigation> {
  int _currentIndex = 0;
  int _dataRevision = 0;

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 0) _dataRevision++;
    });
  }

  void _openCaptureScreen() async {
    await Navigator.of(context).push(
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
                    setState(() {
                      _currentIndex = 0;
                      _dataRevision++;
                    });
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openProductComparison(Product product) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductComparisonScreen(
          dataAdapter: widget.dataAdapter,
          productId: product.id,
        ),
      ),
    );
    if (mounted) setState(() => _dataRevision++);
  }

  void _openReceiptDetail(Receipt receipt) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptDetailScreen(
          adapter: widget.dataAdapter,
          receiptId: receipt.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(
            dataAdapter: widget.dataAdapter,
            refreshRevision: _dataRevision,
            onSettingsPressed: () => _navigateToTab(1),
            onProductSelected: _openProductComparison,
            onReceiptSelected: _openReceiptDetail,
          ),
          ProfileScreen(
            dataAdapter: widget.dataAdapter,
            onProfileSaved: () => setState(() => _dataRevision++),
          ),
        ],
      ),
      bottomNavigationBar: ReseeboBottomNavigation(
        selectedIndex: _currentIndex,
        onTabSelected: _navigateToTab,
        onScan: _openCaptureScreen,
      ),
    );
  }
}
