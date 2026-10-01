import 'dart:js_interop';

import 'local_cipher.dart';

@JS('ltVault.seal')
external JSPromise<JSString> _seal(JSString plain);

@JS('ltVault.open')
external JSPromise<JSString> _open(JSString sealed);

@JS('ltVault.reset')
external JSPromise<JSAny?> _reset();

class WebCryptoCipher implements LocalCipher {
  @override
  Future<String> seal(String plain) async => (await _seal(plain.toJS).toDart).toDart;

  @override
  Future<String> open(String sealed) async => (await _open(sealed.toJS).toDart).toDart;

  @override
  Future<void> reset() async => _reset().toDart;
}

LocalCipher createCipher() => WebCryptoCipher();
