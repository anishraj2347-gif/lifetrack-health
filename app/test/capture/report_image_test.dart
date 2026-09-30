import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lifetrack/src/capture/report_image.dart';
import 'package:lifetrack/src/storage/attachment_store.dart';
import 'package:lifetrack/src/storage/byte_store.dart';

/// A 4000×3000 "phone photo" carrying a GPS position and a rotation tag.
Uint8List phonePhoto() {
  final im = img.Image(width: 4000, height: 3000);
  img.fill(im, color: img.ColorRgb8(240, 240, 240));
  im.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(28, 1);
  im.exif.imageIfd['Make'] = img.IfdValueAscii('PhoneMaker');
  im.exif.imageIfd.orientation = 6; // rotated 90° by the camera
  return img.encodeJpg(im);
}

void main() {
  test('a kept page is upright, at most 1800 px, and carries no metadata', () {
    final raw = phonePhoto();
    expect(img.decodeJpg(raw)!.exif.gpsIfd.isEmpty, isFalse, reason: 'the fixture really has GPS');
    final kept = ReportImage.prepareSync(raw);
    final back = img.decodeJpg(kept)!;
    expect(back.exif.gpsIfd.isEmpty, isTrue, reason: 'GPS position removed');
    expect(back.exif.imageIfd.hasMake, isFalse, reason: 'device removed');
    expect(back.width < back.height, isTrue, reason: 'rotation applied to the pixels');
    expect(back.height, ReportImage.maxSide);
    expect(kept.length, lessThan(raw.length));
  });

  test('something that is not a photo is refused plainly', () {
    expect(() => ReportImage.prepareSync(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('pages are encrypted at rest and come back intact, in order', () async {
    final bytes = InMemoryByteStore();
    final store = AttachmentStore(bytes, SecretKey(List.filled(32, 9)));
    final p1 = ReportImage.prepareSync(phonePhoto());
    final p2 = Uint8List.fromList([...p1.reversed]);
    await store.save('r1', [p1, p2]);
    for (final name in await bytes.names()) {
      final stored = (await bytes.read(name))!;
      expect(stored.length > 2 && stored[0] == 0xFF && stored[1] == 0xD8, isFalse, reason: '$name is not a readable JPEG');
    }
    final back = await store.load('r1');
    expect(back, hasLength(2));
    expect(back[0], p1);
    expect(back[1], p2);
    await store.delete('r1');
    expect(await store.load('r1'), isEmpty);
  });
}
