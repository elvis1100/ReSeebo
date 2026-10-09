import 'package:flutter/material.dart';

class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.busy,
    required this.child,
    this.saved = false,
  });
  final bool dirty;
  final bool busy;
  final bool saved;
  final Widget child;
  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _discard = false;
  bool _asking = false;
  Future<void> _confirm() async {
    if (widget.busy || _asking) return;
    _asking = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    _asking = false;
    if (discard == true && mounted) {
      setState(() => _discard = true);
      // Wait until PopScope reflects the confirmation before a platform pop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.busy && (!widget.dirty || widget.saved || _discard),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _confirm();
    },
    child: widget.child,
  );
}
