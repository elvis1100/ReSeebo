import 'package:integration_test/integration_test_driver.dart';

// The driver avoids the SDK's VM golden-stream listener for native storage/OCR
// checks, which do not use golden files. The app's test data remains isolated.
Future<void> main() => integrationDriver();
