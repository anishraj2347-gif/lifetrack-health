import 'dart:typed_data';

import '../../model/health_record.dart';

/// Plane B: turns a photo of a paper document into a draft record.
///
/// Interface only. No extractor ships yet — the costly part is field
/// extraction (which number is the dose, which date is the report date), not
/// the OCR. A draft is never saved without the patient confirming each field.
abstract interface class CaptureExtractor {
  Future<CaptureDraft> extract(Uint8List image);
}

class DraftField<T> {
  const DraftField(this.value, {required this.confidence});
  final T? value;

  /// 0..1. Below [needsReview] the field is shown in the caution style.
  final double confidence;
  static const needsReview = 0.85;
  bool get uncertain => value == null || confidence < needsReview;
}

class CaptureDraft {
  const CaptureDraft({required this.kind, required this.title, required this.date, this.doctor, this.results = const []});
  final DraftField<RecordKind> kind;
  final DraftField<String> title;
  final DraftField<DateTime> date;
  final DraftField<String>? doctor;
  final List<DraftField<LabResult>> results;
}
