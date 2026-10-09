import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Compact original-photo thumbnails open a full-size, zoomable viewer.
class ReceiptImagesPreview extends StatelessWidget {
  const ReceiptImagesPreview({super.key, required this.paths});
  final List<String> paths;

  Widget _image(String path, BoxFit fit) {
    Widget failed(BuildContext context, Object error, StackTrace? trace) =>
        const Center(
          child: Icon(Icons.receipt_long, color: AppColors.textMuted),
        );
    return kIsWeb
        ? Image.network(path, fit: fit, errorBuilder: failed)
        : Image.file(File(path), fit: fit, errorBuilder: failed);
  }

  void _open(BuildContext context, int index) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text('Original receipt · Photo ${index + 1}')),
          body: SizedBox.expand(
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 6,
              child: _image(paths[index], BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Original receipt · ${paths.length} ${paths.length == 1 ? 'photo' : 'photos'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: paths.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) => Material(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _open(context, index),
                child: SizedBox(
                  width: 82,
                  child: Column(
                    children: [
                      Expanded(
                        child: SizedBox.expand(
                          child: _image(paths[index], BoxFit.contain),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          'Photo ${index + 1}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
