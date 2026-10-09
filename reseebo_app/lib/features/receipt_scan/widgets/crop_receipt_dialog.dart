import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CropReceiptDialog extends StatefulWidget {
  const CropReceiptDialog({super.key, required this.path});
  final String path;
  @override
  State<CropReceiptDialog> createState() => _CropReceiptDialogState();
}

class _CropReceiptDialogState extends State<CropReceiptDialog> {
  RangeValues _horizontal = const RangeValues(0, 1);
  RangeValues _vertical = const RangeValues(0, 1);
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    try {
      final codec = await ui.instantiateImageCodec(
        await File(widget.path).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() => _aspectRatio = ratio);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Crop recognition area'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Keep the supplier, date, and every purchase line inside the green frame. The original photo stays intact.',
          ),
          const SizedBox(height: 16),
          if (_aspectRatio == null)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SizedBox(
              height: 240,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  final imageWidth = _aspectRatio! > width / height
                      ? width
                      : height * _aspectRatio!;
                  final imageHeight = imageWidth / _aspectRatio!;
                  return Center(
                    child: SizedBox(
                      width: imageWidth,
                      height: imageHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(widget.path), fit: BoxFit.fill),
                          Positioned(
                            left: _horizontal.start * imageWidth,
                            top: _vertical.start * imageHeight,
                            width:
                                (_horizontal.end - _horizontal.start) *
                                imageWidth,
                            height:
                                (_vertical.end - _vertical.start) * imageHeight,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 3,
                                ),
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          const Text('Left and right edges'),
          RangeSlider(
            values: _horizontal,
            divisions: 100,
            labels: RangeLabels(
              '${(_horizontal.start * 100).round()}%',
              '${(_horizontal.end * 100).round()}%',
            ),
            onChanged: (values) {
              if (values.end - values.start >= 0.1) {
                setState(() => _horizontal = values);
              }
            },
          ),
          const Text('Top and bottom edges'),
          RangeSlider(
            values: _vertical,
            divisions: 100,
            labels: RangeLabels(
              '${(_vertical.start * 100).round()}%',
              '${(_vertical.end * 100).round()}%',
            ),
            onChanged: (values) {
              if (values.end - values.start >= 0.1) {
                setState(() => _vertical = values);
              }
            },
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
        onPressed: _aspectRatio == null
            ? null
            : () => Navigator.pop(context, [
                _horizontal.start,
                _vertical.start,
                _horizontal.end,
                _vertical.end,
              ]),
        child: const Text('Apply crop'),
      ),
    ],
  );
}
