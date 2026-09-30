import 'dart:typed_data';

class RelayItem {
  RelayItem({required this.envelope, required this.expiresAt, required this.withdrawHash});
  final Uint8List envelope;
  final DateTime expiresAt;

  /// SHA-256 of the token the depositor keeps; only they can withdraw.
  final String? withdrawHash;
}

/// Ciphertext in transit. Memory only, on purpose: a restart loses at most
/// undelivered shares, which the patient can send again, and nothing is left
/// on disk to leak. Every item has an expiry of at most 48 hours.
class RelayStore {
  final Map<String, Map<String, RelayItem>> _boxes = {};

  void put(String mailbox, String grantId, RelayItem item) => (_boxes[mailbox] ??= {})[grantId] = item;

  /// Returns true when an item was removed.
  bool withdraw(String mailbox, String grantId, String tokenHash) {
    final item = _boxes[mailbox]?[grantId];
    if (item == null || item.withdrawHash == null || item.withdrawHash != tokenHash) return false;
    _boxes[mailbox]!.remove(grantId);
    return true;
  }

  /// Pickup: every live item, deleted as it is handed over.
  List<(String grantId, Uint8List envelope)> takeAll(String mailbox, DateTime at) {
    final box = _boxes.remove(mailbox) ?? {};
    return [for (final MapEntry(key: g, value: i) in box.entries) if (at.isBefore(i.expiresAt)) (g, i.envelope)];
  }

  int purgeExpired(DateTime at) {
    var n = 0;
    for (final box in _boxes.values) {
      final dead = [for (final MapEntry(:key, :value) in box.entries) if (!at.isBefore(value.expiresAt)) key];
      n += dead.length;
      dead.forEach(box.remove);
    }
    _boxes.removeWhere((_, b) => b.isEmpty);
    return n;
  }

  int countIn(String mailbox) => _boxes[mailbox]?.length ?? 0;
  int get total => _boxes.values.fold(0, (a, b) => a + b.length);
}
