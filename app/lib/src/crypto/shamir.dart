import 'dart:math';
import 'dart:typed_data';

/// One share of a Shamir split over GF(2^8).
///
/// Carries its [threshold] so combining fewer shares than needed throws
/// instead of returning plausible wrong bytes.
class Share {
  Share({required this.index, required this.threshold, required this.splitId, required List<int> bytes})
      : bytes = Uint8List.fromList(bytes) {
    if (index < 1 || index > 255) throw ArgumentError('Share index must be 1..255.');
  }

  final int index;
  final int threshold;

  /// Identifies the split this share came from; mixing splits is refused.
  final String splitId;
  final Uint8List bytes;

  /// Printable form: `LT1-<index>-<threshold>-<splitId>-<hex>`.
  String encode() =>
      'LT1-$index-$threshold-$splitId-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  static Share decode(String s) {
    final p = s.trim().split('-');
    if (p.length != 5 || p[0] != 'LT1') throw const FormatException('Not a LifeTrack recovery share.');
    final hex = p[4];
    return Share(
      index: int.parse(p[1]),
      threshold: int.parse(p[2]),
      splitId: p[3],
      bytes: [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)],
    );
  }
}

abstract final class Shamir {
  static List<Share> split(List<int> secret, {required int threshold, required int count, Random? random}) {
    if (threshold < 2 || threshold > count || count > 255) {
      throw ArgumentError('Need 2 <= threshold <= count <= 255.');
    }
    final rng = random ?? Random.secure();
    final splitId = List.generate(4, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final out = List.generate(count, (_) => Uint8List(secret.length));
    for (var b = 0; b < secret.length; b++) {
      final coeffs = [secret[b], for (var k = 1; k < threshold; k++) rng.nextInt(256)];
      for (var s = 0; s < count; s++) {
        final x = s + 1;
        var y = 0;
        for (var k = coeffs.length - 1; k >= 0; k--) {
          y = _mul(y, x) ^ coeffs[k];
        }
        out[s][b] = y;
      }
    }
    return [
      for (var s = 0; s < count; s++)
        Share(index: s + 1, threshold: threshold, splitId: splitId, bytes: out[s]),
    ];
  }

  static Uint8List combine(List<Share> shares) {
    if (shares.isEmpty) throw ArgumentError('No shares.');
    final threshold = shares.first.threshold;
    final splitId = shares.first.splitId;
    final len = shares.first.bytes.length;
    if (shares.any((s) => s.splitId != splitId || s.threshold != threshold || s.bytes.length != len)) {
      throw ArgumentError('These shares come from different recovery sets.');
    }
    if (shares.map((s) => s.index).toSet().length != shares.length) {
      throw ArgumentError('The same share was given twice.');
    }
    if (shares.length < threshold) {
      throw ArgumentError('Need $threshold shares, have ${shares.length}.');
    }
    final use = shares.take(threshold).toList();
    final secret = Uint8List(len);
    for (var b = 0; b < len; b++) {
      var acc = 0;
      for (var i = 0; i < use.length; i++) {
        var num = 1, den = 1;
        for (var j = 0; j < use.length; j++) {
          if (i == j) continue;
          num = _mul(num, use[j].index);
          den = _mul(den, use[i].index ^ use[j].index);
        }
        acc ^= _mul(use[i].bytes[b], _mul(num, _inv(den)));
      }
      secret[b] = acc;
    }
    return secret;
  }

  // GF(2^8) with the AES polynomial x^8 + x^4 + x^3 + x + 1.
  static int _mul(int a, int b) {
    var p = 0;
    while (b > 0) {
      if (b & 1 != 0) p ^= a;
      a = (a << 1) ^ ((a & 0x80) != 0 ? 0x11B : 0);
      a &= 0xFF;
      b >>= 1;
    }
    return p;
  }

  static int _inv(int a) {
    if (a == 0) throw ArgumentError('Zero has no inverse.');
    var r = 1;
    for (var i = 0; i < 254; i++) {
      r = _mul(r, a);
    }
    return r;
  }
}
