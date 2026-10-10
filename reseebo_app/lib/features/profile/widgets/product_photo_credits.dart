import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProductPhotoCredits extends StatelessWidget {
  const ProductPhotoCredits({super.key});

  Future<void> _show(BuildContext context) async {
    try {
      final credits = await rootBundle.loadString(
        'assets/catalog/ATTRIBUTION.txt',
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Product photo credits'),
          content: SizedBox(
            width: 480,
            height: MediaQuery.sizeOf(context).height * .55,
            child: SingleChildScrollView(child: SelectableText(credits)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the bundled photo credits. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.photo_library_outlined, size: 18),
    label: const Text('Product photo credits'),
    onPressed: () => _show(context),
  );
}
