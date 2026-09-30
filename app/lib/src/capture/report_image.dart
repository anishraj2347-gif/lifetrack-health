import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Turns a raw camera or gallery photo of a paper report into what LifeTrack
/// keeps: upright, at most 1800 px on the long side, JPEG, and with ALL
/// metadata removed.
///
/// Stripping matters: a phone photo's EXIF can hold the GPS position where
/// it was taken (a home or a clinic), the time and the device. None of that
/// belongs in a medical record or in a share to a doctor.
abstract final class ReportImage {
  static const maxSide = 1800;
  static const quality = 78;

  /// Runs off the UI thread: decoding a 12-megapixel photo drops frames.
  static Future<Uint8List> prepare(Uint8List raw) => compute(prepareSync, raw);

  static Uint8List prepareSync(Uint8List raw) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(raw);
    } on Object {
      decoded = null; // a truncated or corrupt file must not crash the app
    }
    if (decoded == null) throw const FormatException('That file is not a photo LifeTrack can read.');
    // Apply the camera's rotation to the pixels, then forget it.
    var im = img.bakeOrientation(decoded);
    final long = im.width > im.height ? im.width : im.height;
    if (long > maxSide) {
      im = im.width >= im.height ? img.copyResize(im, width: maxSide) : img.copyResize(im, height: maxSide);
    }
    im.exif.clear();
    im.iccProfile = null;
    im.textData = null;
    return img.encodeJpg(im, quality: quality);
  }

  /// A smaller copy for a doctor's share, where several pages must fit.
  static Uint8List forShare(Uint8List kept) {
    final im = img.decodeJpg(kept);
    if (im == null) return kept;
    final long = im.width > im.height ? im.width : im.height;
    if (long <= 1400) return kept;
    final s = im.width >= im.height ? img.copyResize(im, width: 1400) : img.copyResize(im, height: 1400);
    return img.encodeJpg(s, quality: 70);
  }
}
