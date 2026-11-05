import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/app/demo_data.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/consent/consent_store.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/consent/record_access.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/share/clinical_share_service.dart';
import 'package:lifetrack/src/share/http_relay_client.dart';
import 'package:lifetrack/src/share/pending_closes.dart';
import 'package:lifetrack/src/share/relay.dart';
import 'package:lifetrack/src/share/reply_identity.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/storage/record_repository.dart';
import 'package:lifetrack/src/storage/sealed_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lifetrack_server/api.dart';
import 'package:lifetrack_server/id_registry.dart';
import 'package:lifetrack_server/registry.dart';
import 'package:lifetrack_server/relay_store.dart';
import 'package:lifetrack_server/vault_store.dart';
import 'package:shelf/shelf.dart' as shelf;

import '../support/offline.dart';

/// Ending access with the server off: the patient's act stands, the log says
/// so, the message waits, and the screen tells the truth.
void main() {
  final now = DateTime(2026, 9, 30, 11, 30);
  late SimpleKeyPair registry;
  late ConsentStore consent;
  late InMemoryAuditLog audit;
  late SwitchableRelay relay;
  late ClinicalShareService service;
  late InMemoryPendingCloses closes;
  late TestDoctor doctor;

  ClinicalShareService build(RelayClient r, {RegistryTrust? trust, WithdrawTokenStore? keyBook}) {
    final me = ReplyIdentity.create();
    return ClinicalShareService(
      replyIdentity: (_) => me,
      trust: trust ?? const RegistryTrust.none(),
      consent: consent,
      access: RecordAccess(consent: consent, audit: audit, repository: repo),
      audit: audit,
      repository: repo,
      relay: r,
      closes: closes,
      keyBook: keyBook,
    );
  }

  setUp(() async {
    registry = await Ed25519().newKeyPair();
    consent = ConsentStore();
    audit = InMemoryAuditLog();
    relay = SwitchableRelay();
    closes = InMemoryPendingCloses();
    repo = await RecordRepository.open(SealedStore(InMemoryByteStore(), SecretKey(List.filled(32, 4))));
    await repo.savePatient(DemoData.patient('p1'));
    await repo.addAll(DemoData.records('p1'));
    doctor = await TestDoctor.make(registry);
    service = build(relay, trust: RegistryTrust([await registry.extractPublicKey()]));
  });

  Future<ShareReceipt> shared({DateTime? at}) async =>
      service.share(patientId: 'p1', doctor: await service.scan(doctor.qr, at ?? now), levels: {AccessLevel.summary}, at: at ?? now);

  test('offline: access ends here, nothing is thrown, and the log says what happened', () async {
    final r = await shared();
    await doctor.pickUp(relay.inner, now);
    relay.down = true;

    final at = now.add(const Duration(minutes: 5));
    final result = await service.endAccess(r.grant, at);

    expect(result, EndAccessResult.waitingForServer);
    expect(consent.activeGrantsFor('p1', at), isEmpty);
    final log = audit.entriesFor('p1').where((e) => e.action == AuditAction.grantRevoked).toList();
    expect(log.map((e) => e.detail), contains('ended by patient'), reason: 'used to be missing altogether (#13)');
    expect(log.first.detail, contains('has not been told yet'), reason: 'the log does not claim the doctor knows');
    expect(await service.waitingToClose('p1'), hasLength(1));
  });

  test('the revocation is on the record before the phone reaches for the network', () async {
    final r = await shared();
    int revoked() => audit.entriesFor('p1').where((e) => e.action == AuditAction.grantRevoked).length;
    final seen = <int>[];
    relay
      ..down = true
      ..onCall = () => seen.add(revoked());
    await service.endAccess(r.grant, now);
    expect(seen, isNotEmpty);
    expect(seen.first, 1);
  });

  test('when the server is back the retry withdraws and closes, with the close secret', () async {
    final r = await shared();
    final bundle = (await doctor.pickUp(relay.inner, now)).single;
    relay.down = true;
    final later = now.add(const Duration(minutes: 5));
    await service.endAccess(r.grant, later);

    expect(await service.retryPendingCloses(later), 1, reason: 'still down: it stays queued');
    expect(await doctor.pickUp(relay.inner, later), isEmpty);

    relay.down = false;
    final back = later.add(const Duration(minutes: 5));
    expect(await service.retryPendingCloses(back), 0);
    final close = (await doctor.pickUp(relay.inner, back)).single;
    expect((close['type'], close['grantId'], close['closeSecret']), ('close', r.grant.id, bundle['closeSecret']));
    expect(close.containsKey('replaced'), isFalse, reason: 'the doctor app must announce that access ended');
    expect(await service.waitingToClose('p1'), isEmpty);
    expect(audit.entriesFor('p1').first.detail, contains('told that access ended'));
  });

  test('a share not yet picked up is withdrawn by the retry, so the doctor never gets it', () async {
    final r = await shared();
    relay.down = true;
    await service.endAccess(r.grant, now);
    relay.down = false;
    await service.retryPendingCloses(now);
    final left = await doctor.pickUp(relay.inner, now);
    expect(left.map((m) => m['type']), ['close'], reason: 'only the close message is left');
  });

  test('past the share\'s end time the message is dropped and the log says so', () async {
    final r = await shared();
    relay.down = true;
    await service.endAccess(r.grant, now);
    final after = r.grant.expiresAt.add(const Duration(minutes: 1));
    final calls = relay.calls;
    expect(await service.retryPendingCloses(after), 0);
    expect(relay.calls, calls, reason: 'nothing to send to a share the relay has already deleted');
    expect(audit.entriesFor('p1').first.detail, contains('reached its end time'));
  });

  test('one message that keeps failing does not hold back the others', () async {
    final first = await shared();
    final other = await TestDoctor.make(registry, id: 'DMC-999');
    final second = await service.share(patientId: 'p1', doctor: other.cert, levels: {AccessLevel.summary}, at: now);
    relay.down = true;
    await service.endAccess(first.grant, now);
    await service.endAccess(second.grant, now);
    relay.down = false;
    relay.onCall = () {
      if (relay.calls == 1) throw const SocketLikeFailure();
    };
    relay.calls = 0;
    expect(await service.retryPendingCloses(now), 1);
    expect((await service.waitingToClose('p1')).single.grantId, first.grant.id);
  });

  group('changing a share with the server off', () {
    test('nothing is lost: the old share stands and the new grant does not', () async {
      final first = await shared();
      await doctor.pickUp(relay.inner, now);
      relay.down = true;
      final later = now.add(const Duration(minutes: 30));

      await expectLater(service.changeTime(first.grant, const Duration(hours: 4), later), throwsA(isA<SocketLikeFailure>()));

      expect(consent.activeGrantsFor('p1', later).map((g) => g.id), [first.grant.id]);
      expect(await service.canChangeTime(first.grant), isTrue, reason: 'it can be tried again without a new scan');
      expect(audit.entriesFor('p1').where((e) => e.detail == 'share not delivered'), hasLength(1));

      // Back online, the same change goes through and replaces the old share.
      relay.down = false;
      await service.retryPendingCloses(later);
      final r = await service.changeTime(first.grant, const Duration(hours: 4), later);
      expect(consent.activeGrantsFor('p1', later).single.id, r.grant.id);
    });
  });

  group('through the real client and handler', () {
    late RelayStore store;
    late bool serverOff;
    late http.Client client;
    final base = Uri.parse('http://127.0.0.1:8787');

    setUp(() async {
      store = RelayStore();
      serverOff = false;
      final handler = LifeTrackApi(
        registry: await DoctorRegistry.open(signingKey: await Ed25519().newKeyPair()),
        relay: store,
        vault: VaultStore(Directory.systemTemp.createTempSync('lt-end-')),
        ids: await IdRegistry.open(),
        adminToken: 'a',
      ).handler;
      client = MockClient((req) async {
        if (serverOff) throw http.ClientException('Connection refused', req.url);
        final res = await handler(shelf.Request(req.method, req.url, body: req.bodyBytes, headers: req.headers));
        return http.Response.bytes(await res.read().expand((c) => c).toList(), res.statusCode, headers: res.headers);
      });
    });

    test('the withdraw token survives a failed attempt, and the retry really removes the share', () async {
      final tokens = InMemoryWithdrawTokens();
      final phone = build(HttpRelayClient(baseUrl: base, tokens: tokens, client: client), keyBook: tokens);
      final t0 = DateTime.now().toUtc();
      final r = await phone.share(patientId: 'p1', doctor: doctor.cert, levels: {AccessLevel.summary}, at: t0);
      expect(store.total, 1);

      serverOff = true;
      expect(await phone.endAccess(r.grant, t0), EndAccessResult.waitingForServer);
      expect(await tokens.peek(r.grant.id), isNotNull, reason: 'it used to be spent before the call was made');
      expect(store.total, 1, reason: 'the share is still sitting on the relay');

      serverOff = false;
      expect(await phone.retryPendingCloses(t0), 0);
      expect(store.total, 1, reason: 'the share is gone; the close message is what is left');
      expect(await tokens.peek(r.grant.id), isNull);
      expect(await tokens.peek('close-${r.grant.id}'), isNull, reason: 'no token is kept for a close message');
    });

    test('an answer other than success keeps the token too', () async {
      final tokens = InMemoryWithdrawTokens();
      await tokens.put('g1', 'token');
      final refusing = MockClient((_) async => http.Response('{}', 500));
      final c = HttpRelayClient(baseUrl: base, tokens: tokens, client: refusing);
      await expectLater(c.withdraw(mailbox: 'd-${'a' * 64}', grantId: 'g1'), throwsA(isA<RelayUnavailable>()));
      expect(await tokens.peek('g1'), 'token');
    });
  });

  group('on the whole phone', () {
    late DateTime clock;
    late SwitchableRelay phoneRelay;

    TestPhone makePhone({Duration? retryAfter}) => TestPhone(relay: phoneRelay, registry: registry, now: () => clock, retryAfter: retryAfter);

    Future<ShareReceipt> share(AppServices s) async => s.sharing!.share(patientId: s.selfPatientId!, doctor: doctor.cert, levels: {AccessLevel.summary}, at: clock);

    setUp(() {
      clock = now;
      phoneRelay = SwitchableRelay();
    });

    test('the queue survives a restart, and the next start sends it', () async {
      final p = makePhone();
      final s = await p.open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final r = await share(s);
      await doctor.pickUp(phoneRelay.inner, clock);
      phoneRelay.down = true;
      expect(await s.endAccess(r.grant), EndAccessResult.waitingForServer);
      await s.flush();

      phoneRelay.down = false;
      final relaunched = await p.open();
      await relaunched.retryNow();
      expect((await doctor.pickUp(phoneRelay.inner, clock)).single['type'], 'close');
      expect(await relaunched.sharing!.waitingToClose(relaunched.selfPatientId!), isEmpty);
    });

    test('with the app left open, the timer sends it once the server is back', () async {
      final s = await makePhone(retryAfter: const Duration(milliseconds: 20)).open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final r = await share(s);
      await doctor.pickUp(phoneRelay.inner, clock);
      phoneRelay.down = true;
      await s.endAccess(r.grant);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await s.sharing!.waitingToClose(s.selfPatientId!), hasLength(1), reason: 'still down after a failed retry');

      phoneRelay.down = false;
      for (var i = 0; i < 100 && (await s.sharing!.waitingToClose(s.selfPatientId!)).isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await s.sharing!.waitingToClose(s.selfPatientId!), isEmpty);
      expect((await doctor.pickUp(phoneRelay.inner, clock)).single['type'], 'close');
    });

    test('"Check for prescriptions and updates" sends it too', () async {
      final s = await makePhone().open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final r = await share(s);
      phoneRelay.down = true;
      await s.endAccess(r.grant);
      phoneRelay.down = false;
      await s.checkInbox();
      expect(await s.sharing!.waitingToClose(s.selfPatientId!), isEmpty);
    });

    test('ending a delegation offline still ends it', () async {
      final s = await makePhone().open();
      await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      final adult = await s.addDelegatingAdult(name: 'Ravi Sharma', dob: DateTime(1950), sex: Sex.male, relation: 'father', typedName: 'Ravi Sharma');
      final r = await s.sharing!.share(patientId: adult.id, doctor: doctor.cert, levels: {AccessLevel.summary}, at: clock);
      phoneRelay.down = true;
      await s.endDelegation(adult.id);
      expect(s.consent.activeGrantsFor(adult.id, clock), isEmpty);
      expect(s.custodyOf(adult.id)!.isActive, isFalse, reason: 'it used to stop at the first failed call');
      expect((await s.sharing!.waitingToClose(adult.id)).single.grantId, r.grant.id);
    });

    testWidgets('the Share screen says so, and keeps saying so until the doctor is told', (tester) async {
      late AppServices s;
      await tester.runAsync(() async {
        s = await makePhone().open();
        await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
        await share(s);
        phoneRelay.down = true;
      });
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LifeTrackApp(boot: () async => s));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('End access'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('End access').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('End access').last);
      // The work behind the tap is real: let it finish, then draw.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('could not be reached, so'), findsOneWidget);
      expect(find.textContaining('has not been told yet'), findsWidgets);
      expect(s.activeGrants(), isEmpty);
    });
  });

  test('the close queue is plain JSON that round-trips', () {
    final c = PendingClose(grantId: 'g', patientId: 'p', doctorActorId: 'doctor:1', keyId: 'k', expiresAt: DateTime.utc(2026), doctorKey: 'a', closeSecret: 's', replaced: true);
    final back = PendingClose.fromJson((jsonDecode(jsonEncode(c.toJson())) as Map).cast());
    expect((back.grantId, back.doctorKey, back.closeSecret, back.replaced, back.mailbox), ('g', 'a', 's', true, 'd-k'));
    unawaited(Future<void>.value());
  });
}

late RecordRepository repo;
