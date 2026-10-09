/// Store profile configuration for Reseebo offline store.
class StoreProfile {
  final String id;
  final String storeName;
  final String? ownerName;
  final String? photoPath;
  final double defaultMarkupPercentage;

  const StoreProfile({
    required this.id,
    required this.storeName,
    this.ownerName,
    this.photoPath,
    this.defaultMarkupPercentage = 20.0,
  });

  StoreProfile copyWith({
    String? id,
    String? storeName,
    String? ownerName,
    String? photoPath,
    double? defaultMarkupPercentage,
  }) {
    return StoreProfile(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      ownerName: ownerName ?? this.ownerName,
      photoPath: photoPath ?? this.photoPath,
      defaultMarkupPercentage:
          defaultMarkupPercentage ?? this.defaultMarkupPercentage,
    );
  }
}
