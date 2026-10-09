import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'receipt_image_geometry.dart';

/// Zoomable original or recognition image. Token coordinates must belong to
/// the exact file at [imagePath]; overlays are never remapped across edits.
///
/// Supports zoom/pan via [InteractiveViewer] and high-contrast toggle to
/// help sari-sari store owners read faint or faded thermal prints.
class ReceiptImageViewer extends StatefulWidget {
  final String imagePath;
  final double height;
  final List<OcrTextToken> tokens;
  final Set<int> selectedTokens;
  final ValueChanged<int>? onTokenSelected;
  final String imageLabel;
  final bool showContrastControl;
  final int? displayCacheWidth;
  final bool isEnhanced;
  final Widget? topOverlay;

  /// In the capture list one finger scrolls the page; two fingers zoom/pan.
  /// Full-screen and text-selection viewers keep normal image gestures.
  final bool scrollPageWithOneFinger;

  /// Reports raw touch ownership so a surrounding scroll view can suspend
  /// its drag recognizer before it competes with a staggered two-finger pinch.
  final ValueChanged<bool>? onInteractionActiveChanged;

  const ReceiptImageViewer({
    super.key,
    required this.imagePath,
    this.height = 220.0,
    this.tokens = const [],
    this.selectedTokens = const {},
    this.onTokenSelected,
    this.imageLabel = 'Original receipt',
    this.showContrastControl = true,
    this.displayCacheWidth,
    this.isEnhanced = false,
    this.topOverlay,
    this.scrollPageWithOneFinger = false,
    this.onInteractionActiveChanged,
  });

  @override
  State<ReceiptImageViewer> createState() => _ReceiptImageViewerState();
}

class _ReceiptImageViewerState extends State<ReceiptImageViewer> {
  final TransformationController _transformController =
      TransformationController();
  bool _highContrast = false;
  Size? _imageSize;
  int _imageGeneration = 0;
  final Set<int> _activePointers = {};
  double _lastGestureScale = 1;
  int _lastPointerCount = 0;
  bool _pinched = false;
  Drag? _pageDrag;

  void _captureGestureStart(ScaleStartDetails details) {
    _lastGestureScale = 1;
    _lastPointerCount = details.pointerCount;
    _pinched = details.pointerCount > 1;
    if (!_pinched) {
      _pageDrag = Scrollable.maybeOf(context)?.position.drag(
        DragStartDetails(globalPosition: details.focalPoint),
        () => _pageDrag = null,
      );
    }
  }

  void _captureGestureUpdate(ScaleUpdateDetails details, Size viewport) {
    if (details.pointerCount > 1) {
      _pinched = true;
      _pageDrag?.cancel();
      _pageDrag = null;
      if (_lastPointerCount != details.pointerCount) {
        _lastGestureScale = details.scale;
        _lastPointerCount = details.pointerCount;
        return;
      }
      final current = _transformController.value;
      final currentScale = current.getMaxScaleOnAxis();
      final nextScale = (currentScale * details.scale / _lastGestureScale)
          .clamp(1.0, 4.5);
      final factor = nextScale / currentScale;
      final focal = details.localFocalPoint;
      final previous = focal - details.focalPointDelta;
      final next =
          Matrix4.translationValues(focal.dx, focal.dy, 0) *
          Matrix4.diagonal3Values(factor, factor, 1) *
          Matrix4.translationValues(-previous.dx, -previous.dy, 0) *
          current;
      next.setEntry(
        0,
        3,
        next.entry(0, 3).clamp(viewport.width * (1 - nextScale), 0.0),
      );
      next.setEntry(
        1,
        3,
        next.entry(1, 3).clamp(viewport.height * (1 - nextScale), 0.0),
      );
      _transformController.value = next;
    } else if (!_pinched) {
      _pageDrag?.update(
        DragUpdateDetails(
          globalPosition: details.focalPoint,
          delta: Offset(0, details.focalPointDelta.dy),
          primaryDelta: details.focalPointDelta.dy,
        ),
      );
    }
    _lastGestureScale = details.scale;
    _lastPointerCount = details.pointerCount;
  }

  void _captureGestureEnd(ScaleEndDetails details) {
    _pageDrag?.end(
      DragEndDetails(
        velocity: Velocity(
          pixelsPerSecond: Offset(0, details.velocity.pixelsPerSecond.dy),
        ),
        primaryVelocity: details.velocity.pixelsPerSecond.dy,
      ),
    );
    _pageDrag = null;
    _lastPointerCount = 0;
    _lastGestureScale = 1;
    _pinched = false;
  }

  void _pointerDown(PointerDownEvent event) {
    if (_activePointers.add(event.pointer) && _activePointers.length == 1) {
      widget.onInteractionActiveChanged?.call(true);
    }
  }

