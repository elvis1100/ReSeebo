import 'package:flutter/material.dart';

import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/widgets/store_header.dart';
import '../widgets/default_markup_slider.dart';
import '../widgets/product_photo_credits.dart';

class ProfileScreen extends StatefulWidget {
  final IReseeboDataAdapter dataAdapter;
  final VoidCallback? onBack;
  final VoidCallback? onProfileSaved;

  const ProfileScreen({
    super.key,
    required this.dataAdapter,
    this.onBack,
    this.onProfileSaved,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  StoreProfile? _profile;
  final _storeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  double? _markupPercentage;
  bool _isLoading = true;
  bool _isSaving = false;
  Object? _loadError;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _storeNameController.addListener(_changed);
    _ownerNameController.addListener(_changed);
    _loadProfile();
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _storeNameController.dispose();
    _ownerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile({bool refresh = false}) async {
    if (_isSaving || _isRefreshing) return;
    final base = _profile;
    _isRefreshing = true;
    setState(() {
      if (!refresh) _isLoading = true;
      _loadError = null;
    });
    try {
      final profile = await widget.dataAdapter.getStoreProfile();
      if (!mounted) return;
      // Refresh only pristine fields; edits made during the read also survive.
      final baseName = base?.storeName.trim().isEmpty == true
          ? 'Sari-sari Store'
          : base?.storeName;
      if (base == null || _storeNameController.text == baseName) {
        _storeNameController.text = profile.storeName.trim().isEmpty
            ? 'Sari-sari Store'
            : profile.storeName;
      }
      if (base == null || _ownerNameController.text == base.ownerName) {
        _ownerNameController.text = profile.ownerName;
      }
      setState(() {
        if (base == null || _markupPercentage == base.defaultMarkupPercent) {
          _markupPercentage = profile.defaultMarkupPercent;
        }
        _profile = profile;
      });
    } catch (error) {
      if (mounted) {
        if (base == null) {
          setState(() => _loadError = error);
        } else {
          showAppError(context, error);
        }
      }
    } finally {
      _isRefreshing = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_profile == null || _isSaving || _isRefreshing) return;
    final storeName = _storeNameController.text.trim();
    if (storeName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter your store name.')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      // Preserve an explicitly unset markup while retaining existing photo data.
      final updated = StoreProfile(
        name: storeName,
        ownerName: _ownerNameController.text.trim(),
        photoPath: _profile!.photoPath,
        defaultMarkupPercent: _markupPercentage,
      );
      await widget.dataAdapter.updateStoreProfile(updated);
      if (!mounted) return;
      final stored = await widget.dataAdapter.getStoreProfile();
      if (!mounted) return;
      setState(() {
        _profile = stored;
      });
      widget.onProfileSaved?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Store settings saved.')));
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      toolbarHeight: 64,
      title: const StoreHeader(),
      leading: widget.onBack == null
          ? null
          : IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: widget.onBack,
            ),
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => _loadProfile(refresh: true),
            child: _loadError != null
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ErrorState(
                      message: userMessage(_loadError!),
                      onRetry: _loadProfile,
                    ),
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppSpacing.page,
                    children: [
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Store information',
                              style: AppTypography.headingMedium,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _storeNameController,
                              enabled: !_isSaving,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Store name',
                                prefixIcon: Icon(Icons.storefront_rounded),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _ownerNameController,
                              enabled: !_isSaving,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Owner name (optional)',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DefaultMarkupSlider(
                        markupPercentage: _markupPercentage,
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                  setState(() => _markupPercentage = value),
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                        label: 'Save settings',
                        icon: Icons.check_rounded,
                        isLoading: _isSaving,
                        isFullWidth: true,
                        onPressed: _saveProfile,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Reseebo v1.0.0',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      const ProductPhotoCredits(),
                    ],
                  ),
          ),
  );
}
