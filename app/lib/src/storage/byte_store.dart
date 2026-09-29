import 'dart:typed_data';

/// Named blobs on local storage.
///
/// **Atomicity contract.** [write] must replace the blob entirely or not at
/// all: write a temp file, flush it, rename over the target. Callers rely on
/// this — the record set is rewritten whole on every change, so a torn write
/// would lose *every* record, not only the one being added.
///
/// Residual, recorded rather than hidden: Dart cannot fsync a directory, so a
/// power loss right after the rename can roll back to the previous blob. It
/// cannot produce a torn one.
abstract interface class ByteStore {
  Future<Uint8List?> read(String name);
  Future<void> write(String name, Uint8List bytes);
  Future<void> delete(String name);
  Future<List<String>> names();
}

/// For tests and for widget tests that must never touch a platform channel.
class InMemoryByteStore implements ByteStore {
  final Map<String, Uint8List> _blobs = {};

  @override
  Future<Uint8List?> read(String name) async => _blobs[name];

  @override
  Future<void> write(String name, Uint8List bytes) async =>
      _blobs[name] = Uint8List.fromList(bytes);

  @override
  Future<void> delete(String name) async => _blobs.remove(name);

  @override
  Future<List<String>> names() async => _blobs.keys.toList();
}
