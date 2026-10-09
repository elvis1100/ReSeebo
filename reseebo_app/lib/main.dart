import 'package:flutter/material.dart';
import 'core/adapters/i_reseebo_data_adapter.dart';
import 'core/adapters/sqlite_reseebo_data_adapter.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/shared_widgets.dart';
import 'features/dashboard/screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

class ReseeboApp extends StatelessWidget {
  const ReseeboApp({super.key, required this.adapter});
  final IReseeboDataAdapter adapter;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Reseebo',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: DashboardScreen(adapter: adapter),
  );
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  IReseeboDataAdapter? _adapter;
  Object? _error;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    setState(() => _error = null);
    try {
      final adapter = await SqliteReseeboDataAdapter.open();
      if (!mounted) {
        await adapter.close();
        return;
      }
      setState(() => _adapter = adapter);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    _adapter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_adapter != null) return ReseeboApp(adapter: _adapter!);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: _error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 54,
                        color: AppColors.primary,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Reseebo',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('Your tindahan, on your phone.'),
                      SizedBox(height: 24),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  )
                : ErrorState(message: userMessage(_error!), onRetry: _open),
          ),
        ),
      ),
    );
  }
}
