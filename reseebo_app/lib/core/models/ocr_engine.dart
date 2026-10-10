enum OcrEngineId {
  mlKit('mlkit'),
  ppOcrV5Mobile('ppocr_v5_mobile'),
  ppOcrV6Medium('ppocr_v6_medium');

  const OcrEngineId(this.wireId);
  final String wireId;

  static OcrEngineId fromWireId(String value) => values.firstWhere(
    (id) => id.wireId == value,
    orElse: () => throw FormatException('Unknown OCR engine: $value'),
  );
}

/// Availability means the packaged model and native runtime have been verified;
/// an advertised model name alone does not make an engine usable.
class OcrEngineDescriptor {
  const OcrEngineDescriptor({
    required this.id,
    required this.label,
    required this.modelVersion,
    required this.runtimeVersion,
    required this.available,
    this.unavailableReason,
  });
  final OcrEngineId id;
  final String label;
  final String modelVersion;
  final String runtimeVersion;
  final bool available;
  final String? unavailableReason;
}

/// Identity of one complete receipt reading, including ordered input content.
/// Elapsed time is wall-clock milliseconds for recognition and evidence passes.
class OcrRunMetadata {
  const OcrRunMetadata({
    required this.engineId,
    required this.modelVersion,
    required this.runtimeVersion,
    required this.parserVersion,
    required this.inputDigest,
    required this.preprocessingRevision,
    required this.elapsedMs,
  });
  final OcrEngineId engineId;
  final String modelVersion;
  final String runtimeVersion;
  final String parserVersion;
  final String inputDigest;
  final String preprocessingRevision;
  final int elapsedMs;

  Map<String, dynamic> toJson() => {
    'engineId': engineId.wireId,
    'modelVersion': modelVersion,
    'runtimeVersion': runtimeVersion,
    'parserVersion': parserVersion,
    'inputDigest': inputDigest,
    'preprocessingRevision': preprocessingRevision,
    'elapsedMs': elapsedMs,
  };

  factory OcrRunMetadata.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid OCR run $key');
      }
      return value;
    }

    final elapsed = json['elapsedMs'];
    if (elapsed is! int || elapsed < 0) {
      throw const FormatException('Invalid OCR run elapsedMs');
    }
    return OcrRunMetadata(
      engineId: OcrEngineId.fromWireId(text('engineId')),
      modelVersion: text('modelVersion'),
      runtimeVersion: text('runtimeVersion'),
      parserVersion: text('parserVersion'),
      inputDigest: text('inputDigest'),
      preprocessingRevision: text('preprocessingRevision'),
      elapsedMs: elapsed,
    );
  }
}
