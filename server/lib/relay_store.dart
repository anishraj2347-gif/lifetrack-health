import 'dart:typed_data';

class RelayItem {
  RelayItem({required this.envelope, required this.expiresAt, required this.withdrawHash});
  final Uint8List envelope;
  final DateTime expiresAt;

  /// SHA-256 of the token the depositor keeps; only they can withdraw.
  final String? withdrawHash;
}

/// Why a deposit was not taken.
class RelayFull implements Exception {
  const RelayFull(this.message);
  final String message;
}

/// Ciphertext in transit. Memory only, on purpose: a restart loses at most
/// undelivered shares, which the patient can send again, and nothing is left
/// on disk to leak. Every item has an expiry of at most 48 hours.
///
/// A deposit never replaces another: items under the same grant id sit side
/// by side, so nobody can swap a waiting share for their own by reusing its
/// id, or block one by depositing first. Size is bounded per mailbox and in
/// total, so the relay cannot be filled until it runs out of memory.
class RelayStore {
  RelayStore({this.maxItemsPerMailbox = 200, this.maxTotalBytes = 512 * 1024 * 1024});

  final int maxItemsPerMailbox;
  final int maxTotalBytes;

  final Map<String, List<(String, RelayItem)>> _boxes = {};
  int _bytes = 0;

  /// Throws [RelayFull] when the mailbox or the relay is full.
  void put(String mailbox, String grantId, RelayItem item) {
    final box = _boxes[mailbox] ??= [];
    if (box.length >= maxItemsPerMailbox) throw const RelayFull('This mailbox is full.');
    if (_bytes + item.envelope.length > maxTotalBytes) throw const RelayFull('The relay is full. Try again later.');
    box.add((grantId, item));
    _bytes += item.envelope.length;
  }

  /// Returns true when an item was removed: the one under [grantId] whose
  /// withdraw hash is [tokenHash].
  bool withdraw(String mailbox, String grantId, String tokenHash) {
    final box = _boxes[mailbox];
    if (box == null) return false;
    final i = box.indexWhere((e) => e.$1 == grantId && e.$2.withdrawHash != null && e.$2.withdrawHash == tokenHash);
    if (i < 0) return false;
    _bytes -= box.removeAt(i).$2.envelope.length;
    if (box.isEmpty) _boxes.remove(mailbox);
    return true;
  }

  /// Pickup: every live item, deleted as it is handed over.
  List<(String grantId, Uint8List envelope)> takeAll(String mailbox, DateTime at) {
    final box = _boxes.remove(mailbox) ?? const [];
    for (final (_, i) in box) {
      _bytes -= i.envelope.length;
    }
    return [for (final (g, i) in box) if (at.isBefore(i.expiresAt)) (g, i.envelope)];
  }

  int purgeExpired(DateTime at) {
    var n = 0;
    for (final box in _boxes.values) {
      box.removeWhere((e) {
        final dead = !at.isBefore(e.$2.expiresAt);
        if (dead) {
          n++;
          _bytes -= e.$2.envelope.length;
        }
        return dead;
      });
    }
    _boxes.removeWhere((_, b) => b.isEmpty);
    return n;
  }

  int countIn(String mailbox) => _boxes[mailbox]?.length ?? 0;
  int get total => _boxes.values.fold(0, (a, b) => a + b.length);
  int get bytes => _bytes;
}
