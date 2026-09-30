import 'dart:math';

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import '../ai/cloud_escalation.dart';
import '../ai/insight.dart';
import '../ai/plane_a/insight_engine.dart';
import '../audit/audit_log.dart';
import '../consent/consent_store.dart';
import '../consent/consent_token.dart';
import '../consent/grants.dart';
import '../consent/record_access.dart';
import '../crypto/key_derivation.dart';
import '../emergency/emergency_card.dart';
import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../model/patient.dart';
import '../storage/byte_store.dart';
import '../storage/record_repository.dart';
import '../share/clinical_share_service.dart';
import '../share/http_relay_client.dart';
import '../share/relay.dart';
import '../share/share_bundle.dart';
import '../share/reply_identity.dart';
import '../storage/sealed_store.dart';
import '../vault/backup_vault.dart';
import 'cloud_escalation_adapter.dart';
import 'demo_data.dart';

/// Everything the screens use, assembled once. Screens call these methods
/// rather than reaching into stores, so every patient action that changes
/// consent also writes its audit entry.
class AppServices {
  AppServices._({
    required this.clock,
    required this.sealed,
    required this.repository,
    required this.audit,
    required this.consent,
    required this.access,
    required this.insightEngine,
    required this.emergency,
    required this.vault,
    required this.cloud,
    required this.settings,
  });

  /// Phase 2 sharing, or null when this build has no relay or registry
  /// configured — the Share screen then says so instead of pretending.
  ClinicalShareService? sharing;

  static const _grantsBlob = 'grants';
  static const _settingsBlob = 'settings';

  final DateTime Function() clock;
  final SealedStore sealed;
  final RecordRepository repository;
  final PersistentAuditLog audit;
  final ConsentStore consent;
  final RecordAccess access;
  final InsightEngine insightEngine;
  final EmergencyCardStore emergency;
  final BackupVault vault;
  final CloudEscalation cloud;
  final Map<String, Object?> settings;

  Future<void> _pendingWrite = Future.value();

  static Future<AppServices> open({
    required ByteStore bytes,
    required SecretKey deviceKey,
    required RemoteVaultStore remote,
    required KdfParams kdf,
    required CloudEscalationFactory cloudFactory,
    DateTime Function()? clock,
    ShareConfig? share,
    RelayClient Function(WithdrawTokenStore tokens)? relayOverride,
  }) async {
    final now = clock ?? DateTime.now;
    final sealed = SealedStore(bytes, deviceKey);
    final repository = await RecordRepository.open(sealed);
    final audit = await PersistentAuditLog.open(sealed);
    final settings = ((await sealed.read(_settingsBlob) as Map?) ?? {}).cast<String, Object?>();
    late final AppServices services;
    final consent = ConsentStore(onChanged: (s) => services._persistGrants());
    consent.restore(((await sealed.read(_grantsBlob) as Map?) ?? {}).cast<String, Object?>());
    final access = RecordAccess(consent: consent, audit: audit, repository: repository);
    services = AppServices._(
      clock: now,
      sealed: sealed,
      repository: repository,
      audit: audit,
      consent: consent,
      access: access,
      insightEngine: InsightEngine(access),
      emergency: EmergencyCardStore(bytes, audit),
      vault: BackupVault(remote: remote, audit: audit, params: kdf),
      cloud: cloudFactory(repository: repository, consent: consent, audit: audit, access: access, clock: now),
      settings: settings,
    );
    consent.evictFinished(now());
    if (share != null && share.isComplete) {
      final tokens = _SealedTokens(sealed);
      services.sharing = ClinicalShareService(
        trust: RegistryTrust([SimplePublicKey(base64Decode(share.registryKey!), type: KeyPairType.ed25519)]),
        consent: consent,
        access: access,
        audit: audit,
        repository: repository,
        relay: relayOverride?.call(tokens) ?? HttpRelayClient(baseUrl: Uri.parse(share.relayUrl!), tokens: tokens),
        replyIdentity: services._replyIdentity,
      );
    }
    return services;
  }

  /// Waits for background grant persistence. Tests call this before reopening.
  Future<void> flush() => _pendingWrite;

  void _persistGrants() {
    final snapshot = consent.toJson();
    _pendingWrite = _pendingWrite.then((_) => sealed.write(_grantsBlob, snapshot));
  }

