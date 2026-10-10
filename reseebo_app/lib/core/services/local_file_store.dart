import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../errors/app_exception.dart';

class StoredLocalFile {
  const StoredLocalFile({
    required this.path,
    required this.hash,
    required this.created,
  });
  final String path;
  final String hash;
  final bool created;
}

/// Files are copied before committing references. Only files newly created by
/// the operation may be removed on failure; picker originals remain untouched.
class LocalFileStore {
  LocalFileStore(this.directory);
  final Directory directory;

  Future<String> hash(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists() || await source.length() == 0) {
      throw const ValidationException('Choose a readable, non-empty image.');
    }
    return (await sha256.bind(source.openRead()).first).toString();
  }

  Future<StoredLocalFile> persist(
    String sourcePath, {
    required String category,
    String? existingPath,
  }) async {
    final source = File(sourcePath);
    final digest = await hash(sourcePath);
    if (existingPath == sourcePath && owns(sourcePath)) {
      return StoredLocalFile(path: sourcePath, hash: digest, created: false);
    }
    if (!RegExp(r'^[a-z_]+$').hasMatch(category)) {
      throw ArgumentError.value(category, 'category');
    }
    final destination = Directory(p.join(directory.path, category));
    await destination.create(recursive: true);
    final extension = p.extension(sourcePath).toLowerCase();
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : '.jpg';
    final targetPath = p.join(
      destination.path,
      '${const Uuid().v4()}$safeExtension',
    );
    final stagingPath = '$targetPath.partial';
    try {
      await source.copy(stagingPath);
      // Read the actual copy: concurrent edits to an external picker source
      // cannot leave the receipt's stored hash describing different bytes.
      final copiedHash = await hash(stagingPath);
      if (copiedHash != digest) {
        throw const ValidationException(
          'The image changed while saving. Please select it again.',
        );
      }
      await File(stagingPath).rename(targetPath);
      return StoredLocalFile(path: targetPath, hash: copiedHash, created: true);
    } catch (_) {
      await remove(stagingPath);
      await remove(targetPath);
      rethrow;
    }
  }

  bool owns(String path) =>
      p.isWithin(p.absolute(directory.path), p.absolute(path));

  /// Cleanup is best-effort after a failed operation or a committed replacement.
  /// Failure to remove an orphan must not turn a successful commit into a retry.
  Future<void> remove(String? path) async {
    if (path == null || !owns(path)) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A later successful operation remains safe even if cleanup is unavailable.
    }
  }
}
