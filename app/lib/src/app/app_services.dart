import 'dart:math';
import 'dart:typed_data';

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
import '../model/custody.dart';
import '../model/health_record.dart';
import '../model/patient.dart';
import '../capture/report_image.dart';
import '../storage/attachment_store.dart';
import '../storage/byte_store.dart';
import '../storage/record_repository.dart';
import '../share/clinical_share_service.dart';
import '../export/record_export.dart';
import '../family/family_link.dart';
import '../share/http_relay_client.dart';
import '../share/relay.dart';
import '../share/share_bundle.dart';
import '../share/reply_identity.dart';
import '../storage/sealed_store.dart';
import '../vault/backup_vault.dart';
import 'cloud_escalation_adapter.dart';
import 'demo_data.dart';
import 'demo_report_images.dart';

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
    required this.attachments,
  });

  /// Original pages of paper reports and prescriptions, encrypted.
  final AttachmentStore attachments;

  /// Phase 2 sharing, or null when this build has no relay or registry
  /// configured — the Share screen then says so instead of pretending.
  ClinicalShareService? sharing;

  /// Links to adults with their own phones (P7). Travels over the same
  /// relay as sharing, so it exists exactly when sharing does.
  FamilyLinkService? links;

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
      attachments: AttachmentStore(bytes, deviceKey),
    );
    consent.evictFinished(now());
    await services._settleOwner();
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
        originals: services.originals,
        shrink: ReportImage.forShare,
        keyBook: tokens,
      );
      services.links = FamilyLinkService(sealed: sealed, relay: services.sharing!.relay, audit: audit, replyIdentity: services._replyIdentity);
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

  bool get appLockEnabled => (settings['appLock'] as bool?) ?? true;

  Future<void> setAppLock(bool on) async {
    settings['appLock'] = on;
    await _saveSettings();
    await audit.append(AuditEntry(
      at: clock(),
      actorId: 'patient:${selfPatientId ?? currentPatientId}',
      patientId: selfPatientId ?? currentPatientId ?? '',
      action: AuditAction.edit,
      detail: on ? 'App lock turned on' : 'App lock turned off',
    ));
  }

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

  /// Saves a photographed paper document: every page is straightened,
  /// shrunk and stripped of metadata, encrypted, and linked to the record.
  Future<HealthRecord> addScanned({required HealthRecord draft, required List<Uint8List> rawPages}) async {
    final pages = <Uint8List>[for (final p in rawPages) await ReportImage.prepare(p)];
    final attachmentId = 'a-${_randomId()}';
    await attachments.save(attachmentId, pages);
    final r = HealthRecord(
      id: draft.id,
      patientId: draft.patientId,
      kind: draft.kind,
      title: draft.title,
      date: draft.date,
      source: RecordSource.smartCapture,
      doctor: draft.doctor,
      facility: draft.facility,
      results: draft.results,
      dose: draft.dose,
      ingredient: draft.ingredient,
      labName: draft.labName,
      sampleDate: draft.sampleDate,
      attachmentId: attachmentId,
    );
    await addRecord(r);
    return r;
  }

  /// The patient's own originals — their phone, their data, no grant.
  Future<List<Uint8List>> originals(HealthRecord r) async => r.attachmentId == null ? const [] : attachments.load(r.attachmentId!);

  Future<void> _saveDemoOriginals(String patientId) async {
    final name = repository.patient(patientId)!.name;
    for (final r in repository.recordsOf(patientId)) {
      if (r.attachmentId == null || r.kind != RecordKind.report) continue;
      final page = DemoReportImages.render(
        lab: r.labName ?? 'Sample lab',
        title: r.title,
        patient: name,
        date: fullDateOf(r.effectiveDate),
        rows: [
          for (final res in r.results)
            (
              res.analyte.replaceAll('_', ' ').toUpperCase(),
              res.value == res.value.roundToDouble() ? res.value.toStringAsFixed(0) : '${res.value}',
              res.unit,
              res.printedLow != null && res.printedHigh != null
                  ? '${res.printedLow}-${res.printedHigh}'
                  : res.printedHigh != null
                      ? '< ${res.printedHigh}'
                      : res.printedLow != null
                          ? '> ${res.printedLow}'
                          : '-',
            ),
        ],
      );
      await attachments.save(r.attachmentId!, [page]);
    }
  }

  static String fullDateOf(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// The patient ticked "still taking" at share time.
  Future<void> confirmMedicines(Set<String> recordIds, DateTime at) async {
    for (final r in records().where((r) => recordIds.contains(r.id))) {
      await repository.add(r.copyWith(patientConfirmedAt: at));
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
      await _saveDemoOriginals(id);
    }
    settings['currentPatientId'] = id;
    settings['selfPatientId'] = id;
    settings['demo'] = demo;
    await _saveSettings();
    await repository.saveCustody(Custody(patientId: id, kind: CustodyKind.self, custodianId: id, relation: 'self'));
    return patient;
  }

  Future<void> updatePatient(Patient p) => repository.savePatient(p);

  bool get isDemo => settings['demo'] == true;

  // ---- family (profiles on this phone) -----------------------------------

  /// The phone owner's own profile, fixed once and stored.
  String? get selfPatientId => settings['selfPatientId'] as String?;

  /// Installs made before family existed never stored the owner. The owner
  /// is the profile nobody else holds custody of — never "whoever is on
  /// screen", which becomes a child the moment the parent switches to them.
  Future<void> _settleOwner() async {
    if (settings['selfPatientId'] != null) return;
    final dependents = {for (final c in repository.custodies) if (c.kind != CustodyKind.self) c.patientId};
    final owner = repository.patients.where((p) => !dependents.contains(p.id)).firstOrNull;
    if (owner == null) return;
    settings['selfPatientId'] = owner.id;
    await _saveSettings();
    if (repository.custodyOf(owner.id) == null) {
      await repository.saveCustody(Custody(patientId: owner.id, kind: CustodyKind.self, custodianId: owner.id, relation: 'self'));
    }
  }
  Patient? get selfPatient => selfPatientId == null ? null : repository.patient(selfPatientId!);

  bool get viewingSelf => currentPatientId == selfPatientId;

  /// Every profile kept on this phone, the owner's first.
  List<Patient> familyOnPhone() {
    final self = selfPatient;
    return [
      ?self,
      for (final c in repository.custodies)
        if (c.patientId != selfPatientId && c.isActive) ?repository.patient(c.patientId),
    ];
  }

  Custody? custodyOf(String patientId) =>
      repository.custodyOf(patientId) ??
      (patientId == selfPatientId ? Custody(patientId: patientId, kind: CustodyKind.self, custodianId: patientId, relation: 'self') : null);

  Future<void> switchTo(String patientId) async {
    if (!familyOnPhone().any((p) => p.id == patientId)) throw const CustodyRefused('That profile is not on this phone.');
    settings['currentPatientId'] = patientId;
    await _saveSettings();
  }

  /// A child's profile, kept on this phone. The phone owner declares they
  /// are the parent; verification (DigiLocker) is not connected yet, and the
  /// app says so wherever the custody is shown.
  Future<Patient> addChild({required String name, required DateTime dob, required Sex sex, required String relation}) async {
    await _settleOwner();
    final self = selfPatient ?? (throw const CustodyRefused('Set up your own profile first.'));
    final at = clock();
    final child = Patient(id: 'p-${_randomId()}', name: name, dateOfBirth: dob, sex: sex);
    if (child.ageAt(at) >= 18) throw const CustodyRefused('An adult keeps their own profile. Use "An adult who wants me to manage" if they ask you to.');
    await repository.savePatient(child);
    await repository.saveCustody(Custody(
      patientId: child.id,
      kind: CustodyKind.childOfParent,
      custodianId: self.id,
      relation: relation,
      method: ConsentMethod.parentDeclaration,
      consentedAt: at,
      statement: '${self.name} declared they are ${child.name}\'s parent.',
    ));
    await audit.append(AuditEntry(at: at, actorId: Actors.patient(self.id), patientId: child.id, action: AuditAction.edit, tokenId: 'family-custody-${child.id}', detail: 'Profile created by ${self.name} (parent)'));
    return child;
  }

  /// An adult who asked the phone owner to keep and share their records.
  /// They confirm in person by typing their own name under the statement.
  Future<Patient> addDelegatingAdult({
    required String name,
    required DateTime dob,
    required Sex sex,
    required String relation,
    required String typedName,
  }) async {
    await _settleOwner();
    final self = selfPatient ?? (throw const CustodyRefused('Set up your own profile first.'));
    String norm(String x) => x.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (norm(typedName) != norm(name)) throw const CustodyRefused('They must type their own name exactly as it is on the profile.');
    final at = clock();
    final adult = Patient(id: 'p-${_randomId()}', name: name, dateOfBirth: dob, sex: sex);
    if (adult.ageAt(at) < 18) throw const CustodyRefused('Under 18: add them as a child instead.');
    await repository.savePatient(adult);
    await repository.saveCustody(Custody(
      patientId: adult.id,
      kind: CustodyKind.delegatedByAdult,
      custodianId: self.id,
      relation: relation,
      method: ConsentMethod.inPersonOnCustodianPhone,
      consentedAt: at,
      statement: Custody.delegationStatement(adultName: name, custodianName: self.name),
      signedName: typedName.trim(),
    ));
    await audit.append(AuditEntry(at: at, actorId: Actors.patient(adult.id), patientId: adult.id, action: AuditAction.grantIssued, tokenId: 'family-custody-${adult.id}', detail: 'Asked ${self.name} to manage their records (confirmed in person)'));
    return adult;
  }

  /// Ends a delegation: nothing more is shared on their behalf, and any
  /// live access given for them is revoked at once.
  Future<void> endDelegation(String patientId) async {
    final c = repository.custodyOf(patientId);
    if (c == null || c.kind != CustodyKind.delegatedByAdult || !c.isActive) return;
    final at = clock();
    for (final g in consent.activeGrantsFor(patientId, at)) {
      if (sharing != null && g.granteeKeyId != null) {
        await sharing!.endAccess(g, at);
      } else {
        consent.revoke(g.id);
      }
    }
    await repository.saveCustody(c.ended(at));
    await audit.append(AuditEntry(at: at, actorId: Actors.patient(c.custodianId), patientId: patientId, action: AuditAction.grantRevoked, tokenId: 'family-custody-$patientId', detail: 'Management ended; nothing more is shared on their behalf'));
    if (currentPatientId == patientId) await switchTo(selfPatientId!);
  }

  /// What the doctor is told about who shared, when it is not the patient
  /// themself: "Anjali Sharma, parent".
  String? sharedByNote() {
    final id = currentPatientId;
    if (id == null || id == selfPatientId) return null;
    final c = custodyOf(id);
    final self = selfPatient;
    if (c == null || self == null) return null;
    return switch (c.kind) {
      CustodyKind.childOfParent => '${self.name}, parent',
      CustodyKind.delegatedByAdult => '${self.name}, at the patient\'s request',
      CustodyKind.self => null,
    };
  }

  /// Who is granting when the current profile shares — and whether they
  /// may. The owner grants for themself; a parent for a child under 18; a
  /// custodian for an adult whose delegation is active.
  String actingGrantor() {
    final id = currentPatientId!;
    final c = custodyOf(id) ?? (throw const CustodyRefused('This profile has no custody record.'));
    final at = clock();
    switch (c.kind) {
      case CustodyKind.self:
        return Actors.patient(id);
      case CustodyKind.childOfParent:
        if (repository.patient(id)!.ageAt(at) >= 18) {
          throw const CustodyRefused('They are 18 now. Only they can share their records.');
        }
        return Actors.patient(c.custodianId);
      case CustodyKind.delegatedByAdult:
        if (!c.isActive) throw const CustodyRefused('They ended your management of their records.');
        return Actors.patient(c.custodianId);
    }
  }

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
    if (r.kind == RecordKind.prescription) await _tellLinkedFamily(r.patientId);
  }

  /// Saves the Emergency ID, and sends the new card to linked family who
  /// were chosen to see it.
  Future<void> saveEmergencyCard(String patientId, EmergencyCard card) async {
    await emergency.save(patientId, card);
    await _tellLinkedFamily(patientId);
  }

  /// Best effort: a save never fails because the relay is unreachable. The
  /// next change, or "Check for updates", tries again.
  Future<void> _tellLinkedFamily(String patientId) async {
    if (patientId != selfPatientId) return;
    try {
      await refreshFamilyLinks();
    } on Object {
      // Offline. The linked copy stays as it was until the next send.
    }
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
    actingGrantor(); // refuses when this profile may not be acted for
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

  // ---- linked adults (P7) -------------------------------------------------

  Future<FamilyInvite> createFamilyInvite() {
    final self = selfPatient ?? (throw const CustodyRefused('Set up your own profile first.'));
    return links!.createInvite(ownerId: self.id, ownerName: self.name, at: clock());
  }

  List<HealthRecord> _activeMedicines(String patientId) =>
      [for (final r in repository.recordsOf(patientId)) if (r.kind == RecordKind.prescription && r.isActiveAt(clock())) r];

  /// On the invited adult's own phone. They choose what the inviter sees.
  Future<FamilyLink> joinFamily({required String code, required bool shareEmergency, required bool shareMedicines}) async {
    final self = selfPatient ?? (throw const CustodyRefused('Set up your own profile first.'));
    return links!.accept(
      ownerId: self.id,
      ownerName: self.name,
      code: code,
      shareEmergency: shareEmergency,
      shareMedicines: shareMedicines,
      emergency: shareEmergency ? await emergency.load(self.id) : null,
      activeMedicines: shareMedicines ? _activeMedicines(self.id) : const [],
      at: clock(),
    );
  }

  /// Sends a fresh copy of what this phone shares to everyone linked.
  Future<void> refreshFamilyLinks() async {
    final self = selfPatient;
    if (links == null || self == null) return;
    final card = await emergency.load(self.id);
    for (final l in await links!.links()) {
      if (!l.iShareEmergency && !l.iShareMedicines) continue;
      await links!.sendUpdate(ownerId: self.id, link: l, emergency: card, activeMedicines: _activeMedicines(self.id), at: clock());
    }
  }

  Future<FamilyLink> changeFamilySharing(FamilyLink link, {required bool emergency, required bool medicines}) async {
    final id = selfPatientId!;
    return links!.changeSharing(
      ownerId: id,
      link: link,
      shareEmergency: emergency,
      shareMedicines: medicines,
      emergency: emergency ? await this.emergency.load(id) : null,
      activeMedicines: medicines ? _activeMedicines(id) : const [],
      at: clock(),
    );
  }

  Future<void> unlinkFamily(FamilyLink link) => links!.unlink(ownerId: selfPatientId!, link: link, at: clock());

  /// Prescriptions for whoever is on screen; family-link messages for the
  /// owner. Returns (prescriptions added, link messages handled, refused).
  Future<(int, int, int)> checkInbox() async {
    final at = clock();
    var (added, handled, refused) = (0, 0, 0);
    if (selfPatientId != null) {
      final (a, h, r) = await sharing!.collectInbox(selfPatientId!, at, handlers: links!.handlers(ownerId: selfPatientId!, at: at));
      (added, handled, refused) = (a.length, h, r);
      if (a.isNotEmpty) await _tellLinkedFamily(selfPatientId!);
    }
    if (currentPatientId != null && currentPatientId != selfPatientId) {
      final (a, _, r) = await sharing!.collectInbox(currentPatientId!, at);
      added += a.length;
      refused += r;
    }
    return (added, handled, refused);
  }

  // ---- export -------------------------------------------------------------

  /// A complete, unencrypted copy of the profile on screen, for the patient
  /// to keep or pass on. The export is logged before the file exists (#13).
  /// A parent may export a child's records; the same rule as sharing decides.
  Future<RecordExport> exportCurrent() async {
    final id = currentPatientId!;
    final grantor = actingGrantor();
    final at = clock();
    await audit.append(AuditEntry(at: at, actorId: grantor, patientId: id, action: AuditAction.export, detail: 'records, Emergency ID, originals and access log'));
    final records = repository.recordsOf(id);
    return RecordExport(
      patient: repository.patient(id)!,
      records: records,
      profile: repository.profileOf(id),
      emergency: await emergency.load(id),
      audit: audit.entriesFor(id),
      originals: {
        for (final r in records)
          if (r.attachmentId != null)
            if (await originals(r).then((p) => p, onError: (_) => const <Uint8List>[]) case final pages when pages.isNotEmpty) r.id: pages,
      },
      at: at,
    );
  }

  // ---- erasure (DPDP §12) -------------------------------------------------

  /// Deletes this profile's records, grants, Emergency ID and backup. The
  /// erasure itself stays as the only entry in the log.
  Future<void> eraseProfile({required String account}) async {
    final id = currentPatientId!;
    if (id == selfPatientId && familyOnPhone().length > 1) {
      // Erasing the owner would strand a child's or parent's records on a
      // phone nobody can open for them. They go first, deliberately.
      throw const CustodyRefused('Remove the other family profiles on this phone first.');
    }
    final at = clock();
    for (final r in repository.recordsOf(id)) {
      if (r.attachmentId != null) await attachments.delete(r.attachmentId!);
    }
    // Linked adults are told, so they delete what this phone shared.
    for (final l in id == selfPatientId ? await links?.links() ?? const <FamilyLink>[] : const <FamilyLink>[]) {
      try {
        await links!.unlink(ownerId: id, link: l, at: at);
      } on Object {
        // Offline: the link is removed here, but their copy stays until they unlink.
      }
    }
    await repository.eraseFor(id);
    consent.eraseFor(id);
    await emergency.erase(id);
    await vault.erase(account);
    await audit.eraseFor(
      id,
      AuditEntry(at: at, actorId: 'patient:$id', patientId: id, action: AuditAction.erasure, detail: 'records, grants, Emergency ID and backup deleted'),
    );
    if (id != selfPatientId && selfPatientId != null) {
      settings['currentPatientId'] = selfPatientId;
      await _saveSettings();
      await flush();
      return;
    }
    settings.remove('currentPatientId');
    settings.remove('selfPatientId');
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
