import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Interactive store avatar picker allowing store owners to personalize
/// their local tindahan ledger profile photo.
class StoreLogoPicker extends StatelessWidget {
  final String? photoPath;
  final ValueChanged<String> onPhotoSelected;

  const StoreLogoPicker({
    super.key,
    this.photoPath,
    required this.onPhotoSelected,
  });

  Future<void> _pickPhoto(BuildContext context) async {
    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (image != null) {
        onPhotoSelected(image.path);
      }
    } catch (_) {
      // Graceful fallback for simulator / non-gallery platforms
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (photoPath != null && photoPath!.isNotEmpty) {
      if (photoPath!.startsWith('assets/')) {
        imageProvider = AssetImage(photoPath!);
      } else {
        final file = File(photoPath!);
        if (file.existsSync()) {
          imageProvider = FileImage(file);
        }
      }
    }

    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: AppColors.primarySurface,
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? const Icon(
                    Icons.storefront_rounded,
                    size: 46,
                    color: AppColors.primary,
                  )
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: InkWell(
              onTap: () => _pickPhoto(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
