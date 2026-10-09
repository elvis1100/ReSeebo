import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Interactive viewer for the original physical receipt image.
///
/// Supports zoom/pan via [InteractiveViewer] and high-contrast toggle to
/// help sari-sari store owners read faint or faded thermal prints.
class ReceiptImageViewer extends StatefulWidget {
  final String imagePath;
  final double height;

  const ReceiptImageViewer({
    super.key,
    required this.imagePath,
    this.height = 220.0,
  });

  @override
  State<ReceiptImageViewer> createState() => _ReceiptImageViewerState();
}

class _ReceiptImageViewerState extends State<ReceiptImageViewer> {
  final TransformationController _transformController =
      TransformationController();
  bool _highContrast = false;

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
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 1.0,
              maxScale: 4.5,
              child: Center(
                child: ColorFiltered(
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
                'Pinch to zoom original receipt',
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
          'Sample Receipt Preview',
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
            child: Icon(
              icon,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
