import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/identity/identity_verifier.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/http_relay_client.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/identity.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Onboarding with DigiLocker, through the app's real client and the real
/// server, with the practice DigiLocker standing in and the browser step
/// done by following the page's own link.
void main() {
  test('verify with Aadhaar, create the profile, add a newborn from the birth certificate; a second phone is refused', () async {
    final key = await Ed25519().newKeyPair();
    final trust = RegistryTrust([await key.extractPublicKey()]);
    final handler = LifeTrackApi(
      registry: await DoctorRegistry.open(signingKey: key),
      relay: RelayStore(),
      vault: VaultStore(Directory.systemTemp.createTempSync('lt-v-')),
      ids: await IdRegistry.open(),
      adminToken: 'a',
      identity: IdentityService(provider: PracticeDigiLocker(), registryKey: key, hmacSecret: List.filled(32, 3), trust: trust),
      requireIdentity: true,
    ).handler;
    final client = MockClient((req) async {
      final res = await handler(shelf.Request(req.method, req.url, body: req.bodyBytes, headers: req.headers));
      return http.Response.bytes(await res.read().expand((c) => c).toList(), res.statusCode, headers: res.headers);
    });
    final base = Uri.parse('http://127.0.0.1:8787');
    final registryKey = (await registryKeyOf(client, base));

    Future<AppServices> phone(int k) => AppServices.open(
          bytes: InMemoryByteStore(),
          deviceKey: SecretKey(List.filled(32, k)),
          remote: InMemoryRemoteVaultStore(),
          kdf: KdfParams.weakForTests(),
          cloudFactory: defaultCloud,
          share: ShareConfig(relayUrl: '$base', registryKey: registryKey),
          relayOverride: (t) => HttpRelayClient(baseUrl: base, tokens: t, client: client),
          idDirectoryOverride: () => HttpIdDirectory(baseUrl: base, client: client),
          verifierOverride: () => HttpIdentityVerifier(baseUrl: base, client: client),
          identityRequired: true,
        );

    /// The person in the browser picks [account] on the practice page, then
    /// reads the hand-back code off the page that ends the sign-in.
    String? shown;
    Future<void> Function(Uri) browserPicks(String account) => (url) async {
          final page = (await client.get(url)).body;
          final link = RegExp('href="([^"]*account=$account)"').firstMatch(page)!.group(1)!.replaceAll('&amp;', '&');
          final approve = await client.send(http.Request('GET', base.resolve(link))..followRedirects = false);
          final done = (await client.get(Uri.parse(approve.headers['location']!))).body;
          shown = RegExp(r'[0-9A-Z]{4}-[0-9A-Z]{4}').firstMatch(done)?.group(0);
        };
    Future<String?> typesShownCode(bool _) async => shown;

    final s = await phone(1);
    final me = await s.verifyWithDigiLocker(purpose: 'self', openUrl: browserPicks('anjali'), askCode: typesShownCode);
    final p = await s.createProfile(name: '', dob: DateTime(2000), sex: Sex.unspecified, verification: me);
    expect((p.name, p.sex, p.isVerified), ('Anjali Sharma', Sex.female, true));
    expect(s.lifeTrackIdOf(p.id), isNotNull);

    final baby = await s.addChild(
      name: '', dob: DateTime(2000), sex: Sex.unspecified, relation: 'son',
      verification: await s.verifyWithDigiLocker(purpose: 'newborn', openUrl: browserPicks('anjali'), askCode: typesShownCode),
    );
    expect(baby.name, 'Baby of Anjali Sharma');
    expect(s.custodyOf(baby.id)!.isVerified, isTrue);

    await expectLater(s.verifyWithDigiLocker(purpose: 'self', openUrl: browserPicks('noaadhaar'), askCode: typesShownCode), throwsA(isA<VerificationFailed>()));

    final other = await phone(2);
    final again = await other.verifyWithDigiLocker(purpose: 'self', openUrl: browserPicks('anjali'), askCode: typesShownCode);
    await expectLater(other.createProfile(name: '', dob: DateTime(2000), sex: Sex.unspecified, verification: again), throwsA(isA<PersonExists>()));
    expect(other.currentPatient, isNull);
  });
}

Future<String> registryKeyOf(http.Client c, Uri base) async {
  final r = await c.get(base.resolve('/v1/registry/key'));
  return RegExp('"publicKey":"([^"]+)"').firstMatch(r.body)!.group(1)!;
}
