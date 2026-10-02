import 'dart:typed_data';

import '../../model/health_record.dart';
import 'report_parser.dart';

/// Plane B: turns the pages of a paper or PDF document into a draft record.
///
/// Everything happens on the phone: [PageReader] reads the words (Tesseract,
/// on device), [parseCapture] turns them into fields. A draft is never saved
/// until the patient has checked it against the photo — every uncertain
/// field one by one, then the whole draft once.

/// One word read off a page, with where it sits. [line] is the reader's own
/// text-line number, so words split across table columns can be rejoined.
class OcrWord {
  const OcrWord(this.text, {required this.confidence, required this.left, required this.top, required this.right, required this.bottom, this.line = 0});
  final String text;

  /// 0..100, as the reader reports it.
  final double confidence;
  final int left, top, right, bottom;
  final int line;

  int get height => bottom - top;
  double get midY => (top + bottom) / 2;
}

class OcrPage {
  const OcrPage(this.words);
  final List<OcrWord> words;
}

/// Reads the words on one page image. Implementations must not send the
/// page anywhere (CLAUDE.md #1).
abstract interface class PageReader {
  Future<OcrPage> read(Uint8List page);
}

class CaptureExtractor {
  const CaptureExtractor(this.reader);
  final PageReader reader;

  Future<CaptureDraft> extract(List<Uint8List> pages, {required DateTime today, void Function(int done, int total)? progress}) async {
    final read = <OcrPage>[];
    for (final (i, p) in pages.indexed) {
      progress?.call(i, pages.length);
      read.add(await reader.read(p));
    }
    progress?.call(pages.length, pages.length);
    return parseCapture(read, today: today);
  }
}

class DraftField<T> {
  const DraftField(this.value, {required this.confidence, this.seen});
  const DraftField.none() : value = null, confidence = 0, seen = null;
  final T? value;

  /// 0..1. Below [needsReview] the patient must tick or correct the field.
  final double confidence;
  static const needsReview = 0.85;
  bool get uncertain => value == null || confidence < needsReview;

  /// The line on the page this was read from, shown next to the field so the
  /// patient can find it on the photo.
  final String? seen;

  DraftField<T> capped(double max) => DraftField(value, confidence: confidence < max ? confidence : max, seen: seen);
}

/// One medicine read off a prescription. Becomes one prescription record.
class DraftMedicine {
  const DraftMedicine({required this.name, this.dose = const DraftField.none(), this.timing = const DraftField.none(), this.days = const DraftField.none()});

  /// As written, with its strength: "Metformin 500 mg".
  final DraftField<String> name;
  final DraftField<Dose> dose;

  /// `before_food`, `after_food` or `with_food`.
  final DraftField<String> timing;
  final DraftField<int> days;

  DraftMedicine capped(double max) => DraftMedicine(name: name.capped(max), dose: dose.capped(max), timing: timing.capped(max), days: days.capped(max));
}

class CaptureDraft {
  const CaptureDraft({
    required this.kind,
    this.title = const DraftField.none(),
    this.date = const DraftField.none(),
    this.place = const DraftField.none(),
    this.doctor = const DraftField.none(),
    this.results = const [],
    this.medicines = const [],
    this.handwriting = false,
  });

  /// Nothing could be read: the patient fills the form as before.
  static const empty = CaptureDraft(kind: DraftField(RecordKind.report, confidence: 0));

  final DraftField<RecordKind> kind;

  /// Report or scan name. Prescriptions take their title from each medicine.
  final DraftField<String> title;

  /// For a report, the sample date when printed; else the document date.
  final DraftField<DateTime> date;

  /// The lab (report) or the clinic or hospital (prescription).
  final DraftField<String> place;
  final DraftField<String> doctor;
  final List<DraftField<LabResult>> results;
  final List<DraftMedicine> medicines;

  /// The page looks handwritten: nothing on it is trusted without a tick.
  final bool handwriting;

  bool get readAnything => title.value != null || date.value != null || place.value != null || results.isNotEmpty || medicines.isNotEmpty;
}
