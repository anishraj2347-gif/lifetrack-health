import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/crypto/vault_codec.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/http_relay_client.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Backup and restore through the app's real HTTP client and the real server
/// handler, joined in memory: what the server stores is what it would hold.
void main() {
  test('back up, lose the phone, restore on another — over the real HTTP contract', () async {
    final dir = Directory.systemTemp.createTempSync('lt-vault-');
    final handler = LifeTrackApi(
      registry: await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair()),
      relay: RelayStore(),
      vault: VaultStore(dir),
      ids: await IdRegistry.open(),
      adminToken: 'a',
    ).handler;
    final client = MockClient((req) async {
      final res = await handler(shelf.Request(req.method, req.url, body: req.bodyBytes, headers: req.headers));
      return http.Response.bytes(await res.read().expand((c) => c).toList(), res.statusCode, headers: res.headers);
    });
    final remote = HttpRemoteVaultStore(baseUrl: Uri.parse('http://127.0.0.1:8787'), client: client);
    Future<AppServices> phone(int k) => AppServices.open(
          bytes: InMemoryByteStore(),
          deviceKey: SecretKey(List.filled(32, k)),
          remote: remote,
          kdf: KdfParams.weakForTests(),
          cloudFactory: defaultCloud,
          clock: () => DateTime(2026, 10, 1, 10),
        );

    final old = await phone(1);
    await old.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female, demo: true);
    await old.attachments.save('a1', [Uint8List.fromList(List.filled(2000, 7))]);
    await old.addRecord(HealthRecord(id: 'r1', patientId: old.selfPatientId!, kind: RecordKind.report, title: 'HbA1c', date: DateTime(2026, 9, 8), source: RecordSource.smartCapture, attachmentId: 'a1'));
    final kit = await old.setUpBackup();

    // What the server holds: no record title, no name, no password.
    final stored = File('${dir.path}/${kit.account}.json').readAsStringSync();
    for (final secret in ['Anjali', 'HbA1c', 'Lipid', kit.password, kit.password.replaceAll('-', '')]) {
      expect(stored.contains(secret), isFalse, reason: secret);
    }

    final fresh = await phone(2);
    await expectLater(fresh.restoreFromBackup(account: kit.account, password: AppServices.newBackupPassword()), throwsA(isA<VaultAuthenticationFailed>()));
    await fresh.restoreFromBackup(account: kit.account, password: kit.password);
    expect(fresh.selfPatient!.name, 'Anjali Sharma');
    expect(fresh.repository.recordsOf(fresh.selfPatientId!).map((r) => r.id), contains('r1'));
    expect((await fresh.attachments.load('a1')).single.length, 2000);

    // The restored phone keeps the same backup up to date; turning it off deletes it.
    await fresh.backUpNow();
    expect(fresh.lastBackupError, isNull);
    await fresh.turnOffBackup();
    expect(File('${dir.path}/${kit.account}.json').existsSync(), isFalse);
  });
}
