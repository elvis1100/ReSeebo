import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Picker files are temporary until the profile/product adapter copies them.
class PhotoEditor extends StatefulWidget {
  const PhotoEditor({
    super.key,
    required this.path,
    required this.onChanged,
    this.enabled = true,
    this.label = 'Photo',
  });
  final String? path;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String label;

  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  bool _picking = false;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    if (_picking || !widget.enabled) return;
    setState(() => _picking = true);
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
      );
      if (photo != null && context.mounted) widget.onChanged(photo.path);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open photos. Check camera/photo access in phone settings and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 88,
              height: 88,
              child: widget.path == null
                  ? ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 32,
                      ),
                    )
                  : (kIsWeb
                      ? Image.network(
                          widget.path!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        )
                      : Image.file(
                          File(widget.path!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        )),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '${widget.label} (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: widget.enabled && !_picking
                ? () => _pick(context, ImageSource.camera)
                : null,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Camera'),
          ),
          OutlinedButton.icon(
            onPressed: widget.enabled && !_picking
                ? () => _pick(context, ImageSource.gallery)
                : null,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Photos'),
          ),
          if (widget.path != null)
            TextButton(
              onPressed: widget.enabled && !_picking
                  ? () => widget.onChanged(null)
                  : null,
              child: const Text('Remove'),
            ),
        ],
      ),
    ],
  );
}
