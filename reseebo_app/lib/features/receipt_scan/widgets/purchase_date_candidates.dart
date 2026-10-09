import 'package:flutter/material.dart';

import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';

class PurchaseDateCandidates extends StatefulWidget {
  const PurchaseDateCandidates({
    super.key,
    required this.candidates,
    required this.canRemember,
    required this.enabled,
    required this.onChoose,
  });
  final List<PurchaseDateCandidate> candidates;
  final bool canRemember;
  final bool enabled;
  final Future<void> Function(PurchaseDateCandidate, bool) onChoose;

  @override
  State<PurchaseDateCandidates> createState() => _PurchaseDateCandidatesState();
}

class _PurchaseDateCandidatesState extends State<PurchaseDateCandidates> {
  bool _remember = false;
  bool _busy = false;

  Future<void> _choose(PurchaseDateCandidate candidate) async {
    setState(() => _busy = true);
    try {
      await widget.onChoose(candidate, _remember && widget.canRemember);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the date choice. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Needs review: which date is printed on this receipt?'),
      for (final candidate in widget.candidates)
        TextButton(
          onPressed: widget.enabled && !_busy ? () => _choose(candidate) : null,
          child: Text(
            '${purchaseDate(candidate.date, withTime: candidate.hasTime)} '
            '(${candidate.order == NumericDateOrder.dayFirst ? 'day/month' : 'month/day'})',
          ),
        ),
      if (widget.canRemember)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remember date format for this supplier branch'),
          value: _remember,
          onChanged: widget.enabled && !_busy
              ? (value) => setState(() => _remember = value ?? false)
              : null,
        ),
    ],
  );
}
