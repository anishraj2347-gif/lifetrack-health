import 'dart:convert';
import 'dart:io' show Directory, File, FileMode;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/vault_codec.dart';
import 'byte_store.dart';

/// [ByteStore] on the local filesystem, honouring the atomicity contract:
/// temp file → flush → rename.
///
/// File names are a hash of the blob name, so no caller-supplied string can
/// traverse out of [root]. The index of names is sealed under [indexKey]
/// when one is given (the app always gives the device key), so the folder
/// reveals neither names nor what they say about the profiles on the phone.
class FileByteStore implements ByteStore {
  FileByteStore(this.root, {this.indexKey});

  final Directory root;
  final SecretKey? indexKey;
  static const _indexName = 'lifetrack/index';

  /// Every write and delete runs one at a time. Unserialised, two saves at
  /// the same moment (a share writes grants, audit and tokens together)
  /// interleaved their index updates and corrupted it — seen on a phone in
  /// the phase 2 demo.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

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
  Future<void> write(String name, Uint8List bytes) => _serial(() => _write(name, bytes));

  Future<void> _write(String name, Uint8List bytes) async {
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
  Future<void> delete(String name) => _serial(() => _delete(name));

  Future<void> _delete(String name) async {
    final f = await _fileFor(name);
    if (await f.exists()) await f.delete();
    await _index(name, add: false);
  }

  @override
  Future<List<String>> names() async {
    final idx = File('${root.path}/index.json');
    if (!await idx.exists()) return [];
    final raw = await idx.readAsBytes();
    final key = indexKey;
    if (key != null && VaultCodec.versionOf(raw) != null) {
      try {
        return ((await VaultCodec.open(raw, key, name: _indexName))! as List).cast<String>();
      } on Object {
        // A damaged sealed index: names are only a listing, never needed to
        // read a blob. Start again; the next save rewrites it.
        return [];
      }
    }
    // A plain index (no key, or written before the index was sealed).
    final text = utf8.decode(raw, allowMalformed: true);
    try {
      return (jsonDecode(text) as List).cast<String>();
    } on FormatException {
      // A damaged index must never block saving records. Recover every name
      // still readable in it; the next save rewrites it whole.
      return [for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(text)) m.group(1)!];
    }
  }

  Future<void> _index(String name, {required bool add}) async {
    final current = (await names()).toSet();
    if (add ? !current.add(name) : !current.remove(name)) return;
    final idx = File('${root.path}/index.json');
    final temp = File('${idx.path}.tmp');
    final key = indexKey;
    await temp.writeAsBytes(key == null ? utf8.encode(jsonEncode(current.toList())) : await VaultCodec.seal(current.toList(), key, name: _indexName), flush: true);
    await temp.rename(idx.path);
  }
}