  Future<void> _saveSettings() => sealed.write(_settingsBlob, settings);

  final Map<String, ReplyIdentity> _replies = {};

  /// One reply mailbox and key per patient, created on first share and kept
  /// sealed under the device key.
  Future<ReplyIdentity> _replyIdentity(String patientId) async {
    final cached = _replies[patientId];
    if (cached != null) return cached;
    final all = ((await sealed.read('reply_identities') as Map?) ?? {}).cast<String, Object?>();
    final stored = all[patientId];
    final id = stored == null ? await ReplyIdentity.create() : await ReplyIdentity.fromJson((stored as Map).cast());
    if (stored == null) {
      all[patientId] = await id.toJson();
      await sealed.write('reply_identities', all);
    }
    return _replies[patientId] = id;
  }

  /// The patient ticked "still taking" at share time.
  Future<void> confirmMedicines(Set<String> recordIds, DateTime at) async {
    for (final r in records().where((r) => recordIds.contains(r.id))) {
      await repository.add(HealthRecord(
        id: r.id,
        patientId: r.patientId,
        kind: r.kind,
        title: r.title,
        date: r.date,
        source: r.source,
        doctor: r.doctor,
        facility: r.facility,
        results: r.results,
        dose: r.dose,
        ingredient: r.ingredient,
        labName: r.labName,
        sampleDate: r.sampleDate,
        attachmentId: r.attachmentId,
        endDate: r.endDate,
        patientConfirmedAt: at,
      ));
    }
  }

  /// The patient's own Summary for "Show on my phone": built on the phone
  /// from the patient's own data — nothing is sent and no grant is involved.
  Map<String, Object?> ownSummary() {
    final p = currentPatient!;
    final prof = clinicalProfile();
    final rs = records();
    final all = scopesFor(AccessLevel.values.toSet());
    return ShareBundle.build(
      patient: p,
      at: clock(),
      levels: {AccessLevel.summary, AccessLevel.familyIllnesses},
      filter: null,
      requested: all,
      granted: all,
      allergies: prof.allergies,
      conditions: prof.conditions,
      familyIllnesses: prof.familyIllnesses,
      prescriptions: [for (final r in rs) if (r.kind == RecordKind.prescription) r],
      reports: [for (final r in rs) if (r.kind == RecordKind.report) r],
      scans: const [],
      profileUpdatedAt: prof.updatedAt,
    );
  }

  ClinicalProfile clinicalProfile() =>
      currentPatientId == null ? const ClinicalProfile() : repository.profileOf(currentPatientId!);

  Future<void> saveClinicalProfile(ClinicalProfile p) => repository.saveProfile(
        currentPatientId!,
        ClinicalProfile(allergies: p.allergies, conditions: p.conditions, familyIllnesses: p.familyIllnesses, updatedAt: clock()),
      );

  // ---- profile -----------------------------------------------------------

  String? get currentPatientId => settings['currentPatientId'] as String?;
  Patient? get currentPatient => currentPatientId == null ? null : repository.patient(currentPatientId!);

  Future<Patient> createProfile({required String name, required DateTime dob, required Sex sex, bool demo = false}) async {
    final id = 'p-${_randomId()}';
    final patient = demo ? DemoData.patient(id) : Patient(id: id, name: name, dateOfBirth: dob, sex: sex);
    await repository.savePatient(patient);
    if (demo && repository.recordsOf(id).isEmpty) {
      await repository.addAll(DemoData.records(id));
      await repository.saveProfile(id, DemoData.profile(clock()));
    }
    settings['currentPatientId'] = id;
    settings['demo'] = demo;
    await _saveSettings();
    return patient;
  }

  Future<void> updatePatient(Patient p) => repository.savePatient(p);

  bool get isDemo => settings['demo'] == true;

  // ---- records -----------------------------------------------------------

  List<HealthRecord> records() => currentPatientId == null ? const [] : repository.recordsOf(currentPatientId!);

  Future<void> addRecord(HealthRecord r) async {
    await repository.add(r);
    await audit.append(AuditEntry(
      at: clock(),
      actorId: 'patient:${r.patientId}',
      patientId: r.patientId,
      action: AuditAction.edit,
      dataClass: r.dataClass,
      detail: 'added "${r.title}"',
    ));
  }

