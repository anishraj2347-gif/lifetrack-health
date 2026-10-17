import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../capture/profile_photo.dart';
import '../../security/plain_leftovers.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'parts.dart';

/// A person's round photo, or their initials when they have none. The
/// selected person gets a caramel ring ("selected" — never a health status).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.patientId, required this.name, this.size = 44, this.selected = false, this.photo});
  final String? patientId;
  final String name;
  final double size;
  final bool selected;

  /// A photo not yet saved (the add pages show it before the profile exists).
  final Uint8List? photo;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = photo ?? (patientId == null ? null : AppScope.of(context).photoOf(patientId!));
    // Decoded at the size it is drawn, not the photo's own (a face is
    // shown at 32–56 points; the photo may be ten times that).
    final image = bytes == null ? null : ResizeImage(MemoryImage(bytes), width: (size * MediaQuery.devicePixelRatioOf(context)).ceil(), policy: ResizeImagePolicy.fit);
    final face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? LT.accent : LT.raised,
        image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: bytes != null
          ? null
          : Text(initials(name), style: TextStyle(fontFamily: LT.display, fontSize: size * 0.34, fontWeight: FontWeight.w600, color: selected ? LT.onAccent : LT.ink)),
    );
    if (!selected || bytes == null) return ExcludeSemantics(child: face);
    // A photo hides the caramel fill, so the selection is drawn as a ring.
    return ExcludeSemantics(
      child: Container(
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: LT.accent, width: 2.2)),
        child: SizedBox(width: size - 8.4, height: size - 8.4, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, image: DecorationImage(image: image!, fit: BoxFit.cover)))),
      ),
    );
  }
}

/// A face bundled with the app (the sample family), or null if missing.
Future<Uint8List?> bundledPhoto(String asset) async {
  try {
    return (await rootBundle.load(asset)).buffer.asUint8List();
  } on Object {
    return null;
  }
}

/// What the photo sheet returned: a prepared photo, or a request to remove it.
class PhotoPick {
  const PhotoPick(this.jpeg);
  final Uint8List? jpeg;
  bool get removed => jpeg == null;
}

/// Camera or gallery → a small, upright, metadata-free square JPEG. The
/// picker's plain file in the cache is deleted as soon as it is read (#7c).
Future<PhotoPick?> pickProfilePhoto(BuildContext context, {bool canRemove = false}) async {
  final source = await showModalBottomSheet<Object>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text('Profile photo', style: LT.title.copyWith(fontSize: 20))),
          SlabButton('Take a photo', icon: LucideIcons.camera, onPressed: () => Navigator.pop(sheet, ImageSource.camera)),
          SizedBox(height: 10),
          SlabButton('Choose from gallery', icon: LucideIcons.image, variant: ButtonVariant.outline, onPressed: () => Navigator.pop(sheet, ImageSource.gallery)),
          if (canRemove) ...[
            SizedBox(height: 6),
            SlabButton('Remove photo', icon: LucideIcons.trash2, variant: ButtonVariant.ghost, onPressed: () => Navigator.pop(sheet, 'remove')),
          ],
          SizedBox(height: 8),
          Text('Kept on this phone, encrypted, and in your backup if it is on. Never on the Emergency ID.', textAlign: TextAlign.center, style: LT.meta),
        ]),
      ),
    ),
  );
  if (source == 'remove') return const PhotoPick(null);
  if (source is! ImageSource) return null;
  final x = await ImagePicker().pickImage(source: source, preferredCameraDevice: CameraDevice.front, maxWidth: 1600, maxHeight: 1600);
  if (x == null) return null;
  final raw = await x.readAsBytes();
  await deleteQuietly(x.path);
  final jpeg = await compute(prepareProfilePhoto, raw);
  return jpeg == null ? null : PhotoPick(jpeg);
}

/// A big avatar with a camera badge: tap to add or change the photo.
class PhotoEditButton extends StatelessWidget {
  const PhotoEditButton({super.key, required this.name, required this.onPicked, this.patientId, this.photo, this.size = 104});
  final String name;
  final String? patientId;
  final Uint8List? photo;
  final double size;
  final ValueChanged<PhotoPick> onPicked;

  @override
  Widget build(BuildContext context) {
    final has = photo != null || (patientId != null && AppScope.of(context).photoOf(patientId!) != null);
    return Semantics(
      button: true,
      label: has ? 'Change photo' : 'Add a photo',
      child: GestureDetector(
        onTap: () async {
          final p = await pickProfilePhoto(context, canRemove: has);
          if (p != null) onPicked(p);
        },
        child: SizedBox(
          width: size + 6,
          height: size + 6,
          child: Stack(children: [
            PersonAvatar(patientId: patientId, name: name.isEmpty ? '+' : name, photo: photo, size: size),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: LT.button, shape: BoxShape.circle, border: Border.all(color: LT.surface, width: 3)),
                child: Icon(has ? LucideIcons.pencil : LucideIcons.camera, size: 16, color: LT.onButton),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
