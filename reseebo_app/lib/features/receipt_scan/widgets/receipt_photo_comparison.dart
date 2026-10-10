import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Read-only comparison of the preserved original and staged enhanced photo.
/// Both layers share one transform; dragging the divider never changes edits
/// or the image selected for recognition. Geometry edits are shown as-is.
class ReceiptPhotoComparison extends StatefulWidget {
  const ReceiptPhotoComparison({
    super.key,
    required this.originalPath,
    required this.enhancedPath,
    required this.height,
    this.topOverlay,
    this.onInteractionActiveChanged,
  });

  final String originalPath;
  final String enhancedPath;
  final double height;
  final Widget? topOverlay;
  final ValueChanged<bool>? onInteractionActiveChanged;

  @override
  State<ReceiptPhotoComparison> createState() => _ReceiptPhotoComparisonState();
}

class _ReceiptPhotoComparisonState extends State<ReceiptPhotoComparison> {
  final _transform = TransformationController();
  final _pointers = <int>{};
  double _split = .5;

  void _down(PointerDownEvent event) {
    if (_pointers.add(event.pointer) && _pointers.length == 1) {
      widget.onInteractionActiveChanged?.call(true);
    }
  }

  void _end(PointerEvent event) {
    if (_pointers.remove(event.pointer) && _pointers.isEmpty) {
      widget.onInteractionActiveChanged?.call(false);
    }
  }

  void _setSplit(double value) =>
      setState(() => _split = value.clamp(.08, .92));

  @override
  void dispose() {
    if (_pointers.isNotEmpty) {
      final release = widget.onInteractionActiveChanged;
      scheduleMicrotask(() => release?.call(false));
    }
    _transform.dispose();
    super.dispose();
  }

  Widget _image(String path) => ColoredBox(
    // A crop/rotation may change aspect ratio. Original letterbox margins must
    // stay opaque rather than revealing the enhanced layer underneath them.
    color: AppColors.textPrimary,
    child: Image.file(
      File(path),
      fit: BoxFit.contain,
      cacheWidth: 1600,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white70),
      ),
    ),
  );

  Widget _label(String label) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(AppSpacing.radiusS),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: Material(
      color: AppColors.textPrimary,
      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerDown: _down,
              onPointerUp: _end,
              onPointerCancel: _end,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 4.5,
                child: SizedBox.fromSize(
                  size: constraints.biggest,
                  child: _image(widget.enhancedPath),
                ),
              ),
            ),
            // Clipping happens in viewport coordinates, outside the shared
            // transform, so the comparison divider stays fixed while zooming.
            IgnorePointer(
              child: ClipRect(
                clipper: _OriginalClipper(_split),
                child: InteractiveViewer(
                  transformationController: _transform,
                  panEnabled: false,
                  scaleEnabled: false,
                  minScale: 1,
                  maxScale: 4.5,
                  child: SizedBox.fromSize(
                    size: constraints.biggest,
                    child: _image(widget.originalPath),
                  ),
                ),
              ),
            ),
            Positioned(
              left: constraints.maxWidth * _split - 24,
              top: 0,
              bottom: 0,
              width: 48,
              child: Semantics(
                label: 'Compare original and enhanced photo',
                value: '${(_split * 100).round()}% original',
                increasedValue:
                    '${((_split + .1).clamp(.08, .92) * 100).round()}% original',
                decreasedValue:
                    '${((_split - .1).clamp(.08, .92) * 100).round()}% original',
                onIncrease: () => _setSplit(_split + .1),
                onDecrease: () => _setSplit(_split - .1),
                child: Listener(
                  onPointerDown: _down,
                  onPointerUp: _end,
                  onPointerCancel: _end,
                  child: GestureDetector(
                    key: const ValueKey('receipt-comparison-divider'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) => _setSplit(
                      _split + details.delta.dx / constraints.maxWidth,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(width: 2, color: Colors.white),
                        const CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.compare_arrows_rounded,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: widget.topOverlay ?? const SizedBox.shrink(),
            ),
            Positioned(bottom: 8, left: 8, child: _label('Original')),
            Positioned(bottom: 8, right: 8, child: _label('Enhanced')),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                tooltip: 'Fit photo to screen',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _transform.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen_rounded),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OriginalClipper extends CustomClipper<Rect> {
  const _OriginalClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_OriginalClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
