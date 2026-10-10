class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}

class RevisionConflictException extends AppException {
  const RevisionConflictException([
    super.message =
        'This receipt changed since it was opened. Reopen the current receipt before saving.',
  ]);
}

class ReceiptSnapshotException extends AppException {
  const ReceiptSnapshotException(super.message);
}

class DuplicateReceiptException extends AppException {
  const DuplicateReceiptException(this.receiptIds)
    : super(
        'A similar receipt is already saved. Open the earlier receipt or confirm that this is a separate purchase.',
      );
  final List<String> receiptIds;
}

String userMessage(Object error) => error is AppException
    ? error.message
    : 'Could not complete this on your phone. Your saved records are intact. Please try again.';
