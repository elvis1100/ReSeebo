import 'package:flutter/material.dart';
import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/models/store_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../widgets/default_markup_slider.dart';
import '../widgets/store_logo_picker.dart';

/// Screen allowing the tindahan store owner to configure their store profile,
/// customize default markup percentage, and inspect on-device offline storage.
class ProfileScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final VoidCallback? onBack;

  const ProfileScreen({
    super.key,
    required this.dataAdapter,
    this.onBack,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  StoreProfile? _profile;
  late TextEditingController _storeNameController;
  late TextEditingController _ownerNameController;
  String? _photoPath;
  double _markupPercentage = 20.0;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _storeNameController = TextEditingController();
    _ownerNameController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _ownerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final profile = await widget.dataAdapter.getStoreProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
        _storeNameController.text = profile.storeName;
        _ownerNameController.text = profile.ownerName ?? '';
        _photoPath = profile.photoPath;
        _markupPercentage = profile.defaultMarkupPercentage;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_profile == null) return;

    final storeName = _storeNameController.text.trim();
    if (storeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.priceIncrease,
          content: Text('Store name cannot be empty.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updated = _profile!.copyWith(
        storeName: storeName,
        ownerName: _ownerNameController.text.trim().isEmpty
            ? null
            : _ownerNameController.text.trim(),
        photoPath: _photoPath,
        defaultMarkupPercentage: _markupPercentage,
      );

      await widget.dataAdapter.updateStoreProfile(updated);

      if (mounted) {
        setState(() {
          _profile = updated;
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.primary,
            content: Text('Store profile and settings updated successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.priceIncrease,
            content: Text('Failed to update store profile: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Store Profile & Settings'),
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              )
            : null,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Store logo avatar
                  StoreLogoPicker(
                    photoPath: _photoPath,
                    onPhotoSelected: (path) {
                      setState(() => _photoPath = path);
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Store identity card
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tindahan Information',
                          style: AppTypography.headingSmall.copyWith(
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.m),
                        TextField(
                          controller: _storeNameController,
                          style: AppTypography.bodyRegular,
                          decoration: const InputDecoration(
                            labelText: 'Store Name',
                            prefixIcon: Icon(Icons.storefront_rounded),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.m),
                        TextField(
                          controller: _ownerNameController,
                          style: AppTypography.bodyRegular,
                          decoration: const InputDecoration(
                            labelText: 'Owner Name (Optional)',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),

                  // Markup configuration slider
                  DefaultMarkupSlider(
                    markupPercentage: _markupPercentage,
                    onChanged: (val) {
                      setState(() => _markupPercentage = val);
                    },
                  ),
                  const SizedBox(height: AppSpacing.m),

                  // Offline-First Device Status Card
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.offline_pin_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.s),
                            Text(
                              'Offline-First System Status',
                              style: AppTypography.headingSmall.copyWith(
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s),
                        _buildStatusRow(
                          label: 'Storage Database',
                          value: 'Local SQLite (On-Device)',
                          isOk: true,
                        ),
                        const Divider(height: 12),
                        _buildStatusRow(
                          label: 'OCR Recognition',
                          value: '100% Bundled Local Engine',
                          isOk: true,
                        ),
                        const Divider(height: 12),
                        _buildStatusRow(
                          label: 'Cloud Dependency',
                          value: 'None (Zero data leaves device)',
                          isOk: true,
                        ),
                        const Divider(height: 12),
                        _buildStatusRow(
                          label: 'App Edition',
                          value: 'Reseebo v1.0.0 (Tindahan Edition)',
                          isOk: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Save changes button
                  AppButton(
                    label: _isSaving ? 'Saving Changes...' : 'Save Settings',
                    icon: Icons.check_circle_outline_rounded,
                    isLoading: _isSaving,
                    isFullWidth: true,
                    onPressed: _saveProfile,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusRow({
    required String label,
    required String value,
    required bool isOk,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOk)
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            const SizedBox(width: 4),
            Text(
              value,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: isOk ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
