import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../share/reply_identity.dart';
import '../storage/sealed_store.dart';

/// Where LifeTrack IDs are registered: the LifeTrack server in the app
/// (`HttpIdDirectory`), a map in tests.
abstract interface class IdDirectory {
  /// False when [id] is already taken.
  Future<bool> register({required String id, required String mailbox, required List<int> key, required String tokenHash});
  Future<void> move({required String id, required String token, required String mailbox, required List<int> key});
  Future<void> delete({required String id, required String token});
}

class InMemoryIdDirectory implements IdDirectory {
  final Map<String, Map<String, Object?>> entries = {};

  @override
  Future<bool> register({required String id, required String mailbox, required List<int> key, required String tokenHash}) async {
    if (entries.containsKey(id)) return false;
    entries[id] = {'mailbox': mailbox, 'key': key, 'tokenHash': tokenHash};
    return true;
  }

  @override
  Future<void> move({required String id, required String token, required String mailbox, required List<int> key}) async {
    final e = entries[id];
    if (e == null || e['tokenHash'] != await RelayApi.sha256Hex(token)) throw StateError('Not your ID.');
    entries[id] = {...e, 'mailbox': mailbox, 'key': key};
  }

  @override
  Future<void> delete({required String id, required String token}) async {
    final e = entries[id];
    if (e == null) return;
    if (e['tokenHash'] != await RelayApi.sha256Hex(token)) throw StateError('Not your ID.');
    entries.remove(id);
  }
}

/// One LifeTrack ID per profile on this phone, each pointing at that
/// profile's reply mailbox. The ID's token — the only way to move or delete
/// it — is kept sealed here and in the encrypted backup.
class LifeTrackIds {
  LifeTrackIds({required this.sealed, required this.directory, required this.replyIdentity});

  static const _blob = 'lifetrack_ids';

  final SealedStore sealed;
  final IdDirectory directory;
  final Future<ReplyIdentity> Function(String patientId) replyIdentity;

  Map<String, Object?> _ids = {};
  bool _loaded = false;

  Future<void> load() async {
    _ids = ((await sealed.read(_blob) as Map?) ?? {}).cast<String, Object?>();
    _loaded = true;
  }

  Future<void> _save() => sealed.write(_blob, _ids);

  Map<String, Object?>? _of(String patientId) => (_ids[patientId] as Map?)?.cast<String, Object?>();

  /// The profile's ID, once registered; null before that.
  String? idOf(String patientId) {
    assert(_loaded, 'call load() first');
    final e = _of(patientId);
    return e != null && e['registered'] == true ? e['id'] as String : null;
  }

  /// The profile whose ID this is, if it is on this phone.
  String? profileFor(String lifeTrackId) {
    for (final e in _ids.entries) {
      if ((e.value as Map)['id'] == lifeTrackId) return e.key;
    }
    return null;
  }

  /// Registers an ID for [patientId] if it has none. Draws again when the
  /// server says a number is taken; that is what makes it unique.
  Future<String> ensure(String patientId) async {
    final have = _of(patientId);
    if (have != null && have['registered'] == true) return have['id']! as String;
    final me = await replyIdentity(patientId);
    if (have != null) {
      // Came back from a backup: point the same ID at this phone.
      await directory.move(id: have['id']! as String, token: have['token']! as String, mailbox: me.mailbox, key: me.publicKey);
      _ids[patientId] = {...have, 'registered': true};
      await _save();
      return have['id']! as String;
    }
    final token = RelayApi.newToken();
    for (var attempt = 0; attempt < 8; attempt++) {
      final id = LifeTrackId.generate();
      if (await directory.register(id: id, mailbox: me.mailbox, key: me.publicKey, tokenHash: await RelayApi.sha256Hex(token))) {
        _ids[patientId] = {'id': id, 'token': token, 'registered': true};
        await _save();
        return id;
      }
    }
    throw StateError('Could not find a free LifeTrack ID.');
  }

  /// Best effort for every profile; offline is fine, the next call retries.
  Future<void> ensureAll(Iterable<String> patientIds) async {
    for (final p in patientIds) {
      try {
        await ensure(p);
      } on Object {
        // Retried on the next start or "Check for updates".
      }
    }
  }

  Future<void> remove(String patientId) async {
    final e = _of(patientId);
    if (e == null) return;
    try {
      await directory.delete(id: e['id']! as String, token: e['token']! as String);
    } finally {
      _ids.remove(patientId);
      await _save();
    }
  }

  /// For the encrypted backup: IDs and their tokens.
  Map<String, Object?> export() => {
        for (final e in _ids.entries) e.key: {'id': (e.value as Map)['id'], 'token': (e.value as Map)['token']},
      };

  /// From a backup: kept unregistered until [ensure] points them at this
  /// phone's mailboxes.
  Future<void> import(Map<String, Object?> m) async {
    for (final e in m.entries) {
      _ids[e.key] = {...(e.value! as Map).cast<String, Object?>(), 'registered': false};
    }
    await _save();
  }
}
