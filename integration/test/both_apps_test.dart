import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/http_relay_client.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';
import 'package:lifetrack_doctor/session.dart';
import 'package:lifetrack_doctor/store/memory_cipher.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;

/// The patient app's and the doctor app's own code, talking through the
/// real server handler — every step the two apps share, in the order a
/// clinic visit uses them. Nothing here imitates either app.
void main() {
  const admin = 'admin-token';
  final base = Uri.parse('http://127.0.0.1:8787');
  late http.Client client;
  late AppServices patient;
  late DoctorSession doctor;
  late String patientId;

  Future<http.Response> adminPost(String path) => client.post(base.resolve(path), headers: {RelayApi.hAdmin: admin});

  setUp(() async {
    final handler = LifeTrackApi(
      registry: await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair()),
      relay: RelayStore(),
      vault: VaultStore(Directory.systemTemp.createTempSync('lt-both-')),
      ids: await IdRegistry.open(),
      adminToken: admin,
    ).handler;
    client = MockClient((req) async {
      final res = await handler(shelf.Request(req.method, req.url, body: req.bodyBytes, headers: req.headers));
      return http.Response.bytes(await res.read().expand((c) => c).toList(), res.statusCode, headers: res.headers);
    });

    // The patient's phone, with the registry key pinned as a build would.
    final registryKey = await registryKeyOf(client, base);
    patient = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 4)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      share: ShareConfig(relayUrl: '$base', registryKey: registryKey),
      relayOverride: (t) => HttpRelayClient(baseUrl: base, tokens: t, client: client),
      idDirectoryOverride: () => HttpIdDirectory(baseUrl: base, client: client),
      doctorStatusOverride: () => HttpDoctorStatus(baseUrl: base, client: client),
    );
    patientId = (await patient.createProfile(name: 'Meera Iyer', dob: DateTime(1972, 3, 4), sex: Sex.female, demo: true)).id;
    await patient.assignLifeTrackIds();

    // The doctor's phone: enrols, then the registry approves after the
    // licence check.
    SharedPreferences.setMockInitialValues({});
    doctor = await DoctorSession.load(base, cipher: MemoryCipher(), client: client);
    await doctor.enrol(name: 'Dr. Kavya Menon', speciality: 'General Medicine', council: 'Delhi Medical Council', registrationNo: 'DMC-24680');
    expect(doctor.state, EnrolmentState.pending);
  });

  Future<void> approveDoctor() async {
    expect((await adminPost('/v1/admin/doctors/DMC-24680/approve')).statusCode, 200);
    await doctor.refreshStatus();
    expect(doctor.state, EnrolmentState.approved);
  }

  test('a pending doctor has no code a patient can scan', () async {
    expect(doctor.certificateQr, isNull);
    await doctor.refreshStatus();
    expect(doctor.state, EnrolmentState.pending);
  });

  test('scan, share, open as confirmed, prescribe, collect as signed', () async {
    await approveDoctor();
    final id = patient.lifeTrackIdOf(patientId);
    expect(id, isNotNull, reason: 'the profile has a LifeTrack ID registered with the server');

    // The patient scans the doctor's QR and shares the Summary.
    final cert = await patient.sharing!.scan(doctor.certificateQr!, DateTime.now());
    expect((cert.name, cert.registrationNo), ('Dr. Kavya Menon', 'DMC-24680'));
    final receipt = await patient.sharing!.share(
      patientId: patientId,
      doctor: cert,
      levels: {AccessLevel.summary},
      grantorId: patient.actingGrantor(),
      at: DateTime.now(),
    );

    // The doctor's app picks it up and files it under the patient's ID.
    expect(await doctor.pickUp(), 1);
    final sh = doctor.inbox.single;
    expect(sh.verified, isTrue, reason: 'sender proof and registry agree');
    expect(sh.lifeTrackId, id);
    final name = patient.repository.patient(patientId)!.name;
    expect(sh.patientName, name);
    expect((sh.bundle['latestTests'] as List?) ?? const [], isNotEmpty, reason: 'the summary carries the sample results');
    expect(doctor.patients.single.key, id);

    // The doctor writes a prescription; it reaches the patient's records signed.
    await doctor.sendPrescription(
      sh,
      SignedPrescription(
        patientId: (sh.bundle['patientRef'] as String?) ?? '',
        doctorRegistryId: doctor.registrationNo,
        doctorName: 'Dr. Kavya Menon',
        qualification: 'MBBS, MD',
        registrationNo: doctor.registrationNo,
        medicine: 'Metformin 500 mg',
        ingredient: 'metformin',
        morning: 1,
        afternoon: 0,
        night: 1,
        days: 30,
        issuedAt: DateTime.now().toUtc(),
        timing: 'after_food',
      ),
    );
    final (added, _, refused) = await patient.checkInbox();
    expect((added, refused), (1, 0));
    final rx = patient.repository.recordsOf(patientId).where((r) => r.title.contains('Metformin 500 mg') && r.provenance == Provenance.signed);
    expect(rx, hasLength(1));
    expect(doctor.prescriptions.single.patientKey, id);

    // The patient ends access; the doctor's copy closes on the next pickup.
    await patient.sharing!.endAccess(receipt.grant, DateTime.now());
    await doctor.pickUp();
    expect(doctor.inbox, isEmpty);
    expect(doctor.closedByPatient, [name]);
    expect(doctor.patients.single.name, name, reason: 'the register keeps who they saw');
  });

  test('the doctor asks by LifeTrack ID; the patient approves once and declines once', () async {
    await approveDoctor();
    final id = patient.lifeTrackIdOf(patientId)!;

    await doctor.requestAccess(lifeTrackId: id, levels: ['summary', 'familyIllnesses'], note: 'Diabetes follow-up');
    await patient.checkInbox();
    final pending = await patient.pendingRequests();
    expect(pending, hasLength(1));
    expect(pending.single.doctor.registrationNo, 'DMC-24680');
    expect(pending.single.levels, {AccessLevel.summary, AccessLevel.familyIllnesses});

    // Approved at a lower level than asked.
    await patient.sharing!.share(
      patientId: patientId,
      doctor: pending.single.doctor,
      levels: {AccessLevel.summary},
      requested: pending.single.levels,
      grantorId: patient.actingGrantor(),
      at: DateTime.now(),
    );
    await patient.requests!.remove(pending.single.request.requestId);
    expect(await doctor.pickUp(), 1);
    expect(doctor.inbox.single.lifeTrackId, id);
    expect(doctor.inbox.single.bundle['withheld'], isNotEmpty, reason: 'the doctor is told what was not shared');

    // A second request is declined; the doctor sees it.
    await doctor.requestAccess(lifeTrackId: id, levels: ['allReports']);
    await patient.checkInbox();
    await patient.declineRequest((await patient.pendingRequests()).single);
    await doctor.pickUp();
    expect(doctor.sent.first.declined, isTrue);
  });

  test('a revoked doctor is refused by the patient app and stops being approved in the doctor app', () async {
    await approveDoctor();
    final qr = doctor.certificateQr!;
    expect((await adminPost('/v1/admin/doctors/DMC-24680/revoke')).statusCode, 200);

    await expectLater(patient.sharing!.scan(qr, DateTime.now()), throwsA(isA<CertificateRejected>()));
    await doctor.refreshStatus();
    expect(doctor.state, EnrolmentState.revoked);
    expect(doctor.certificateQr, isNull);
  });
}

Future<String> registryKeyOf(http.Client c, Uri base) async =>
    (jsonDecode((await c.get(base.resolve('/v1/registry/key'))).body) as Map)['publicKey']! as String;
