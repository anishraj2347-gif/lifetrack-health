import 'package:cryptography/cryptography.dart';

import '../crypto/vault_codec.dart';
import 'byte_store.dart';

/// JSON documents sealed under the device key, over any [ByteStore].
///
/// Records, grants and the audit log all go through here, so all three are
/// encrypted at rest and all three get the framing and schema guarantees.
class SealedStore {
  SealedStore(this.bytes, this.key);

  final ByteStore bytes;
  final SecretKey key;

  /// Each blob is sealed bound to its [name] (frame version 2). A blob
  /// written before that is read once and rewritten bound.
  Future<Object?> read(String name) async {
    final frame = await bytes.read(name);
    if (frame == null) return null;
    final body = await VaultCodec.open(frame, key, name: name);
    if (VaultCodec.versionOf(frame) == 1) await write(name, body);
    return body;
  }

  Future<void> write(String name, Object? body) async =>
      bytes.write(name, await VaultCodec.seal(body, key, name: name));

  Future<void> delete(String name) => bytes.delete(name);
}
