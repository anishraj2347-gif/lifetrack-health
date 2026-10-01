import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Records are only ever stored encrypted. These remove the plain copies
/// that pass through the app's cache on their way in or out: a camera photo
/// before it is cleaned and sealed, a PDF picked from the phone, an export
/// or Emergency ID image handed to the share sheet.

Future<void> deleteQuietly(String? path) async {
  if (path == null) return;
  try {
    await File(path).delete();
  } on Object {
    // Already gone, or outside the app's own storage.
  }
}

/// Run when the app opens: anything a crash or a closed share sheet left in
/// the cache goes. Only names LifeTrack or its plugins create are touched.
Future<int> sweepPlainLeftovers([Directory? cache]) async {
  var n = 0;
  try {
    final dir = cache ?? await getTemporaryDirectory();
    if (!await dir.exists()) return 0;
    await for (final e in dir.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((x) => x.isNotEmpty).last;
      final plain = e is File && (isPlainLeftover(name));
      final pluginDir = e is Directory && (name == 'share_plus' || name == 'file_picker');
      if (plain || pluginDir) {
        try {
          await e.delete(recursive: true);
          n++;
        } on Object {
          // In use; the next start tries again.
        }
      }
    }
  } on Object {
    // No cache directory on this platform.
  }
  return n;
}

bool isPlainLeftover(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('image_picker') ||
      lower.startsWith('lifetrack') ||
      lower == 'emergency-id.png' ||
      lower.endsWith('.pdf') ||
      lower.endsWith('.zip') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.heic');
}
