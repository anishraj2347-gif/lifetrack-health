import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'byte_store.dart';

/// The original pages of a paper report or prescription, encrypted under
/// the device key like every record.
///
/// Frame per page: `magic('LA') ‖ version ‖ nonce(12) ‖ mac(16) ‖ jpeg`.
/// A separate magic from records ('LT') so a page can never be mistaken for
/// a record blob, or the other way round. Version 2 binds each page to its
/// blob name (associated data), so pages cannot be swapped between records
/// or reordered; version 1 pages still open.
class AttachmentStore {
  AttachmentStore(this.bytes, this.key);

  final ByteStore bytes;
  final SecretKey key;

  static const _magic = [0x4C, 0x41];
  static const _version = 2;
  static List<int> _aad(String blob) => utf8.encode('lifetrack/page/v2|$blob');
  static final _aead = AesGcm.with256bits();

  static String _page(String id, int n) => 'att_${id}_$n';
  static String _count(String id) => 'att_${id}_count';

  Future<void> save(String id, List<Uint8List> pages) async {
    for (var i = 0; i < pages.length; i++) {
      final box = await _aead.encrypt(pages[i], secretKey: key, aad: _aad(_page(id, i)));
      await bytes.write(_page(id, i), Uint8List.fromList([..._magic, _version, ...box.nonce, ...box.mac.bytes, ...box.cipherText]));
    }
    await bytes.write(_count(id), Uint8List.fromList([pages.length]));
  }

  Future<int> pageCount(String id) async => (await bytes.read(_count(id)))?.first ?? 0;

  Future<List<Uint8List>> load(String id) async {
    final n = await pageCount(id);
    return [
      for (var i = 0; i < n; i++)
        if (await bytes.read(_page(id, i)) case final frame?) await _open(frame, _page(id, i)),
    ];
  }

  Future<Uint8List> _open(Uint8List f, String blob) async {
    if (f.length < 31 || f[0] != _magic[0] || f[1] != _magic[1] || f[2] < 1 || f[2] > _version) {
      throw const FormatException('Not a LifeTrack page.');
    }
    final plain = await _aead.decrypt(SecretBox(f.sublist(31), nonce: f.sublist(3, 15), mac: Mac(f.sublist(15, 31))),
        secretKey: key, aad: f[2] >= 2 ? _aad(blob) : const []);
    return Uint8List.fromList(plain);
  }

  Future<void> delete(String id) async {
    final n = await pageCount(id);
    for (var i = 0; i < n; i++) {
      await bytes.delete(_page(id, i));
    }
    await bytes.delete(_count(id));
  }
}
