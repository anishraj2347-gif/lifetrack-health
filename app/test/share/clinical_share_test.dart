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
import 'package:lifetrack/src/model/vital_reading.dart';
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
      lifeTrackIdOf: (pid) => pid == 'p1' ? '148209375516' : null,
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

    test('the share carries the patient\'s LifeTrack ID, so the doctor can ask again later', () async {
      final d = await doctor();
      final r = await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final b = await pickUpAndOpen(d);
      expect((b['patient']! as Map)['lifeTrackId'], '148209375516');
      // …and proves it came from the phone holding the reply key, which the
      // doctor app needs before filing it under that ID.
      final replyKey = base64Decode((b['replyTo']! as Map)['key']! as String);
      final proof = b['senderProof']! as String;
      expect(await SenderProof.check(doctorKeyPair: d.enc, replyKey: replyKey, grantId: r.grant.id, lifeTrackId: '148209375516', proof: proof), isTrue);
      expect(await SenderProof.check(doctorKeyPair: d.enc, replyKey: replyKey, grantId: r.grant.id, lifeTrackId: '148209375524', proof: proof), isFalse);
    });

    test('with a test filter, prescriptions and scans from the same months stay home', () async {
      final d = await doctor();
      await service.share(
        patientId: 'p1',
        doctor: await service.scan(d.qr, now),
        levels: {AccessLevel.allReports},
        filter: RecordFilter(from: DateTime(2026, 1, 1), analytes: const {'hba1c'}),
        at: now,
      );
      final b = await pickUpAndOpen(d);
      // Metformin (March) and the chest X-ray (January) fall in the dates but carry no HbA1c.
      expect([for (final doc in b['documents']! as List) (doc as Map)['title']], ['HbA1c', 'HbA1c']);
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

    test('a visit grant is a session of 1 hour unless the patient picks more, bound to the device key', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final r = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      expect(r.grant.type, GrantType.session);
      expect(r.grant.expiresAt.difference(now), const Duration(hours: 1));
      expect(r.grant.granteeKeyId, await cert.keyId());
      await expectLater(pickUpAndOpen(d, at: now.add(const Duration(hours: 2))), throwsA(anything));
    });

    test('the patient picks how long, never past 48 hours', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final r = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, window: const Duration(hours: 48), at: now);
      expect(r.grant.expiresAt.difference(now), const Duration(hours: 48));
      await expectLater(
        service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, window: const Duration(hours: 49), at: now),
        throwsA(anything),
      );
    });
  });

  group('changing and ending access', () {
    test('changing the time sends the same share again with the new end, and tells the doctor it was replaced', () async {
      final d = await doctor();
      final first = await service.share(patientId: 'p1', doctor: await service.scan(d.qr, now), levels: {AccessLevel.summary, AccessLevel.familyIllnesses}, at: now);
      await pickUpAndOpen(d);

      final later = now.add(const Duration(minutes: 30));
      final r = await service.changeTime(first.grant, const Duration(hours: 24), later);
      expect(r.grant.expiresAt, later.add(const Duration(hours: 24)));
      expect(r.grant.levels, {AccessLevel.summary, AccessLevel.familyIllnesses}, reason: 'same levels as before');
      expect(consent.activeGrantsFor('p1', later).single.id, r.grant.id, reason: 'the old grant is ended');

      final cert = DoctorCertificate.decode(d.qr);
      final opened = [for (final e in relay.pickUp(await RelayApi.doctorMailbox(cert.encryptionKey), later)) await ShareEnvelope.open(e, d.enc, later)];
      expect(opened.where((b) => b['type'] == 'close').single['replaced'], isTrue);
      expect(opened.where((b) => b['patient'] != null), hasLength(1));

      // Shorter works the same way; a share made before this version needs a new scan.
      final shorter = await service.changeTime(r.grant, const Duration(hours: 1), later);
      expect(shorter.grant.expiresAt, later.add(const Duration(hours: 1)));
      await expectLater(service.changeTime(first.grant, const Duration(hours: 4), later), throwsStateError);
    });

    test('moving from Summary to All my reports replaces the grant instead of throwing', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final first = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      final second = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.allReports}, at: now.add(const Duration(minutes: 5)));
      final live = consent.activeGrantsFor('p1', now.add(const Duration(minutes: 6)));
      expect(live.map((g) => g.id), [second.grant.id]);
      expect(live.single.id, isNot(first.grant.id));
      expect(relay.pending(await RelayApi.doctorMailbox(cert.encryptionKey)), 2,
          reason: 'the first, undelivered share was withdrawn; the new share and a close notice for the old one wait');
    });

    test('ending access removes a share the doctor has not picked up', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final r = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      await service.endAccess(r.grant, now.add(const Duration(minutes: 1)));
      // Only the close notice is left for the doctor; the share itself is gone.
      final close = await pickUpAndOpen(d, at: now.add(const Duration(minutes: 1)));
      expect(close['type'], 'close');
      expect(consent.activeGrantsFor('p1', now), isEmpty);
    });

    test('ending access after pickup tells the doctor device to close it, with a secret only the patient holds', () async {
      final d = await doctor();
      final cert = await service.scan(d.qr, now);
      final r = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      final bundle = await pickUpAndOpen(d);
      expect(bundle['closeSecret'], isA<String>());
      await service.endAccess(r.grant, now.add(const Duration(minutes: 5)));
      final close = await pickUpAndOpen(d, at: now.add(const Duration(minutes: 5)));
      expect(close['type'], 'close');
      expect(close['grantId'], r.grant.id);
      expect(close['closeSecret'], bundle['closeSecret']);

      // A second share gets a different secret: one close cannot end another.
      final r2 = await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now.add(const Duration(minutes: 6)));
      final b2 = await pickUpAndOpen(d, at: now.add(const Duration(minutes: 6)));
      expect(b2['closeSecret'], isNot(bundle['closeSecret']));
      expect(r2.grant.id, isNot(r.grant.id));
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

  group('a doctor revoked after their certificate was issued', () {
    Future<SignedPrescription> write(Doctor d) => SignedPrescription(
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
          issuedAt: now,
        ).signedWith(d.sign);
    late _Switch status;
    late ClinicalShareService online;
    setUp(() {
      status = _Switch();
      online = ClinicalShareService(
        replyIdentity: (_) async => me,
        trust: trust,
        consent: consent,
        access: RecordAccess(consent: consent, audit: audit, repository: repo),
        audit: audit,
        repository: repo,
        relay: relay,
        doctors: status,
      );
    });

    test('is refused at scan, at share and for prescriptions, while the phone can ask', () async {
      final d = await doctor();
      final cert = await online.scan(d.qr, now);
      await online.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      status.answer = false;
      final revoked = isA<CertificateRejected>().having((e) => e.problem, 'problem', CertificateProblem.revoked);
      await expectLater(online.scan(d.qr, now), throwsA(revoked));
      await expectLater(online.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now), throwsA(revoked));
      await expectLater(online.acceptPrescription(patientId: 'p1', rx: await write(d), doctorCertificateQr: d.qr, at: now), throwsA(revoked));
    });

    test('offline, the certificate itself decides', () async {
      final d = await doctor();
      status.answer = null;
      await online.share(patientId: 'p1', doctor: await online.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
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

  group('original pages travel with the share', () {
    ClinicalShareService withOriginals(Map<String, List<Uint8List>> pages) => ClinicalShareService(
          trust: trust,
          consent: consent,
          access: RecordAccess(consent: consent, audit: audit, repository: repo),
          audit: audit,
          repository: repo,
          relay: relay,
          replyIdentity: (_) async => me,
          originals: (r) async => pages[r.attachmentId] ?? const [],
        );

    test('the latest tests carry their photographed originals; unreleased records never do', () async {
      final svc = withOriginals({
        'demo-photo-demo-hba1c-2026-09': [Uint8List.fromList(List.filled(1000, 1))],
        'demo-photo-demo-lipid-2026-09': [Uint8List.fromList(List.filled(1000, 2)), Uint8List.fromList(List.filled(1000, 3))],
        'demo-photo-xray': [Uint8List.fromList(List.filled(1000, 4))],
      });
      final d = await doctor();
      await svc.share(patientId: 'p1', doctor: await svc.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final b = await pickUpAndOpen(d);
      final originals = (b['originals']! as Map).cast<String, Object?>();
      expect(originals.keys, containsAll(['demo-hba1c-2026-09', 'demo-lipid-2026-09']));
      expect((originals['demo-lipid-2026-09']! as List), hasLength(2));
      expect(originals.containsKey('demo-xray-2026-01'), isFalse, reason: 'scans are not in the Summary level');
      expect(b['originalsOmitted'], 0);
    });

    test('pages past the size budget are counted, not silently dropped', () async {
      final big = Uint8List(ClinicalShareService.originalsBudget ~/ 2 + 10);
      final svc = withOriginals({
        'demo-photo-demo-hba1c-2026-09': [big],
        'demo-photo-demo-lipid-2026-09': [big],
        'demo-photo-demo-glucose-2026-09': [big],
      });
      final d = await doctor();
      await svc.share(patientId: 'p1', doctor: await svc.scan(d.qr, now), levels: {AccessLevel.summary}, at: now);
      final b = await pickUpAndOpen(d);
      expect((b['originals']! as Map).length, 1);
      expect(b['originalsOmitted'], 2);
    });
  });

  test("a parent's share for a child records the parent as grantor and tells the doctor", () async {
    final d = await doctor();
    final r = await service.share(
      patientId: 'p1',
      doctor: await service.scan(d.qr, now),
      levels: {AccessLevel.summary},
      at: now,
      grantorId: 'patient:parent-1',
      sharedBy: 'Ramesh Sharma (parent)',
    );
    expect(r.grant.grantorId, 'patient:parent-1');
    expect(audit.entriesFor('p1').where((e) => e.action == AuditAction.clinicalShare).single.actorId, 'patient:parent-1');
    expect((await pickUpAndOpen(d))['sharedBy'], 'Ramesh Sharma (parent)');
  });

  group('home readings', () {
    VitalReading bp(String id, DateTime at) => VitalReading(id: id, patientId: 'p1', at: at, kind: VitalKind.bloodPressure, systolic: 132, diastolic: 84, pulse: 76);

    test('reach a doctor only when the patient ticks them; only the last 30 days; the read is logged', () async {
      await repo.addVital(bp('v-old', now.subtract(const Duration(days: 45))));
      await repo.addVital(bp('v-new', now.subtract(const Duration(days: 3))));
      await repo.addVital(VitalReading(id: 'g1', patientId: 'p1', at: now.subtract(const Duration(days: 1)), kind: VitalKind.glucose, glucose: 112, context: GlucoseContext.fasting));
      final d = await doctor();
      final cert = await service.scan(d.qr, now);

      await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary}, at: now);
      expect((await pickUpAndOpen(d)).containsKey('homeReadings'), isFalse);
      expect(audit.entriesFor('p1').where((e) => e.dataClass == DataClass.vitals), isEmpty);

      await service.share(patientId: 'p1', doctor: cert, levels: {AccessLevel.summary, AccessLevel.homeReadings}, at: now.add(const Duration(minutes: 1)));
      final envs = relay.pickUp(await RelayApi.doctorMailbox(cert.encryptionKey), now.add(const Duration(minutes: 1)));
      final shares = [for (final e in envs) await ShareEnvelope.open(e, d.enc, now.add(const Duration(minutes: 1)))];
      final b = shares.firstWhere((x) => x['homeReadings'] != null);
      final items = ((b['homeReadings']! as Map)['items']! as List).cast<Map>();
      expect(items.map((i) => i['kind']).toSet(), {'bloodPressure', 'glucose'});
      expect(items, hasLength(2), reason: 'the 45-day-old reading stays home');
      expect((b['homeReadings']! as Map)['measuredBy'], 'patient');
      expect(audit.entriesFor('p1').where((e) => e.dataClass == DataClass.vitals && e.actorId.startsWith('doctor:')), isNotEmpty);
    });
  });
}

class _Switch implements DoctorStatus {
  bool? answer = true;
  @override
  Future<bool?> stillApproved(DoctorCertificate cert) async => answer;
}
