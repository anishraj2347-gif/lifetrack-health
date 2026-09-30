import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ai/plane_c/cloud_gateway.dart';
import 'package:lifetrack/src/ai/plane_c/pseudonymised_slice.dart';
import 'package:lifetrack/src/app/demo_data.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/consent/consent_store.dart';
import 'package:lifetrack/src/consent/grants.dart';
import 'package:lifetrack/src/consent/record_access.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/storage/record_repository.dart';
import 'package:lifetrack/src/storage/sealed_store.dart';

class RecordingClient implements CloudClient {
  RecordingClient({this.reply = const ['HbA1c moved from 6.8 to 6.1 %.'], this.fail = false});
  final List<String> reply;
  final bool fail;
  final sent = <String>[];
  @override
  Future<List<String>> analyse(String payload) async {
    sent.add(payload);
    if (fail) throw const CloudRefused('network down');
    return reply;
  }
}

void main() {
  // Deliberately far from the wall clock: every gate must use the injected
  // time. If any of them read DateTime.now(), these tests would fail today.
  final now = DateTime(2031, 5, 6, 10);
  final patient = DemoData.patient('p1');

  late ConsentStore consent;
  late InMemoryAuditLog audit;
  late RecordRepository repo;
  late RecordingClient client;

  Future<CloudGateway> gateway({TierPolicy? policy, RecordingClient? c}) async {
    client = c ?? RecordingClient();
    return CloudGateway(
      access: RecordAccess(consent: consent, audit: audit, repository: repo),
      audit: audit,
      policy: policy ?? RemoteTierPolicy(enabledRegions: {'IN'}, fetchedAt: now.subtract(const Duration(hours: 1))),
      client: client,
    );
  }

  String disclosure() => PseudonymisedSlice.fromRecords(
        patient: patient,
        records: [for (final r in repo.recordsOf('p1')) if (r.dataClass == DataClass.reports) r],
        at: now,
      ).canonical;

  String cloudGrant() {
    final g = Grants.cloudOnce(patientId: 'p1', at: now);
    consent.issue(g, at: now);
    return g.id;
  }

  HumanAction tap({DateTime? at, String? shown}) =>
      HumanAction(surface: 'test', tappedAt: at ?? now.subtract(const Duration(seconds: 5)), disclosure: shown ?? disclosure());

  setUp(() async {
    consent = ConsentStore();
    audit = InMemoryAuditLog();
    repo = await RecordRepository.open(SealedStore(InMemoryByteStore(), SecretKey(List.filled(32, 1))));
    await repo.savePatient(patient);
    await repo.addAll(DemoData.records('p1'));
  });

  test('a valid tap with its own grant sends exactly the disclosed payload', () async {
    final g = await gateway();
    final result = await g.analyse(patient: patient, regionCode: 'IN', action: tap(), tokenId: cloudGrant(), now: now);
    expect(result.statements, hasLength(1));
    expect(client.sent.single, disclosure());
  });

  test('the kill switch refuses, using the caller\'s clock', () async {
    final stale = RemoteTierPolicy(enabledRegions: {'IN'}, fetchedAt: now.subtract(const Duration(hours: 7)));
    final g = await gateway(policy: stale);
    await expectLater(g.analyse(patient: patient, regionCode: 'IN', action: tap(), tokenId: cloudGrant(), now: now), throwsA(isA<CloudRefused>()));
    expect(client.sent, isEmpty);
    final dark = await gateway(policy: const DisabledTierPolicy());
    await expectLater(dark.analyse(patient: patient, regionCode: 'IN', action: tap(), tokenId: cloudGrant(), now: now), throwsA(isA<CloudRefused>()));
  });

  test('a tap is single-use', () async {
    final g = await gateway();
    final t = tap();
    await g.analyse(patient: patient, regionCode: 'IN', action: t, tokenId: cloudGrant(), now: now);
    await expectLater(g.analyse(patient: patient, regionCode: 'IN', action: t, tokenId: cloudGrant(), now: now), throwsA(isA<CloudRefused>()));
    expect(client.sent, hasLength(1));
  });

  test('two concurrent sends on one tap cross once', () async {
    final g = await gateway();
    final t = tap();
    final token = cloudGrant();
    final results = await Future.wait([
      g.analyse(patient: patient, regionCode: 'IN', action: t, tokenId: token, now: now).then((_) => 'ok', onError: (_) => 'refused'),
      g.analyse(patient: patient, regionCode: 'IN', action: t, tokenId: token, now: now).then((_) => 'ok', onError: (_) => 'refused'),
    ]);
    expect(results..sort(), ['ok', 'refused']);
    expect(client.sent, hasLength(1));
  });

  test('a stale tap is refused', () async {
    final g = await gateway();
    await expectLater(
      g.analyse(patient: patient, regionCode: 'IN', action: tap(at: now.subtract(const Duration(minutes: 2))), tokenId: cloudGrant(), now: now),
      throwsA(isA<CloudRefused>()),
    );
  });

  test('Plane A\'s grant cannot authorise a cloud crossing', () async {
    final a = Grants.onDeviceInsights(patientId: 'p1', at: now);
    consent.issue(a, at: now);
    final g = await gateway();
    await expectLater(
      g.analyse(patient: patient, regionCode: 'IN', action: tap(), tokenId: a.id, now: now),
      throwsA(isA<ConsentDenied>().having((e) => e.reason, 'reason', DenialReason.wrongActor)),
    );
    expect(client.sent, isEmpty);
  });

  test('a payload that differs from what the patient read is refused', () async {
    final g = await gateway();
    await expectLater(
      g.analyse(patient: patient, regionCode: 'IN', action: tap(shown: '{"entries":[]}'), tokenId: cloudGrant(), now: now),
      throwsA(isA<CloudRefused>()),
    );
    expect(client.sent, isEmpty);
  });

  test('the egress is audited before the send, so a failed send is still recorded', () async {
    final g = await gateway(c: RecordingClient(fail: true));
    await expectLater(g.analyse(patient: patient, regionCode: 'IN', action: tap(), tokenId: cloudGrant(), now: now), throwsA(isA<CloudRefused>()));
    final egress = audit.entriesFor('p1').where((e) => e.action == AuditAction.cloudEgress);
    expect(egress, hasLength(1));
    expect(egress.single.actorId, 'agent:cloud');
  });

  test('banned statements in the reply are dropped, not rephrased', () async {
    final g = await gateway(c: RecordingClient(reply: ['HbA1c fell.', 'This suggests early diabetes.']));
    final r = await g.analyse(patient: patient, regionCode: 'IN', action: tap(), tokenId: cloudGrant(), now: now);
    expect(r.statements, ['HbA1c fell.']);
    expect(r.dropped, 1);
  });

  test('the slice carries no identifiers and is bounded', () {
    final text = disclosure();
    for (final s in ['Anjali', 'Sharma', 'p1', '1984', 'Mehta', 'Apollo', 'demo-']) {
      expect(text.contains(s), isFalse, reason: s);
    }
    final slice = PseudonymisedSlice.fromRecords(patient: patient, records: repo.recordsOf('p1'), at: now);
    expect(slice.entries.length, lessThanOrEqualTo(PseudonymisedSlice.maxEntries));
    final withFreeText = PseudonymisedSlice.fromRecords(patient: patient, at: now, records: [
      HealthRecord(
        id: 'x',
        patientId: 'p1',
        kind: RecordKind.report,
        title: 'x',
        date: DateTime(2031, 1, 1),
        source: RecordSource.typedByPatient,
        results: const [LabResult(analyte: 'Ramesh special test', value: 1, unit: 'u')],
      ),
    ]).canonical;
    expect(withFreeText.contains('Ramesh'), isFalse, reason: 'free-text analyte names are excluded');
  });
}
