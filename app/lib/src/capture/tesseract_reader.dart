import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../ai/plane_b/capture.dart';

/// Reads a page with Tesseract inside the app (Android, `MainActivity`).
///
/// The page goes over as grey pixels in memory — never as a file, so there
/// is no plain copy to sweep (CLAUDE.md #7c) — and nothing leaves the phone.
class TesseractPageReader implements PageReader {
  static const _channel = MethodChannel('lifetrack/ocr');

  @override
  Future<OcrPage> read(Uint8List page) async {
    final grey = await compute(greyForOcr, page);
    final words = await _channel.invokeListMethod<Map<Object?, Object?>>('read', {'pixels': grey.pixels, 'width': grey.width, 'height': grey.height});
    return OcrPage([
      for (final w in words ?? const <Map<Object?, Object?>>[])
        OcrWord(
          w['t']! as String,
          confidence: (w['c']! as num).toDouble(),
          left: w['l']! as int,
          top: w['u']! as int,
          right: w['r']! as int,
          bottom: w['b']! as int,
          line: w['n']! as int,
        ),
    ]);
  }
}

typedef GreyPage = ({Uint8List pixels, int width, int height});

/// Upright, one byte per pixel, and sized for Tesseract: small text needs
/// about 2000 px on the long side; much more only slows it down.
GreyPage greyForOcr(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw const FormatException('That page could not be read.');
  var im = img.bakeOrientation(decoded);
  final long = im.width > im.height ? im.width : im.height;
  const target = 2200;
  if (long > target || long < 1400) {
    im = im.width >= im.height
        ? img.copyResize(im, width: target, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: target, interpolation: img.Interpolation.average);
  }
  final out = Uint8List(im.width * im.height);
  var i = 0;
  for (final p in im) {
    out[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) * 255 ~/ p.maxChannelValue;
  }
  return (pixels: out, width: im.width, height: im.height);
}
