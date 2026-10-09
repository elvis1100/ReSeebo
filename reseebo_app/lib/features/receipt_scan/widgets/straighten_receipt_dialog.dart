import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class StraightenReceiptDialog extends StatefulWidget {
  const StraightenReceiptDialog({super.key, required this.path});
  final String path;
  @override
  State<StraightenReceiptDialog> createState() =>
      _StraightenReceiptDialogState();
}

class _StraightenReceiptDialogState extends State<StraightenReceiptDialog> {
  double _angle = 0;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Straighten receipt lines'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Adjust until printed lines are horizontal. This corrects tilt; photograph the receipt from above to avoid perspective distortion.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(
                    angle: _angle * math.pi / 180,
                    child: Image.file(
                      File(widget.path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(Icons.receipt_long),
                    ),
                  ),
                  IgnorePointer(
                    child: Divider(
                      color: Theme.of(context).colorScheme.primary,
                      thickness: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text('${_angle.toStringAsFixed(1)}°'),
          Slider(
            value: _angle,
            min: -15,
            max: 15,
            divisions: 60,
            label: '${_angle.toStringAsFixed(1)}°',
            onChanged: (angle) => setState(() => _angle = angle),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _angle),
        child: const Text('Apply correction'),
      ),
    ],
  );
}
