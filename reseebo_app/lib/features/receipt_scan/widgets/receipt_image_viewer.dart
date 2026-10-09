import 'dart:io';
import 'dart:ui' as ui;
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

  const ReceiptImageViewer({
    super.key,
    required this.imagePath,
    this.height = 220.0,
    this.tokens = const [],
    this.selectedTokens = const {},
    this.onTokenSelected,
    this.imageLabel = 'Original receipt',
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
            child: LayoutBuilder(
              builder: (context, constraints) => InteractiveViewer(
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
                      if (_imageSize != null && widget.onTokenSelected != null)
                        ...widget.tokens.indexed
                            .where(
                              (entry) =>
                                  entry.$2.width > 0 && entry.$2.height > 0,
                            )
                            .map((entry) {
                              final token = entry.$2;
                              final selected = widget.selectedTokens.contains(
                                entry.$1,
                              );
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
                                  label: 'Select receipt text ${token.text}',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        widget.onTokenSelected!(entry.$1),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.primaryLight.withValues(
                                                alpha: 0.25,
                                              )
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
                const SizedBox(width: AppSpacing.xs),
                _buildActionButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Reset zoom',
                  isActive: false,
                  onPressed: _resetZoom,
                ),
              ],
            ),
          ),

          // Image info badge
          Positioned(
            top: AppSpacing.s,
            left: AppSpacing.s,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: 2.0,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              ),
              child: Text(
                '${widget.imageLabel} · pinch to zoom',
                style: AppTypography.caption.copyWith(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
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
