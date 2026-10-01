import 'local_cipher_stub.dart' if (dart.library.js_interop) 'local_cipher_web.dart' as impl;

/// Encrypts what this page keeps in browser storage. On the web the key is a
/// non-extractable WebCrypto key in IndexedDB (see web/index.html); tests use
/// MemoryCipher.
abstract interface class LocalCipher {
  static const prefix = 'lt1:';
  Future<String> seal(String plain);

  /// Throws if [sealed] was not sealed by this browser's key.
  Future<String> open(String sealed);

  /// Forgets the key (Start over): everything sealed under it is unreadable.
  Future<void> reset();
}

LocalCipher platformCipher() => impl.createCipher();
