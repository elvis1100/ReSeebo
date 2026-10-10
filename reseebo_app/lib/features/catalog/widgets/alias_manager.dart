import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';

class AliasManager extends StatefulWidget {
  const AliasManager({
    super.key,
    required this.adapter,
    required this.productId,
    this.enabled = true,
  });
  final IReseeboDataAdapter adapter;
  final String productId;
  final bool enabled;
  @override
  State<AliasManager> createState() => _AliasManagerState();
}

class _AliasManagerState extends State<AliasManager> {
  List<ProductAlias>? _aliases;
  String? _error;
  String? _deleting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final aliases = await widget.adapter.getAliases(widget.productId);
      if (mounted) {
        setState(() {
          _aliases = aliases;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    }
  }

  Future<void> _remove(ProductAlias alias) async {
    if (_deleting != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove saved match?'),
        content: Text(
          '“${alias.description}” will no longer suggest this product. Earlier purchases remain saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep match'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = alias.id);
    try {
      await widget.adapter.deleteAlias(alias.id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Saved receipt matches',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text('Confirmed receipt descriptions help match future scans.'),
      if (_error != null)
        Row(
          children: [
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        )
      else if (_aliases == null)
        const Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        )
      else if (_aliases!.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('No confirmed matches yet.'),
        )
      else
        ..._aliases!.map(
          (alias) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(alias.description),
            trailing: IconButton(
              tooltip: 'Remove saved match',
              onPressed: widget.enabled && _deleting == null
                  ? () => _remove(alias)
                  : null,
              icon: _deleting == alias.id
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
          ),
        ),
    ],
  );
}
