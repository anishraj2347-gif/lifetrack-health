import 'dart:convert';
import 'dart:io';

/// LifeTrack IDs → where to reach that person: a reply mailbox and the
/// public key messages to it are sealed to. No name, no records, no phone
/// number. Only the phone holding the ID's token can move or delete it.
class IdRegistry {
  IdRegistry._(this.file, this._ids);

  final File? file;
  final Map<String, Map<String, Object?>> _ids;

  static Future<IdRegistry> open({File? file}) async {
    final ids = <String, Map<String, Object?>>{};
    if (file != null && await file.exists()) {
      for (final e in (jsonDecode(await file.readAsString()) as Map).entries) {
        ids[e.key as String] = (e.value as Map).cast();
      }
    }
    return IdRegistry._(file, ids);
  }

  Map<String, Object?>? operator [](String id) => _ids[id];
  bool contains(String id) => _ids.containsKey(id);

  /// The ID already issued to this verified person, if any.
  String? bySubject(String subject) {
    for (final e in _ids.entries) {
      if (e.value['subject'] == subject) return e.key;
    }
    return null;
  }

  Future<void> put(String id, Map<String, Object?> entry) async {
    _ids[id] = entry;
    await _save();
  }

  Future<void> remove(String id) async {
    _ids.remove(id);
    await _save();
  }

  Future<void> _save() async {
    final f = file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_ids), flush: true);
    await tmp.rename(f.path);
  }
}
