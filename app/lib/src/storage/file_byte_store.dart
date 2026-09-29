import 'dart:convert';
import 'dart:io' show Directory, File, FileMode;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'byte_store.dart';

/// [ByteStore] on the local filesystem, honouring the atomicity contract:
/// temp file → flush → rename.
///
/// File names are a hash of the blob name, so no caller-supplied string can
/// traverse out of [root] and the directory listing reveals nothing.
class FileByteStore implements ByteStore {
  FileByteStore(this.root);

  final Directory root;

  Future<File> _fileFor(String name) async {
    final digest = await Sha256().hash(utf8.encode('lifetrack-blob:$name'));
    final hex = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return File('${root.path}/$hex.lt');
  }

  @override
  Future<Uint8List?> read(String name) async {
    final f = await _fileFor(name);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    await root.create(recursive: true);
    final target = await _fileFor(name);
    final temp = File('${target.path}.tmp');
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temp.rename(target.path);
    await _index(name, add: true);
  }

  @override
  Future<void> delete(String name) async {
    final f = await _fileFor(name);
    if (await f.exists()) await f.delete();
    await _index(name, add: false);
  }

  @override
  Future<List<String>> names() async {
    final idx = File('${root.path}/index.json');
    if (!await idx.exists()) return [];
    return (jsonDecode(await idx.readAsString()) as List).cast<String>();
  }

  Future<void> _index(String name, {required bool add}) async {
    final current = (await names()).toSet();
    if (add ? !current.add(name) : !current.remove(name)) return;
    final idx = File('${root.path}/index.json');
    final temp = File('${idx.path}.tmp');
    await temp.writeAsString(jsonEncode(current.toList()), flush: true);
    await temp.rename(idx.path);
  }
}
