import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../widgets/camera_viewfinder_guide.dart';

/// Screen enabling store owners to snap photos of receipts with on-device
/// framing assistance, gallery upload fallback, and offline OCR status.
class CaptureScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final ValueChanged<ReceiptDraft>? onDraftReady;
  final VoidCallback? onBack;

  const CaptureScreen({
    super.key,
    required this.dataAdapter,
    this.onDraftReady,
    this.onBack,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  String? _statusMessage;

  Future<void> _captureFromCamera() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (photo != null) {
        await _processImagePath(photo.path);
      }
    } catch (_) {
      // In desktop/simulator environments without camera, fallback gracefully
      _useDemoReceipt();
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (image != null) {
        await _processImagePath(image.path);
      }
    } catch (_) {
      _useDemoReceipt();
    }
  }

  Future<void> _useDemoReceipt() async {
    await _processImagePath('assets/samples/demo_puregold_receipt.jpg');
  }

  Future<void> _processImagePath(String localPath) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Reading receipt lines...';
    });

    try {
      final draft = await widget.dataAdapter.processReceiptImage(localPath);
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        widget.onDraftReady?.call(draft);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.priceIncrease,
            content: Text('Failed to process receipt: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Capture Receipt',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Try Demo Receipt',
            icon: const Icon(Icons.receipt_long_rounded, color: AppColors.accentLight),
            onPressed: _isProcessing ? null : _useDemoReceipt,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Viewfinder background preview area
          Container(
            color: const Color(0xFF1E293B),
            child: const Center(
              child: Icon(
                Icons.camera_alt_outlined,
                size: 80,
                color: Color(0xFF475569),
              ),
            ),
          ),

          // Framing cut-out guidelines
          const CameraViewfinderGuide(),

          // Bottom control toolbar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Pick from phone gallery
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Choose from Gallery',
                      icon: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white,
                      ),
                      onPressed: _isProcessing ? null : _pickFromGallery,
                    ),

                    // Main circular shutter capture button
                    GestureDetector(
                      onTap: _isProcessing ? null : _captureFromCamera,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: Colors.transparent,
                        ),
                        child: Center(
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                            child: const Icon(
                              Icons.camera_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Use sample receipt shortcut
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Load Sample',
                      icon: const Icon(
                        Icons.description_outlined,
                        color: Colors.white,
                      ),
                      onPressed: _isProcessing ? null : _useDemoReceipt,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Processing loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3.5,
                      ),
                      const SizedBox(height: AppSpacing.m),
                      Text(
                        'Processing Receipt...',
                        style: AppTypography.headingSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _statusMessage ?? 'Extracting products & prices...',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
