import 'package:flutter/foundation.dart';

/// Owns local load/save state. A failed write preserves the caller's form values;
/// concurrent submissions are ignored and success is exposed only after commit.
class LocalEditorController<T> extends ChangeNotifier {
  LocalEditorController({required this.write, this.read});
  final Future<T> Function()? read;
  final Future<void> Function(T) write;
  T? value;
  Object? error;
  bool loading = false;
  bool saving = false;
  bool saved = false;
  bool _disposed = false;
  int _request = 0;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (read == null || saving) return;
    final request = ++_request;
    loading = true;
    error = null;
    _changed();
    try {
      final result = await read!();
      if (!_disposed && request == _request) value = result;
    } catch (failure) {
      if (!_disposed && request == _request) error = failure;
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        _changed();
      }
    }
  }

  Future<bool> save(T input) async {
    if (saving || loading || _disposed) return false;
    saving = true;
    error = null;
    _changed();
    try {
      await write(input);
      if (_disposed) return false;
      saved = true;
      return true;
    } catch (failure) {
      if (!_disposed) error = failure;
      return false;
    } finally {
      saving = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
