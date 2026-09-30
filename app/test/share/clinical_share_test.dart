import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/demo_data.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/consent/consent_store.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/consent/record_access.dart';
import 'package:lifetrack/src/model/clinical_profile.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/share/clinical_share_service.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/share/reply_identity.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/storage/record_repository.dart';
import 'package:lifetrack/src/storage/sealed_store.dart';

/// A doctor device as the future doctor app would hold it.
class Doctor {
  Doctor(this.enc, this.sign, this.qr);
  final SimpleKeyPair enc;
  final SimpleKeyPair sign;
  final String qr;
}

void main() {
  final now = DateTime(2026, 9, 30, 11, 30);
  late SimpleKeyPair registry;
  late RegistryTrust trust;
  late ConsentStore consent;
  late InMemoryAuditLog audit;
  late RecordRepository repo;
  late InMemoryRelay relay;
  late ClinicalShareService service;
  late ReplyIdentity me;

  Future<Doctor> doctor({String id = 'DMC-12345', DateTime? expires, SimpleKeyPair? signer}) async {
    final enc = await X25519().newKeyPair();
    final sign = await Ed25519().newKeyPair();
    final unsigned = DoctorCertificate(
      registryId: id,
      name: 'Dr. R. Mehta',
      speciality: 'Cardiology',
      council: 'Delhi Medical Council',
      registrationNo: id,
      encryptionKey: (await enc.extractPublicKey()).bytes,
      signingKey: (await sign.extractPublicKey()).bytes,
      issuedAt: DateTime(2026, 1, 1),
      expiresAt: expires ?? DateTime(2027, 1, 1),
      signature: const [],
    );
    final sig = await Ed25519().sign(unsigned.signedBytes, keyPair: signer ?? registry);
    final cert = DoctorCertificate(
      registryId: unsigned.registryId,
      name: unsigned.name,
      speciality: unsigned.speciality,
      council: unsigned.council,
      registrationNo: unsigned.registrationNo,
      encryptionKey: unsigned.encryptionKey,
      signingKey: unsigned.signingKey,
      issuedAt: unsigned.issuedAt,
      expiresAt: unsigned.expiresAt,
      signature: sig.bytes,
    );
    return Doctor(enc, sign, cert.encode());
  }

  Future<Map<String, Object?>> pickUpAndOpen(Doctor d, {DateTime? at}) async {
    final cert = DoctorCertificate.decode(d.qr);
    final envs = relay.pickUp(await RelayApi.doctorMailbox(cert.encryptionKey), at ?? now);
    expect(envs, hasLength(1));
    return ShareEnvelope.open(envs.single, d.enc, at ?? now);
  }

  setUp(() async {
    registry = await Ed25519().newKeyPair();
    trust = RegistryTrust([await registry.extractPublicKey()]);
    consent = ConsentStore();
    audit = InMemoryAuditLog();
    repo = await RecordRepository.open(SealedStore(InMemoryByteStore(), SecretKey(List.filled(32, 4))));
    await repo.savePatient(DemoData.patient('p1'));
    await repo.addAll(DemoData.records('p1'));
    await repo.add(HealthRecord(id: 'note1', patientId: 'p1', kind: RecordKind.note, title: 'Private worry', date: now, source: RecordSource.typedByPatient));
    await repo.saveProfile(
      'p1',
      ClinicalProfile(
        allergies: const [Allergy(substance: 'Penicillin', reaction: 'rash')],
        conditions: const [Condition(name: 'Type 2 diabetes', sinceYear: 2021)],
        familyIllnesses: const [FamilyIllness(relation: Relation.father, condition: 'Heart attack', ageAtOnset: 58)],
        updatedAt: DateTime(2026, 9, 28),
      ),
    );
    relay = InMemoryRelay();
    me = await ReplyIdentity.create();
    service = ClinicalShareService(
      replyIdentity: (_) async => me,
      trust: trust,
      consent: consent,
      access: RecordAccess(consent: consent, audit: audit, repository: repo),
      audit: audit,
      repository: repo,
      relay: relay,
    );
  });

  group('doctor certificate', () {
    test('a registry-signed code verifies', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      expect(cert.name, 'Dr. R. Mehta');
    });

    test('with no registry configured, every doctor is refused', () async {
      final d = await doctor();
      await expectLater(const RegistryTrust.none().verify(d.qr, now),
          throwsA(isA<CertificateRejected>().having((e) => e.problem, 'problem', CertificateProblem.untrustedRegistry)));
    });

    test('a code signed by anyone else is refused', () async {
      final d = await doctor(signer: await Ed25519().newKeyPair());
      await expectLater(service.scan(d.qr, now), throwsA(isA<CertificateRejected>().having((e) => e.problem, 'problem', CertificateProblem.badSignature)));
    });

    test('an expired verification is refused', () async {
      final d = await doctor(expires: DateTime(2026, 6, 1));
      await expectLater(service.scan(d.qr, now), throwsA(isA<CertificateRejected>().having((e) => e.problem, 'problem', CertificateProblem.expired)));
    });

    test('a tampered name breaks the signature', () async {
      final d = await doctor();
      final j = jsonDecode(utf8.decode(base64Url.decode(d.qr))) as Map;
      j['name'] = 'Dr. Someone Else';
      final forged = base64Url.encode(utf8.encode(jsonEncode(j)));
      await expectLater(service.scan(forged, now), throwsA(isA<CertificateRejected>()));
    });
  });

  group('sharing the Summary', () {
    test('only the chosen doctor device can open it, and it reads in the right order', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      final b = await pickUpAndOpen(d);
      expect((b['allergies']! as List).single, containsPair('substance', 'Penicillin'));
      final meds = b['medicines']! as Map;
      expect([for (final m in meds['active']! as List) (m as Map)['title']], ['Metformin 500 mg']);
      expect([for (final m in meds['endedRecently']! as List) (m as Map)['title']], ['Glycomet 500 SR']);
      final tests = b['latestTests']! as List;
      final hba1c = tests.firstWhere((t) => (t as Map)['analyte'] == 'hba1c') as Map;
      expect(hba1c['lab'], 'Thyrocare');
      expect(hba1c['ageDays'], 22);
      expect(hba1c['source'], 'photoOfReport');
      expect((hba1c['previous']! as Map)['value'], 6.4);
      final creat = tests.firstWhere((t) => (t as Map)['analyte'] == 'creatinine') as Map;
      expect(creat['source'], 'patientTyped');
      expect(b.containsKey('familyIllnesses'), isFalse, reason: 'not in the Summary level');
      expect(b.containsKey('documents'), isFalse);
    });

    test('a different device key cannot open it', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final env = relay.pickUp(await RelayApi.doctorMailbox(DoctorCertificate.decode(d.qr).encryptionKey), now).single;
      await expectLater(ShareEnvelope.open(env, await X25519().newKeyPair(), now), throwsA(anything));
    });

    test('the bundle never states a judgement about a value', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary, AccessLevel.allReports}, at: now);
      final text = jsonEncode(await pickUpAndOpen(d)).toLowerCase();
      for (final w in ['valid', 'expired', 'normal', 'abnormal', 'reusable']) {
        expect(text.contains(w), isFalse, reason: w);
      }
    });

    test('personal notes are never shared, at any level', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: AccessLevel.values.toSet(), at: now);
      expect(jsonEncode(await pickUpAndOpen(d)).contains('Private worry'), isFalse);
    });

    test('granting less than asked tells the doctor what was withheld, not what it holds', () async {
      final d = await doctor();
      final r = await service.share(
        patientId: 'p1',
        doctor: await service.scan(d.qr, now),
        levels: {AccessLevel.summary},
        requested: {AccessLevel.allReports},
        at: now,
      );
      expect(r.withheld, {DataClass.scans});
      final b = await pickUpAndOpen(d);
      expect(b['withheld'], ['scans']);
      expect(jsonEncode(b).contains('Chest X-ray'), isFalse);
    });

    test('family illnesses are marked patient-reported', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.familyIllnesses}, at: now);
      final fam = (await pickUpAndOpen(d))['familyIllnesses']! as Map;
      expect(fam['reportedBy'], 'patient');
      expect((fam['items']! as List).single, containsPair('onset', 58));
    });

    test('a date and test filter narrows All my reports', () async {
      final d = await doctor();
      await service.share(
        patientId: 'p1',
        doctor: await service.scan(d.qr, now),
        levels: {AccessLevel.allReports},
        filter: RecordFilter(from: DateTime(2026, 6, 1), analytes: const {'hba1c'}),
        at: now,
      );
      final b = await pickUpAndOpen(d);
      expect([for (final t in b['latestTests']! as List) (t as Map)['analyte']], ['hba1c']);
      expect([for (final doc in b['documents']! as List) (doc as Map)['title']], ['HbA1c']);
    });

    test('every part is audited, and the share is logged before it leaves', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      final log = audit.entriesFor('p1').reversed.toList();
      expect(log.first.action, AuditAction.grantIssued);
      expect(log.last.action, AuditAction.clinicalShare);
      final views = log.where((e) => e.action == AuditAction.view);
      expect(views.map((e) => e.actorId).toSet(), {'doctor:DMC-12345'});
      expect(views.map((e) => e.dataClass).toSet(), {DataClass.allergies, DataClass.conditions, DataClass.prescriptions, DataClass.reports});
    });

    test('a visit grant is a session of at most 4 hours, bound to the device key', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final r = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      expect(r.grant.type, GrantType.session);
      expect(r.grant.expiresAt.difference(now), const Duration(hours: 4));
      expect(r.grant.granteeKeyId, await cert.keyId());
      await expectLater(pickUpAndOpen(d, at: now.add(const Duration(hours: 5))), throwsA(anything));
    });
  });

  group('changing and ending access', () {
    test('moving from Summary to All my reports replaces the grant instead of throwing', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final first = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      final second = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.allReports}, at: now.add(const Duration(minutes: 5)));
      final live = consent.activeGrantsFor('p1', now.add(const Duration(minutes: 6)));
      expect(live.map((g) => g.id), [second.grant.id]);
      expect(live.single.id, isNot(first.grant.id));
      expect(relay.pending(await RelayApi.doctorMailbox(cert.encryptionKey)), 1, reason: 'the first, undelivered share was withdrawn');
    });

    test('ending access removes a share the doctor has not picked up', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final r = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      await service.endAccess(r.grant, now.add(const Duration(minutes: 1)));
      expect(relay.pending(await RelayApi.doctorMailbox(cert.encryptionKey)), 0);
      expect(consent.activeGrantsFor('p1', now), isEmpty);
    });

    test('a relay cannot re-address a share to another grant', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final env = relay.pickUp(await RelayApi.doctorMailbox(DoctorCertificate.decode(d.qr).encryptionKey), now).single;
      final j = jsonDecode(utf8.decode(env)) as Map;
      j['gid'] = 'grant-someone-else';
      await expectLater(ShareEnvelope.open(Uint8List.fromList(utf8.encode(jsonEncode(j))), d.enc, now), throwsA(anything));
    });
  });

  group('prescription back to the patient', () {
    Future<SignedPrescription> write(Doctor d, {String patient = 'p1'}) => SignedPrescription(
          patientId: patient,
          doctorRegistryId: 'DMC-12345',
          doctorName: 'Dr. R. Mehta',
          qualification: 'MD (Medicine)',
          registrationNo: 'DMC-12345',
          medicine: 'Atorvastatin 10 mg',
          ingredient: 'atorvastatin',
          morning: 0,
          afternoon: 0,
          night: 1,
          days: 90,
          issuedAt: now.add(const Duration(minutes: 20)),
        ).signedWith(d.sign);

    test('a signed prescription from a doctor the patient just shared with is added as signed', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final rec = await service.acceptPrescription(patientId: 'p1', rx: await write(d), doctorCertificateQr: d.qr, at: now.add(const Duration(minutes: 21)));
      expect(rec.provenance, Provenance.signed);
      expect(rec.isActiveAt(now.add(const Duration(days: 30))), isTrue);
      expect(rec.prescriberRegistration, 'DMC-12345');
      expect(audit.entriesFor('p1').first.action, AuditAction.prescriptionReceived);
    });

    test('it still arrives after the visit ended and the app restarted', () async {
      final d = await doctor();
      final r = await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      await service.endAccess(r.grant, now.add(const Duration(minutes: 10)));
      consent.evictFinished(now.add(const Duration(hours: 1)));
      await service.acceptPrescription(patientId: 'p1', rx: await write(d), doctorCertificateQr: d.qr, at: now.add(const Duration(hours: 1)));
    });

    test('refused without a recent share, with a forged signature, or for another patient', () async {
      final d = await doctor();
      await expectLater(
        service.acceptPrescription(patientId: 'p1', rx: await write(d), doctorCertificateQr: d.qr, at: now),
        throwsA(isA<PrescriptionRejected>()),
      );
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final imposter = await doctor();
      await expectLater(
        service.acceptPrescription(patientId: 'p1', rx: await write(imposter), doctorCertificateQr: d.qr, at: now),
        throwsA(isA<PrescriptionRejected>()),
      );
      await expectLater(
        service.acceptPrescription(patientId: 'p1', rx: await write(d, patient: 'p2'), doctorCertificateQr: d.qr, at: now),
        throwsA(isA<PrescriptionRejected>()),
      );
    });
  });

  group('the full round trip over the relay', () {
    test('patient shares, doctor replies with a sealed signed prescription, patient collects it', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final bundle = await pickUpAndOpen(d);
      final replyTo = (bundle['replyTo']! as Map).cast<String, Object?>();

      final rx = await SignedPrescription(
        patientId: 'p1',
        doctorRegistryId: 'DMC-12345',
        doctorName: 'Dr. R. Mehta',
        qualification: 'MD (Medicine)',
        registrationNo: 'DMC-12345',
        medicine: 'Atorvastatin 10 mg',
        ingredient: 'atorvastatin',
        morning: 0,
        afternoon: 0,
        night: 1,
        days: 90,
        issuedAt: now.add(const Duration(minutes: 20)),
        note: 'Repeat lipid panel in 3 months',
        timing: 'after_food',
      ).signedWith(d.sign);
      final replyKey = base64Decode(replyTo['key']! as String);
      final sealed = await ShareEnvelope.seal(
        bundle: {'prescription': rx.toJson(), 'certificate': d.qr},
        recipientKey: replyKey,
        keyId: await RelayApi.keyId(replyKey),
        grantId: 'rx-1',
        expiresAt: now.add(const Duration(hours: 48)),
      );
      await relay.deposit(mailbox: replyTo['mailbox']! as String, grantId: 'rx-1', envelope: sealed, expiresAt: now.add(const Duration(hours: 48)));

      final (added, refused) = await service.collectPrescriptions('p1', now.add(const Duration(minutes: 30)));
      expect(refused, 0);
      expect(added.single.title, 'Atorvastatin 10 mg');
      expect(added.single.instructions, 'Repeat lipid panel in 3 months');
      expect(added.single.timing, 'after_food');
      expect(added.single.prescriberRegistration, 'DMC-12345');
      expect(added.single.endDate!.difference(added.single.date).inDays, 90);
      final reloaded = repo.recordsOf('p1').firstWhere((r) => r.title == 'Atorvastatin 10 mg');
      expect(reloaded.instructions, 'Repeat lipid panel in 3 months', reason: 'survives storage');
      expect(repo.recordsOf('p1').any((r) => r.title == 'Atorvastatin 10 mg' && r.provenance == Provenance.signed), isTrue);
    });

    test('a tampered or unreadable reply is refused and logged, never silently dropped', () async {
      final d = await doctor();
      await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      await relay.deposit(mailbox: me.mailbox, grantId: 'junk', envelope: Uint8List.fromList(utf8.encode('{"v":1}')), expiresAt: now.add(const Duration(hours: 1)));
      final (added, refused) = await service.collectPrescriptions('p1', now);
      expect(added, isEmpty);
      expect(refused, 1);
      expect(audit.entriesFor('p1').first.action, AuditAction.denied);
    });
  });
}
