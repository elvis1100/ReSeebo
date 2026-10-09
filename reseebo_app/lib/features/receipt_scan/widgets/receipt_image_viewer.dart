import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

Future<void> openReceiptImage(BuildContext context, String path) =>
    openReceiptImages(context, [path]);

Future<void> openReceiptImages(
  BuildContext context,
  List<String> paths, {
  int initialPage = 0,
}) async {
  if (paths.isEmpty) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => _OriginalReceiptScreen(
        paths: List.of(paths),
        initialPage: initialPage,
      ),
    ),
  );
}

class _OriginalReceiptScreen extends StatefulWidget {
  const _OriginalReceiptScreen({
    required this.paths,
    required this.initialPage,
  });
  final List<String> paths;
  final int initialPage;
  @override
  State<_OriginalReceiptScreen> createState() => _OriginalReceiptScreenState();
}

class _OriginalReceiptScreenState extends State<_OriginalReceiptScreen> {
  late int _page;
  final _transform = TransformationController();
  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(0, widget.paths.length - 1);
  }

  void _select(int page) {
    setState(() {
      _page = page;
      _transform.value = Matrix4.identity();
    });
  }

  void _zoom() {
    final scale = (_transform.value.getMaxScaleOnAxis() * 1.5).clamp(1.0, 8.0);
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Original receipt')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              key: ValueKey(widget.paths[_page]),
              transformationController: _transform,
              minScale: 0.5,
              maxScale: 8,
              child: Center(
                child: Image.file(
                  File(widget.paths[_page]),
                  fit: BoxFit.contain,
                  semanticLabel: 'Original receipt photo, page ${_page + 1}',
                  errorBuilder: (_, _, _) => const Padding(
                    padding: AppSpacing.page,
                    child: Text(
                      'This original photo could not be opened. The recorded purchase details remain available.',
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: AppSpacing.page,
            child: Column(
              children: [
                if (widget.paths.length > 1)
                  _PageControls(
                    index: _page,
                    count: widget.paths.length,
                    enabled: true,
                    onSelected: _select,
                  ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _zoom,
                      icon: const Icon(Icons.zoom_in),
                      label: const Text('Zoom in'),
                    ),
                    TextButton.icon(
                      onPressed: () => _transform.value = Matrix4.identity(),
                      icon: const Icon(Icons.zoom_out_map),
                      label: const Text('Reset zoom'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.index,
    required this.count,
    required this.enabled,
    required this.onSelected,
  });
  final int index, count;
  final bool enabled;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Previous original page',
        onPressed: enabled && index > 0 ? () => onSelected(index - 1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Text(
          'Original page ${index + 1} of $count',
          textAlign: TextAlign.center,
        ),
      ),
      IconButton(
        tooltip: 'Next original page',
        onPressed: enabled && index + 1 < count
            ? () => onSelected(index + 1)
            : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class ReceiptImagesPreview extends StatefulWidget {
  const ReceiptImagesPreview({
    super.key,
    required this.paths,
    this.height = 200,
    this.enabled = true,
  });
  final List<String> paths;
  final double height;
  final bool enabled;
  @override
  State<ReceiptImagesPreview> createState() => _ReceiptImagesPreviewState();
}

class _ReceiptImagesPreviewState extends State<ReceiptImagesPreview> {
  int _page = 0;
  @override
  void didUpdateWidget(covariant ReceiptImagesPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paths.isNotEmpty) {
      _page = _page.clamp(0, widget.paths.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paths.isEmpty) {
      return const Text('Original receipt photos unavailable.');
    }
    return Column(
      children: [
        if (widget.paths.length > 1)
          _PageControls(
            index: _page,
            count: widget.paths.length,
            enabled: widget.enabled,
            onSelected: (index) => setState(() => _page = index),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Image.file(
              File(widget.paths[_page]),
              fit: BoxFit.contain,
              cacheWidth: 900,
              semanticLabel: 'Original receipt preview, page ${_page + 1}',
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('Receipt preview unavailable')),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: widget.enabled
              ? () =>
                    openReceiptImages(context, widget.paths, initialPage: _page)
              : null,
          icon: const Icon(Icons.zoom_in),
          label: const Text('Open original · pinch to zoom'),
        ),
      ],
    );
  }
}

class ReceiptImagePreview extends StatelessWidget {
  const ReceiptImagePreview({
    super.key,
    required this.path,
    this.height = 200,
    this.enabled = true,
  });
  final String path;
  final double height;
  final bool enabled;
  @override
  Widget build(BuildContext context) =>
      ReceiptImagesPreview(paths: [path], height: height, enabled: enabled);
}
