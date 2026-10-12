import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/lifetrack_ids.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

/// The sample family gets LifeTrack IDs, each asked for as a sample; a
/// normal build never marks anyone as one.
void main() {
  Future<(AppServices, InMemoryIdDirectory)> phone({required bool demo}) async {
    final registry = await Ed25519().newKeyPair();
    final dir = InMemoryIdDirectory();
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 8)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => DateTime(2026, 10, 12, 10),
      demoTools: demo,
      share: ShareConfig(relayUrl: 'http://127.0.0.1:1', registryKey: base64Encode((await registry.extractPublicKey()).bytes)),
      relayOverride: (_) => InMemoryRelay(),
      idDirectoryOverride: () => dir,
    );
    return (s, dir);
  }

  test('all ten in the sample family get an ID, marked as samples', () async {
    final (s, dir) = await phone(demo: true);
    await s.createProfile(name: '', dob: DateTime(1990), sex: Sex.unspecified, demo: true);
    await s.addDemoFamily();
    await s.assignLifeTrackIds();
    expect(s.familyOnPhone().map((p) => s.lifeTrackIdOf(p.id)), everyElement(isNotNull));
    expect(dir.entries.length, 10, reason: 'one ID each');
    expect(dir.entries.values.map((e) => e['sample']), everyElement(isTrue));
  });

  test('a normal build never asks for a sample ID', () async {
    final (s, dir) = await phone(demo: false);
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    await s.assignLifeTrackIds();
    expect(dir.entries.values.map((e) => e['sample']), everyElement(isNull));
  });
}
