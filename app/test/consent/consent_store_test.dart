import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/consent/consent_store.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/consent/grants.dart';
import 'package:lifetrack/src/model/health_record.dart';

void main() {
  final t0 = DateTime(2031, 2, 3, 9);
  late ConsentStore store;

  // Built directly with a fixed id: these tests are about the store's rules
  // for a given id. Grants.clinician mints a fresh id per approval.
  ConsentToken doctorGrant({String patient = 'p1', String doctor = 'NMC-1', Set<DataClass>? scopes, Duration window = const Duration(hours: 24), GrantType type = GrantType.session, DateTime? at}) =>
      ConsentToken(
        id: 'grant-$patient-doctor-$doctor',
        patientId: patient,
        grantedToActorId: Actors.doctor(doctor),
        grantorId: Actors.patient(patient),
        purpose: GrantPurpose.clinicalConsult,
        scopes: scopes ?? {DataClass.reports},
        issuedAt: at ?? t0,
        expiresAt: (at ?? t0).add(window),
        type: type,
      );

  test('Grants.clinician mints a fresh, patient-scoped id per approval', () {
    ConsentToken g() => Grants.clinician(patientId: 'p1', doctorRegistryId: 'NMC-1', scopes: {DataClass.reports}, at: t0, window: const Duration(hours: 4), type: GrantType.session);
    final a = g(), b = g();
    expect(a.id, isNot(b.id));
    expect(a.id, startsWith('grant-p1-doctor-NMC-1-'));
  });

  ConsentToken authorize(String id, {String actor = 'doctor:NMC-1', String patient = 'p1', DataClass cls = DataClass.reports, GrantPurpose purpose = GrantPurpose.clinicalConsult, DateTime? at}) =>
      store.authorize(tokenId: id, actorId: actor, patientId: patient, dataClass: cls, purpose: purpose, at: at ?? t0.add(const Duration(minutes: 5)));

  Matcher deniedFor(DenialReason r) => throwsA(isA<ConsentDenied>().having((e) => e.reason, 'reason', r));

  setUp(() => store = ConsentStore());

  group('authorize resolves the stored grant', () {
    test('a granted class authorizes and returns the stored token', () {
      final g = doctorGrant();
      store.issue(g, at: t0);
      expect(authorize(g.id).sameGrantAs(g), isTrue);
    });

    test('a class outside the stored scope is refused', () {
      store.issue(doctorGrant(), at: t0);
      expect(() => authorize(doctorGrant().id, cls: DataClass.prescriptions), deniedFor(DenialReason.outOfScope));
    });

    test('an unknown id is refused', () {
      expect(() => authorize('grant-p1-doctor-FORGED'), deniedFor(DenialReason.unknown));
    });

    test('another actor cannot exercise the grant', () {
      store.issue(doctorGrant(), at: t0);
      expect(() => authorize(doctorGrant().id, actor: 'doctor:NMC-2'), deniedFor(DenialReason.wrongActor));
    });

    test('the grant opens only its own patient', () {
      store.issue(doctorGrant(), at: t0);
      expect(() => authorize(doctorGrant().id, patient: 'p2'), deniedFor(DenialReason.wrongPatient));
    });

    test('purpose is enforced', () {
      store.issue(doctorGrant(), at: t0);
      expect(() => authorize(doctorGrant().id, purpose: GrantPurpose.cloudAnalysis), deniedFor(DenialReason.wrongPurpose));
    });

    test('expired and not-yet-valid grants are refused', () {
      store.issue(doctorGrant(), at: t0);
      expect(() => authorize(doctorGrant().id, at: t0.add(const Duration(hours: 24))), deniedFor(DenialReason.expired));
      expect(() => authorize(doctorGrant().id, at: t0.subtract(const Duration(seconds: 1))), deniedFor(DenialReason.notYetValid));
    });

    test('revocation is immediate', () {
      store.issue(doctorGrant(), at: t0);
      store.revoke(doctorGrant().id);
      expect(() => authorize(doctorGrant().id), deniedFor(DenialReason.revoked));
    });

    test('a one-time grant is spent by its first use', () {
      final g = doctorGrant(type: GrantType.oneTime);
      store.issue(g, at: t0);
      authorize(g.id);
      expect(() => authorize(g.id), deniedFor(DenialReason.spent));
    });
  });

  group('Plane C cannot spend Plane A authority', () {
    test('the cloud actor is refused on the on-device insights grant', () {
      final a = Grants.onDeviceInsights(patientId: 'p1', at: t0);
      store.issue(a, at: t0);
      expect(
        () => authorize(a.id, actor: Actors.cloud, purpose: GrantPurpose.cloudAnalysis),
        deniedFor(DenialReason.wrongActor),
      );
    });
  });

  group('issue cannot alter a live grant', () {
    test('re-issuing an identical grant is a no-op', () {
      store.issue(doctorGrant(), at: t0);
      store.issue(doctorGrant(), at: t0);
      expect(store.activeGrantsFor('p1', t0), hasLength(1));
    });

    test('a later expiry under a live id is refused', () {
      store.issue(doctorGrant(), at: t0);
      expect(() => store.issue(doctorGrant(window: const Duration(hours: 48)), at: t0), throwsA(isA<ConsentConflict>()));
    });

    test('same expiry, wider scope is refused', () {
      store.issue(doctorGrant(), at: t0);
      expect(
        () => store.issue(doctorGrant(scopes: {DataClass.reports, DataClass.personalNotes}), at: t0),
        throwsA(isA<ConsentConflict>()),
      );
      expect(() => authorize(doctorGrant().id, cls: DataClass.personalNotes), deniedFor(DenialReason.outOfScope));
    });

    test('the same doctor can be approved again once the old grant has expired', () {
      store.issue(doctorGrant(), at: t0);
      final nextDay = t0.add(const Duration(days: 2));
      store.issue(doctorGrant(at: nextDay), at: nextDay);
      expect(authorize(doctorGrant().id, at: nextDay.add(const Duration(minutes: 1))).issuedAt, nextDay);
    });

    test('a window beyond 48 hours cannot be constructed', () {
      expect(() => doctorGrant(window: const Duration(hours: 49)), throwsArgumentError);
    });
  });

  group('grant ids are patient-scoped', () {
    test('two patients granting one doctor do not collide', () {
      final a = doctorGrant(patient: 'p1');
      final b = doctorGrant(patient: 'p2');
      expect(a.id, isNot(b.id));
      store
        ..issue(a, at: t0)
        ..issue(b, at: t0);
      store.revoke(b.id);
      expect(store.activeGrantsFor('p1', t0).single.id, a.id);
      expect(authorize(a.id).patientId, 'p1');
    });
  });

  test('state survives a save and restore, including revocation and spending', () {
    final once = doctorGrant(doctor: 'NMC-9', type: GrantType.oneTime);
    store
      ..issue(doctorGrant(), at: t0)
      ..issue(once, at: t0);
    authorize(once.id, actor: 'doctor:NMC-9');
    store.revoke(doctorGrant().id);
    final copy = ConsentStore()..restore(store.toJson());
    expect(
      () => copy.authorize(tokenId: doctorGrant().id, actorId: 'doctor:NMC-1', patientId: 'p1', dataClass: DataClass.reports, purpose: GrantPurpose.clinicalConsult, at: t0),
      deniedFor(DenialReason.revoked),
    );
    expect(
      () => copy.authorize(tokenId: once.id, actorId: 'doctor:NMC-9', patientId: 'p1', dataClass: DataClass.reports, purpose: GrantPurpose.clinicalConsult, at: t0),
      deniedFor(DenialReason.spent),
    );
  });
}