  void _pointerEnd(PointerEvent event) {
    if (_activePointers.remove(event.pointer) && _activePointers.isEmpty) {
      widget.onInteractionActiveChanged?.call(false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDimensions();
  }

  @override
  void didUpdateWidget(covariant ReceiptImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _imageSize = null;
      _resetZoom();
      _loadDimensions();
    }
  }

  Future<void> _loadDimensions() async {
    final generation = ++_imageGeneration;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      final bytes = widget.imagePath.startsWith('assets/')
          ? (await rootBundle.load(widget.imagePath)).buffer.asUint8List()
          : await File(widget.imagePath).readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      // Header dimensions avoid decoding a second full receipt bitmap solely
      // to place OCR overlays; Image.file/asset owns the display decode.
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      if (mounted && generation == _imageGeneration) {
        setState(() => _imageSize = size);
      }
    } catch (_) {
      // Keep the readable-text fallback available when a picker file expired.
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _pageDrag?.cancel();
    if (_activePointers.isNotEmpty) {
      final release = widget.onInteractionActiveChanged;
      // A keyed image can be replaced during a rebuild. Release the parent's
      // scroll lock after that build, rather than calling setState inside it.
      scheduleMicrotask(() => release?.call(false));
    }
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Pinch-to-zoom interactive area
          Positioned.fill(
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerUp: _pointerEnd,
              onPointerCancel: _pointerEnd,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final image = InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 4.5,
                    child: SizedBox.fromSize(
                      size: constraints.biggest,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColorFiltered(
                            colorFilter: _highContrast
                                ? const ColorFilter.matrix(<double>[
                                    1.8, 0, 0, 0, -50, // R
                                    0, 1.8, 0, 0, -50, // G
                                    0, 0, 1.8, 0, -50, // B
                                    0, 0, 0, 1, 0, // A
                                  ])
                                : const ColorFilter.mode(
                                    Colors.transparent,
                                    BlendMode.dst,
                                  ),
                            child: _buildImageWidget(),
                          ),
                          if (_imageSize != null &&
                              widget.onTokenSelected != null)
                            ...widget.tokens.indexed
                                .where(
                                  (entry) =>
                                      entry.$2.width > 0 && entry.$2.height > 0,
                                )
                                .map((entry) {
                                  final token = entry.$2;
                                  final selected = widget.selectedTokens
                                      .contains(entry.$1);
                                  return Positioned.fromRect(
                                    rect: fitReceiptBounds(
                                      Rect.fromLTWH(
                                        token.left,
                                        token.top,
                                        token.width,
                                        token.height,
                                      ),
                                      imageSize: _imageSize!,
                                      viewport: constraints.biggest,
                                    ),
                                    child: Semantics(
                                      button: true,
                                      selected: selected,
                                      label:
                                          'Select receipt text ${token.text}',
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () =>
                                            widget.onTokenSelected!(entry.$1),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? AppColors.primaryLight
                                                      .withValues(alpha: 0.25)
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: selected
                                                  ? AppColors.primaryLight
                                                  : AppColors.info,
                                              width: selected ? 2 : 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                        ],
                      ),
                    ),
                  );
                  if (!widget.scrollPageWithOneFinger) return image;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _captureGestureStart,
                    onScaleUpdate: (details) =>
                        _captureGestureUpdate(details, constraints.biggest),
                    onScaleEnd: _captureGestureEnd,
                    child: IgnorePointer(child: image),
                  );
                },
              ),
            ),
          ),

          // Zoom & contrast controls overlay
          Positioned(
            bottom: AppSpacing.s,
            right: AppSpacing.s,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showContrastControl)
                  _buildActionButton(
                    icon: _highContrast
                        ? Icons.contrast_rounded
                        : Icons.tonality_rounded,
                    tooltip: 'Toggle high contrast for faint receipts',
                    isActive: _highContrast,
                    onPressed: () {
                      setState(() => _highContrast = !_highContrast);
                    },
                  ),
                if (widget.showContrastControl)
                  const SizedBox(width: AppSpacing.xs),
                _buildActionButton(
                  icon: Icons.fit_screen_rounded,
                  tooltip: 'Fit photo to screen',
                  isActive: false,
                  onPressed: _resetZoom,
                ),
              ],
            ),
          ),

          Positioned(
            top: AppSpacing.s,
            left: AppSpacing.s,
            right: AppSpacing.s,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child:
                        widget.topOverlay ??
                        IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .6),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusXs,
                              ),
                            ),
                            child: Text(
                              widget.isEnhanced
                                  ? 'Pinch to zoom'
                                  : '${widget.imageLabel} · pinch to zoom',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                if (widget.isEnhanced) ...[
                  const SizedBox(width: AppSpacing.s),
                  IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                      ),
                      child: const Text(
                        'Enhanced',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget() {
    if (widget.imagePath.startsWith('assets/')) {
      return Image.asset(
        widget.imagePath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    final file = File(widget.imagePath);
    if (file.existsSync()) {
      return Image.file(
        file,
        cacheWidth: widget.displayCacheWidth,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.receipt_long_rounded,
          color: AppColors.textMuted,
          size: 40,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Receipt image unavailable. Use recognized text or enter details.',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? AppColors.primaryLight
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppSpacing.radiusS),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