  // ---- insights (Plane A) -----------------------------------------------

  String _insightGrantId(String patientId) => Grants.onDeviceInsights(patientId: patientId, at: DateTime(2000)).id;

  bool insightsEnabled() {
    final id = currentPatientId;
    if (id == null) return false;
    return consent.activeGrantsFor(id, clock()).any((g) => g.id == _insightGrantId(id));
  }

  /// The patient turning Insights on is the human approval Plane A needs.
  Future<void> enableInsights() async {
    final id = currentPatientId!;
    final at = clock();
    final grant = Grants.onDeviceInsights(patientId: id, at: at);
    consent.issue(grant, at: at);
    await audit.append(AuditEntry(
      at: at,
      actorId: 'patient:$id',
      patientId: id,
      action: AuditAction.grantIssued,
      tokenId: grant.id,
      detail: 'on-device insights, 24 hours',
    ));
  }

  Future<InsightRun?> runInsights() async {
    final patient = currentPatient;
    if (patient == null || !insightsEnabled()) return null;
    return insightEngine.runFor(patient: patient, tokenId: _insightGrantId(patient.id), at: clock());
  }

  // ---- sharing -----------------------------------------------------------

  List<ConsentToken> activeGrants() =>
      currentPatientId == null ? const [] : consent.activeGrantsFor(currentPatientId!, clock());

  Future<void> revoke(ConsentToken grant) async {
    consent.revoke(grant.id);
    await audit.append(AuditEntry(
      at: clock(),
      actorId: 'patient:${grant.patientId}',
      patientId: grant.patientId,
      action: AuditAction.grantRevoked,
      tokenId: grant.id,
      detail: grant.grantedToActorId,
    ));
  }

  List<AuditEntry> auditEntries() => currentPatientId == null ? const [] : audit.entriesFor(currentPatientId!);

  // ---- erasure (DPDP §12) -------------------------------------------------

  /// Deletes this profile's records, grants, Emergency ID and backup. The
  /// erasure itself stays as the only entry in the log.
  Future<void> eraseProfile({required String account}) async {
    final id = currentPatientId!;
    final at = clock();
    await repository.eraseFor(id);
    consent.eraseFor(id);
    await emergency.erase(id);
    await vault.erase(account);
    await audit.eraseFor(
      id,
      AuditEntry(at: at, actorId: 'patient:$id', patientId: id, action: AuditAction.erasure, detail: 'records, grants, Emergency ID and backup deleted'),
    );
    settings.remove('currentPatientId');
    settings.remove('demo');
    await _saveSettings();
    await flush();
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Where phase 2 sharing connects. Both values come from the build
/// (`--dart-define=LT_RELAY_URL=… --dart-define=LT_REGISTRY_KEY=…`).
class ShareConfig {
  const ShareConfig({this.relayUrl, this.registryKey});
  final String? relayUrl;

  /// The registry's Ed25519 public key (base64), pinned into the build.
  final String? registryKey;

  bool get isComplete => (relayUrl ?? '').isNotEmpty && (registryKey ?? '').isNotEmpty;
}

class _SealedTokens implements WithdrawTokenStore {
  _SealedTokens(this.sealed);
  final SealedStore sealed;
  static const _blob = 'withdraw_tokens';

  @override
  Future<void> put(String grantId, String token) async {
    final m = ((await sealed.read(_blob) as Map?) ?? {}).cast<String, Object?>();
    m[grantId] = token;
    await sealed.write(_blob, m);
  }

  @override
  Future<String?> take(String grantId) async {
    final m = ((await sealed.read(_blob) as Map?) ?? {}).cast<String, Object?>();
    final t = m.remove(grantId) as String?;
    await sealed.write(_blob, m);
    return t;
  }
}

typedef CloudEscalationFactory = CloudEscalation Function({
  required RecordRepository repository,
  required ConsentStore consent,
  required AuditLog audit,
  required RecordAccess access,
  required DateTime Function() clock,
});

/// Default Plane C wiring: kill switch off, no network client.
CloudEscalation defaultCloud({
  required RecordRepository repository,
  required ConsentStore consent,
  required AuditLog audit,
  required RecordAccess access,
  required DateTime Function() clock,
}) =>
    CloudEscalationAdapter.dark(repository: repository, consent: consent, audit: audit, access: access, clock: clock);
