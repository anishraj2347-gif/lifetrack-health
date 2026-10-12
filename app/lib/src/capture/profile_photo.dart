import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A person's profile photo as it is kept: a 320 px square JPEG, turned
/// upright, centre-cropped, with every metadata block (location, camera,
/// time) dropped by re-encoding. Returns null for bytes that are not an
/// image. Pure, so it can run on a background isolate.
Uint8List? prepareProfilePhoto(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null; // some decoders throw on bytes that are not their format
  }
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final side = upright.width < upright.height ? upright.width : upright.height;
  final square = img.copyCrop(upright, x: (upright.width - side) ~/ 2, y: (upright.height - side) ~/ 2, width: side, height: side);
  final small = img.copyResize(square, width: 320, height: 320, interpolation: img.Interpolation.average);
  small.exif.clear();
  return img.encodeJpg(small, quality: 82);
}
