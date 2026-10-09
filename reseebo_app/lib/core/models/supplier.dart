/// Reusable supplier entity with branch/location identification.
class Supplier {
  final String id;
  final String name;
  final String? branchLocation;
  final String? notes;

  const Supplier({
    required this.id,
    required this.name,
    this.branchLocation,
    this.notes,
  });

  /// Formatted name with branch e.g. "Puregold (Branch A - San Juan)"
  String get displayName {
    if (branchLocation != null && branchLocation!.isNotEmpty) {
      return '$name ($branchLocation)';
    }
    return name;
  }
}
