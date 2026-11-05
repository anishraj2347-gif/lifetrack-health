import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../share/reply_identity.dart';
import 'identity_verifier.dart';
import '../storage/sealed_store.dart';

/// Where LifeTrack IDs are registered: the LifeTrack server in the app
/// (`HttpIdDirectory`), a map in tests.
abstract interface class IdDirectory {
  /// False when [id] is already taken. Throws [PersonExists] when the
  /// verified person in [attestation] already has a LifeTrack ID. [sample]
  /// marks a demonstration build's made-up person, which a server in
  /// practice mode accepts without an identity check and records as such.
  Future<bool> register({required String id, required String mailbox, required List<int> key, required String tokenHash, IdentityAttestation? attestation, bool sample = false});
  Future<void> move({required String id, required String token, required String mailbox, required List<int> key});

  /// Throws [IdNotYours] when the token no longer matches.
  Future<void> delete({required String id, required String token});

  /// Points the ID of the person in [attestation] at this phone under a new
  /// token, and returns it. The service picks the ID from the attestation.
  /// Throws [ReclaimRefused] for a check that is too old, or no such ID.
  Future<String> reclaim({required String mailbox, required List<int> key, required String tokenHash, required IdentityAttestation attestation});
}

class InMemoryIdDirectory implements IdDirectory {
  final Map<String, Map<String, Object?>> entries = {};

  @override
  Future<bool> register({required String id, required String mailbox, required List<int> key, required String tokenHash, IdentityAttestation? attestation, bool sample = false}) async {
    if (entries.containsKey(id)) return false;
    final subject = attestation?.subjectHash;
    if (subject != null && entries.values.any((e) => e['subject'] == subject)) throw const PersonExists();
    entries[id] = {'mailbox': mailbox, 'key': key, 'tokenHash': tokenHash, 'subject': ?subject, if (sample) 'sample': true, 'since': ?attestation?.verifiedAt};
    return true;
  }

  @override
  Future<String> reclaim({required String mailbox, required List<int> key, required String tokenHash, required IdentityAttestation attestation}) async {
    final found = entries.entries.where((e) => e.value['subject'] == attestation.subjectHash).firstOrNull;
    if (found == null) throw const ReclaimRefused('This person has no LifeTrack ID.');
    if (!attestation.verifiedAt.isAfter(found.value['since']! as DateTime)) throw const ReclaimRefused('That identity check is too old to move an ID.');
    entries[found.key] = {...found.value, 'mailbox': mailbox, 'key': key, 'tokenHash': tokenHash, 'since': attestation.verifiedAt};
    return found.key;
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
    if (e['tokenHash'] != await RelayApi.sha256Hex(token)) throw const IdNotYours();
    entries.remove(id);
  }
}

/// One LifeTrack ID per profile on this phone, each pointing at that
/// profile's reply mailbox. The ID's token — the only way to move or delete
/// it — is kept sealed here and in the encrypted backup.
class LifeTrackIds {
  LifeTrackIds({required this.sealed, required this.directory, required this.replyIdentity, this.attestationOf, this.isSample});

  static const _blob = 'lifetrack_ids';

  final SealedStore sealed;
  final IdDirectory directory;
  final Future<ReplyIdentity> Function(String patientId) replyIdentity;

  /// The profile's DigiLocker verification, sent at registration so the
  /// service can give one person one ID.
  final IdentityAttestation? Function(String patientId)? attestationOf;

  /// True for a demonstration build's made-up person (see [IdDirectory.register]).
  final bool Function(String patientId)? isSample;

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
    return e != null && e['registered'] == true && e['erasing'] != true ? e['id'] as String : null;
  }

  /// The profile whose ID this is, if it is on this phone.
  String? profileFor(String lifeTrackId) {
    for (final e in _ids.entries) {
      if ((e.value as Map)['id'] == lifeTrackId && (e.value as Map)['erasing'] != true) return e.key;
    }
    return null;
  }

  /// Registrations under way, so two at once for the same person (app start
  /// and a profile just added) share one instead of registering two IDs.
  final Map<String, Future<String>> _inFlight = {};

  /// Registers an ID for [patientId] if it has none. Draws again when the
  /// server says a number is taken; that is what makes it unique.
  ///
  /// With [moveExisting], a person who already has an ID takes it over with
  /// the identity check on this profile; a human chose that, because it stops
  /// the ID reaching any other phone that holds it.
  Future<String> ensure(String patientId, {bool moveExisting = false}) => _inFlight[patientId] ??= _ensure(patientId, moveExisting).whenComplete(() {
        // A block, not `=>`: whenComplete waits on a returned future, and
        // remove() returns this very one.
        _inFlight.remove(patientId);
      });

  Future<String> _ensure(String patientId, bool moveExisting) async {
    await retryRemovals(); // an ID erased offline may be this very person's
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
    final tokenHash = await RelayApi.sha256Hex(token);
    final attestation = attestationOf?.call(patientId);
    for (var attempt = 0; attempt < 8; attempt++) {
      final id = LifeTrackId.generate();
      try {
        if (await directory.register(id: id, mailbox: me.mailbox, key: me.publicKey, tokenHash: tokenHash, attestation: attestation, sample: isSample?.call(patientId) ?? false)) {
          _ids[patientId] = {'id': id, 'token': token, 'registered': true};
          await _save();
          return id;
        }
      } on PersonExists {
        if (!moveExisting || attestation == null) rethrow;
        final mine = await directory.reclaim(mailbox: me.mailbox, key: me.publicKey, tokenHash: tokenHash, attestation: attestation);
        _ids[patientId] = {'id': mine, 'token': token, 'registered': true};
        await _save();
        return mine;
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
        // Retried on the next start or "Check for prescriptions and updates".
      }
    }
  }

  /// Deletes the ID from the service. The token stays until the service has
  /// said so: it is the only way to delete it. Offline this throws, and
  /// [retryRemovals] finishes the job.
  Future<void> remove(String patientId) async {
    final e = _of(patientId);
    if (e == null) return;
    _ids[patientId] = {...e, 'erasing': true};
    await _save();
    await _removeNow(patientId);
  }

  Future<void> _removeNow(String patientId) async {
    final e = _of(patientId);
    if (e == null) return;
    try {
      await directory.delete(id: e['id']! as String, token: e['token']! as String);
    } on IdNotYours {
      // Moved to another phone since: it is no longer this phone's to delete.
    }
    _ids.remove(patientId);
    await _save();
  }

  /// Tries every deletion still waiting; returns how many still wait.
  Future<int> retryRemovals() async {
    var left = 0;
    for (final p in [for (final e in _ids.entries) if ((e.value as Map)['erasing'] == true) e.key]) {
      try {
        await _removeNow(p);
      } on Object {
        left++;
      }
    }
    return left;
  }

  /// For the encrypted backup: IDs and their tokens.
  Map<String, Object?> export() => {
        for (final e in _ids.entries)
          if ((e.value as Map)['erasing'] != true) e.key: {'id': (e.value as Map)['id'], 'token': (e.value as Map)['token']},
      };

  /// Drops IDs that came from a backup and were never pointed at this phone.
  Future<void> forgetImported() async {
    _ids.removeWhere((_, e) => (e as Map)['registered'] != true);
    await _save();
  }

  /// From a backup: kept unregistered until [ensure] points them at this
  /// phone's mailboxes.
  Future<void> import(Map<String, Object?> m) async {
    for (final e in m.entries) {
      _ids[e.key] = {...(e.value! as Map).cast<String, Object?>(), 'registered': false};
    }
    await _save();
  }
}
