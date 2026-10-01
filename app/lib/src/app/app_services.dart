import 'dart:async';
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
import '../crypto/shamir.dart';
import '../crypto/vault_codec.dart';
import '../export/record_export.dart';
import '../model/vital_reading.dart';
import '../reminders/custom_reminder.dart';
import '../reminders/reminder_plan.dart';
import '../vaccines/uip_schedule.dart';
import '../model/abha.dart';
import '../family/family_link.dart';
import '../family/family_role.dart';
import '../identity/identity_verifier.dart';
import '../identity/lifetrack_ids.dart';
import '../security/screen_privacy.dart';
import '../share/access_requests.dart';
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

  // ---- identity (DigiLocker) ----------------------------------------------

  /// When true, a profile is created only from a DigiLocker verification:
  /// Aadhaar for everyone, a birth certificate for a newborn (user decision,
  /// 1 Oct 2026). Sample profiles are exempt; they are not people.
  bool identityRequired = false;

  /// Runs DigiLocker checks through the LifeTrack service; null without it.
  IdentityVerifier? verifier;

  /// Opens DigiLocker and returns its signed confirmation. [purpose] is
  /// `self` (their own Aadhaar) or `newborn` (the owner's DigiLocker birth
  /// certificate; needs the owner to be verified).
  Future<IdentityAttestation> verifyWithDigiLocker({required String purpose, required Future<void> Function(Uri url) openUrl}) async {
    final v = verifier ?? (throw const VerificationFailed('DigiLocker checks are not set up in this build.'));
    IdentityAttestation? parent;
    if (purpose == 'newborn') {
      parent = selfPatient?.verification;
      if (parent == null || parent.method != IdentityMethod.aadhaarDigiLocker) {
        throw const VerificationFailed('Verify your own profile with Aadhaar first. A newborn is added from your DigiLocker.');
      }
    }
    return runVerification(verifier: v, trust: sharing!.trust, purpose: purpose, parent: parent, openUrl: openUrl);
  }

  /// Registers the new profile's LifeTrack ID with its verification; if the
  /// person already has one, the new profile is removed again.
  Future<void> _registerVerified(String patientId, {required bool isOwner}) async {
    if (ids == null) return;
    try {
      await ids!.ensure(patientId);
    } on PersonExists {
      await repository.eraseFor(patientId);
      if (isOwner) {
        settings
          ..remove('currentPatientId')
          ..remove('selfPatientId');
        await _saveSettings();
      } else {
        settings['currentPatientId'] = selfPatientId;
        await _saveSettings();
      }
      rethrow;
    } on Object {
      // Offline: registered on the next start or "Check for updates".
    }
  }

  /// Marks a profile made before verification as verified. Name, date of
  /// birth and sex become what DigiLocker confirmed.
  Future<void> applyVerification(String patientId, IdentityAttestation v) async {
    final p = repository.patient(patientId)!;
    await repository.savePatient(p.withVerification(v));
    await audit.append(AuditEntry(at: clock(), actorId: 'patient:$patientId', patientId: patientId, action: AuditAction.edit, detail: 'Identity verified: ${v.method.label}'));
  }

  /// Each profile's 12-digit LifeTrack ID, when the service is configured.
  LifeTrackIds? ids;

  /// Doctors' requests that arrived by LifeTrack ID.
  AccessRequestInbox? requests;

  String? lifeTrackIdOf(String patientId) => ids?.idOf(patientId);

  /// Registers an ID for every profile that has none. Best effort.
  Future<void> assignLifeTrackIds() async => ids?.ensureAll([for (final p in familyOnPhone()) p.id]);

  Future<List<PendingRequest>> pendingRequests() async =>
      requests == null || currentPatientId == null ? const [] : requests!.pending(currentPatientId!, clock());

  Future<void> declineRequest(PendingRequest p) => requests!.decline(p, actorId: actingGrantor(), at: clock());

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
    bool backupEnabled = true,
    IdDirectory Function()? idDirectoryOverride,
    IdentityVerifier Function()? verifierOverride,
    bool identityRequired = false,
    bool demoTools = false,
    ReminderScheduler? reminderScheduler,
    ScreenPrivacy? screenPrivacy,
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
      emergency: EmergencyCardStore(bytes, audit, sealed),
      vault: BackupVault(remote: remote, audit: audit, params: kdf),
      cloud: cloudFactory(repository: repository, consent: consent, audit: audit, access: access, clock: now),
      settings: settings,
      attachments: AttachmentStore(bytes, deviceKey),
    );
    services.backupEnabled = backupEnabled;
    services.identityRequired = identityRequired;
    services.demoTools = demoTools;
    services.reminderScheduler = reminderScheduler;
    services.screenPrivacy = screenPrivacy;
    unawaited(screenPrivacy?.set(services.screenPrivacyEnabled));
    services._doseLog = ((await sealed.read(_doseLogBlob) as Map?) ?? {}).cast<String, Object?>();
    services._vaccines = ((await sealed.read(_vaccinesBlob) as Map?) ?? {}).cast<String, Object?>();
    services._custom = ((await sealed.read(_customBlob) as Map?) ?? {}).cast<String, Object?>();
    services._backup = ((await sealed.read(_backupBlob) as Map?) ?? {}).cast<String, Object?>();
    consent.evictFinished(now());
    await services._settleOwner();
    unawaited(services.refreshReminders());
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
        lifeTrackIdOf: services.lifeTrackIdOf,
        keyBook: tokens,
      );
      services.ids = LifeTrackIds(
        sealed: sealed,
        directory: idDirectoryOverride?.call() ?? HttpIdDirectory(baseUrl: Uri.parse(share.relayUrl!)),
        replyIdentity: services._replyIdentity,
        attestationOf: (pid) => repository.patient(pid)?.verification,
      );
      services.verifier = verifierOverride?.call() ?? HttpIdentityVerifier(baseUrl: Uri.parse(share.relayUrl!));
      await services.ids!.load();
      services.requests = AccessRequestInbox(sealed: sealed, audit: audit, relay: services.sharing!.relay, trust: services.sharing!.trust);
      unawaited(services.assignLifeTrackIds());
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

  ScreenPrivacy? screenPrivacy;

  /// Screenshots, recordings and the Recent apps preview blanked. On unless
  /// the patient turns it off; demo builds start with it off so the screen
  /// can be recorded for a demonstration.
  bool get screenPrivacyEnabled => (settings['screenPrivacy'] as bool?) ?? !demoTools;

  Future<void> setScreenPrivacy(bool on) async {
    settings['screenPrivacy'] = on;
    await _saveSettings();
    await screenPrivacy?.set(on);
    await audit.append(AuditEntry(
      at: clock(),
      actorId: 'patient:${selfPatientId ?? currentPatientId}',
      patientId: selfPatientId ?? currentPatientId ?? '',
      action: AuditAction.edit,
      detail: on ? 'Screen privacy turned on' : 'Screen privacy turned off',
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
      originalFormat: draft.originalFormat,
    );
    await addRecord(r);
    return r;
  }

  /// The patient's own originals — their phone, their data, no grant.
  Future<List<Uint8List>> originals(HealthRecord r) async => r.attachmentId == null ? const [] : attachments.load(r.attachmentId!);

  // ---- medicine reminders -------------------------------------------------

  /// Puts reminders on the phone; null in tests and builds without them.
  ReminderScheduler? reminderScheduler;

  ReminderSettings get reminderSettings =>
      settings['reminders'] is Map ? ReminderSettings.fromJson((settings['reminders']! as Map).cast()) : const ReminderSettings();

  /// Saves the patient's choice. Turning reminders on asks the phone for
  /// permission to notify; refused, they stay off and this returns false.
  Future<bool> setReminders(ReminderSettings next) async {
    if (next.on && !reminderSettings.on) {
      final ok = await reminderScheduler?.requestPermission() ?? false;
      if (!ok) return false;
    }
    settings['reminders'] = next.toJson();
    await _saveSettings();
    await refreshReminders();
    return true;
  }

  /// The next fortnight's reminders, from every profile on this phone:
  /// medicines by dose, and children's vaccinations on their due day.
  List<PlannedReminder> reminderPlan() {
    final now = clock();
    final meds = planReminders(people: [for (final p in familyOnPhone()) (p, repository.recordsOf(p.id))], settings: reminderSettings, now: now);
    final (h, m) = reminderSettings.times[DoseSlot.morning]!;
    var id = 1000;
    final shots = <PlannedReminder>[
      for (final p in familyOnPhone())
        if (p.ageAt(now) < 18)
          for (final (d, st, _) in vaccineStatus(p.dateOfBirth, vaccinesOf(p.id), now))
            if (st == VaccineStatus.upcoming && d.dueDate(p.dateOfBirth).difference(now).inDays < 14)
              PlannedReminder(
                id: id++,
                at: DateTime(d.dueDate(p.dateOfBirth).year, d.dueDate(p.dateOfBirth).month, d.dueDate(p.dateOfBirth).day, h, m),
                slot: DoseSlot.morning,
                items: const [],
                vaccine: (p.name.split(' ').first, d.name),
              ),
    ];
    final mine = planCustomReminders(people: [for (final p in familyOnPhone()) (p, customRemindersOf(p.id))], now: now);
    return [...meds, ...shots.where((r) => r.at.isAfter(now)), ...mine]..sort((a, b) => a.at.compareTo(b.at));
  }

  // ---- children's vaccinations (UIP) ---------------------------------------

  static const _vaccinesBlob = 'vaccinations';
  Map<String, Object?> _vaccines = {};

  Map<String, VaccineGiven> vaccinesOf(String patientId) => {
        for (final e in ((_vaccines[patientId] as Map?) ?? const {}).entries) e.key as String: VaccineGiven.fromJson((e.value as Map).cast()),
      };

  /// Marks a dose given (or, with null, not given). Logged and backed up.
  Future<void> markVaccine(String patientId, String code, VaccineGiven? given) async {
    final m = ((_vaccines[patientId] as Map?) ?? {}).cast<String, Object?>();
    given == null ? m.remove(code) : m[code] = given.toJson();
    _vaccines[patientId] = m;
    await sealed.write(_vaccinesBlob, _vaccines);
    final dose = uipSchedule.where((d) => d.code == code).firstOrNull?.name ?? code;
    await audit.append(AuditEntry(
      at: clock(),
      actorId: actingGrantor(),
      patientId: patientId,
      action: AuditAction.edit,
      detail: given == null ? '$dose marked not given' : '$dose given on ${given.on.toIso8601String().substring(0, 10)}${given.place == null ? '' : ' at ${given.place}'}',
    ));
    await refreshReminders();
    await _backUpQuietly();
  }

  /// Re-plans after anything that could change a dose. Never throws.
  Future<void> refreshReminders() async {
    final sched = reminderScheduler;
    if (sched == null) return;
    try {
      final st = reminderSettings;
      await sched.replaceAll(st.on ? reminderPlan().take(maxScheduled).toList() : const [], showNames: st.showNames, selfPatientId: selfPatientId);
    } on Object {
      // The schedule stays as it was; the next change tries again.
    }
  }

  /// Android keeps at most 500 alarms per app; stay well under.
  static const maxScheduled = 400;

  // ---- the patient's own reminders -----------------------------------------

  static const _customBlob = 'custom_reminders';
  Map<String, Object?> _custom = {};

  List<CustomReminder> customRemindersOf(String patientId) => [
        for (final j in (_custom[patientId] as List?) ?? const []) CustomReminder.fromJson((j as Map).cast()),
      ]..sort((a, b) => a.times.first.$1 * 60 + a.times.first.$2 - (b.times.first.$1 * 60 + b.times.first.$2));

  static String newReminderId() => 'r-${_randomId()}';

  /// Adds or replaces (same id) a reminder. Turns reminders on — making one
  /// is asking to be reminded — and returns false if notifications are not
  /// allowed.
  Future<bool> saveCustomReminder(CustomReminder r) async {
    final problem = r.problem();
    if (problem != null) throw ArgumentError(problem);
    final list = customRemindersOf(r.patientId);
    final i = list.indexWhere((x) => x.id == r.id);
    i < 0 ? list.add(r) : list[i] = r;
    _custom[r.patientId] = [for (final x in list) x.toJson()];
    await sealed.write(_customBlob, _custom);
    await audit.append(AuditEntry(at: clock(), actorId: actingGrantor(), patientId: r.patientId, action: AuditAction.edit, detail: '${i < 0 ? 'reminder added' : 'reminder changed'}: ${r.title}'));
    await _backUpQuietly();
    if (!reminderSettings.on) return setReminders(reminderSettings.copyWith(on: true));
    await refreshReminders();
    return true;
  }

  Future<void> deleteCustomReminder(CustomReminder r) async {
    final list = customRemindersOf(r.patientId)..removeWhere((x) => x.id == r.id);
    _custom[r.patientId] = [for (final x in list) x.toJson()];
    await sealed.write(_customBlob, _custom);
    await audit.append(AuditEntry(at: clock(), actorId: actingGrantor(), patientId: r.patientId, action: AuditAction.edit, detail: 'reminder deleted: ${r.title}'));
    await refreshReminders();
    await _backUpQuietly();
  }

  /// Today's times of the patient's own reminders, for the profile on screen.
  List<(int, int, CustomReminder)> todaysCustom() {
    final id = currentPatientId;
    if (id == null) return const [];
    final now = clock();
    return [
      for (final c in customRemindersOf(id))
        if (c.occursOn(now))
          for (final (h, m) in c.times) (h, m, c),
    ]..sort((a, b) => a.$1 * 60 + a.$2 - (b.$1 * 60 + b.$2));
  }

  static String _customKey(CustomReminder c, int h, int m) => '${c.id}@$h:$m';

  bool customDoneToday(CustomReminder c, int h, int m) =>
      (((_doseLog[_day(clock())] as Map?)?['custom'] as List?) ?? const []).contains(_customKey(c, h, m));

  Future<void> markCustomDone(CustomReminder c, int h, int m, bool done) =>
      _logToday('custom', _customKey(c, h, m), done);

  static const _doseLogBlob = 'dose_log';
  Map<String, Object?> _doseLog = {};
  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Today's doses for the profile on screen: (slot, record, how many).
  List<(DoseSlot, HealthRecord, int)> todaysDoses() {
    final id = currentPatientId;
    if (id == null) return const [];
    final now = clock();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59);
    return [
      for (final slot in DoseSlot.values)
        for (final r in repository.recordsOf(id))
          if (r.kind == RecordKind.prescription && r.dose != null && r.isActiveAt(now) && !r.date.isAfter(endOfDay) && slot.countIn(r.dose!) > 0)
            (slot, r, slot.countIn(r.dose!)),
    ];
  }

  bool takenToday(DoseSlot slot, String recordId) =>
      (((_doseLog[_day(clock())] as Map?)?[slot.name] as List?) ?? const []).contains(recordId);

  /// Ticks a dose taken (or not). Kept on this phone only, for 60 days.
  Future<void> markTaken(DoseSlot slot, String recordId, bool taken) => _logToday(slot.name, recordId, taken);

  Future<void> _logToday(String key, String item, bool done) async {
    final day = _day(clock());
    final d = ((_doseLog[day] as Map?) ?? {}).cast<String, Object?>();
    final list = ((d[key] as List?) ?? const []).cast<String>().toSet();
    done ? list.add(item) : list.remove(item);
    d[key] = list.toList();
    _doseLog[day] = d;
    final cutoff = _day(clock().subtract(const Duration(days: 60)));
    _doseLog.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    await sealed.write(_doseLogBlob, _doseLog);
  }

  // ---- home readings (BP & sugar diary) ----------------------------------

  List<VitalReading> vitalsOf(String patientId) => repository.vitalsOf(patientId);

  /// Saves a reading for the profile on screen. Stays on this phone unless
  /// the patient shares home readings or backs up personal data (#6).
  Future<void> addVital(VitalReading v) async {
    await repository.addVital(v);
    await audit.append(AuditEntry(at: clock(), actorId: actingGrantor(), patientId: v.patientId, action: AuditAction.edit, dataClass: DataClass.vitals, detail: 'home reading added: ${v.display}'));
    await _backUpQuietly();
  }

  Future<void> deleteVital(VitalReading v) async {
    await repository.removeVital(v.id);
    await audit.append(AuditEntry(at: clock(), actorId: actingGrantor(), patientId: v.patientId, action: AuditAction.edit, dataClass: DataClass.vitals, detail: 'home reading deleted: ${v.display}'));
    await _backUpQuietly();
  }

  /// Corrects a record the patient entered. Signed records are refused:
  /// their content is the lab's or doctor's, not the patient's to change.
  Future<void> updateRecord(HealthRecord r) async {
    final old = repository.recordsOf(r.patientId).where((x) => x.id == r.id).firstOrNull ?? (throw StateError('No such record.'));
    if (!old.editable) throw StateError('LifeTrack keeps signed records as they were issued.');
    await repository.add(r);
    await audit.append(AuditEntry(
      at: clock(),
      actorId: actingGrantor(),
      patientId: r.patientId,
      action: AuditAction.edit,
      dataClass: r.dataClass,
      detail: 'corrected "${old.title}"${old.title == r.title ? '' : ' → "${r.title}"'}',
    ));
    if (r.kind == RecordKind.prescription) {
      await _tellLinkedFamily(r.patientId);
      await refreshReminders();
    }
    await _backUpQuietly();
  }

  /// Removes a record and its original pages from this phone (and from the
  /// backup on the next run). Shares already sent are not recalled by this.
  Future<void> deleteRecord(HealthRecord r) async {
    await repository.remove(r.id);
    if (r.attachmentId != null) await attachments.delete(r.attachmentId!);
    await audit.append(AuditEntry(
      at: clock(),
      actorId: actingGrantor(),
      patientId: r.patientId,
      action: AuditAction.edit,
      dataClass: r.dataClass,
      detail: 'deleted "${r.title}"',
    ));
    if (r.kind == RecordKind.prescription) {
      await _tellLinkedFamily(r.patientId);
      await refreshReminders();
    }
    await _backUpQuietly();
  }

  /// Demo builds only (`LT_DEMO_TOOLS=true`): shows the add-sample button.
  bool demoTools = false;

  /// Fills the profile on screen with the sample records (photos stamped
  /// SAMPLE) and a sample allergy/condition list, for demonstrations.
  Future<void> addSampleRecords() async {
    final id = currentPatientId!;
    await repository.addAll(DemoData.records(id));
    await repository.saveProfile(id, DemoData.profile(clock()));
    await _saveDemoOriginals(id);
    await refreshReminders();
    await audit.append(AuditEntry(at: clock(), actorId: 'patient:$id', patientId: id, action: AuditAction.edit, detail: 'Sample records added for a demonstration'));
    await _backUpQuietly();
  }

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

  Future<Patient> createProfile({required String name, required DateTime dob, required Sex sex, bool demo = false, IdentityAttestation? verification}) async {
    if (identityRequired && !demo && verification == null) throw const CustodyRefused('Verify with DigiLocker (Aadhaar) to create a profile.');
    if (verification != null && verification.method != IdentityMethod.aadhaarDigiLocker) throw const CustodyRefused('Your own profile is verified with your Aadhaar.');
    final id = 'p-${_randomId()}';
    final base = demo ? DemoData.patient(id) : Patient(id: id, name: name, dateOfBirth: dob, sex: sex);
    final patient = verification == null ? base : base.withVerification(verification);
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
    if (verification != null) {
      await audit.append(AuditEntry(at: clock(), actorId: 'patient:$id', patientId: id, action: AuditAction.edit, detail: 'Identity verified: ${verification.method.label}'));
      await _registerVerified(id, isOwner: true);
    } else {
      await assignLifeTrackIds();
    }
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

  /// The head of family's view: who each person is to the head. A child's
  /// role stays son or daughter — only their parent can hold it.
  Future<void> setRole(String patientId, FamilyRole role) async {
    final c = repository.custodyOf(patientId);
    if (c == null || c.kind == CustodyKind.self) throw const CustodyRefused('The head of family has no role to set.');
    if (c.kind == CustodyKind.childOfParent && !FamilyRole.forChild.contains(role)) {
      throw const CustodyRefused('A child on this phone is your son or daughter.');
    }
    final old = c.relation;
    await repository.saveCustody(c.withRelation(role.name));
    await audit.append(AuditEntry(at: clock(), actorId: Actors.patient(selfPatientId!), patientId: patientId, action: AuditAction.edit, detail: 'Role changed: ${FamilyRole.describe(old)} → ${role.label.toLowerCase()}'));
    await _backUpQuietly();
  }

  Future<void> switchTo(String patientId) async {
    if (!familyOnPhone().any((p) => p.id == patientId)) throw const CustodyRefused('That profile is not on this phone.');
    settings['currentPatientId'] = patientId;
    await _saveSettings();
  }

  /// A child's profile, kept on this phone. The phone owner declares they
  /// are the parent; verification (DigiLocker) is not connected yet, and the
  /// app says so wherever the custody is shown.
  Future<Patient> addChild({required String name, required DateTime dob, required Sex sex, required String relation, IdentityAttestation? verification}) async {
    await _settleOwner();
    final self = selfPatient ?? (throw const CustodyRefused('Set up your own profile first.'));
    if (!FamilyRole.forChild.contains(FamilyRole.parse(relation))) {
      throw const CustodyRefused('A child under 18 is added only by their parent, as your son or daughter. Their own parent can add them on their phone.');
    }
    if (identityRequired && verification == null) {
      throw const CustodyRefused('Verify the child with DigiLocker: their own Aadhaar, or your DigiLocker birth certificate for a newborn.');
    }
    final byCertificate = verification?.method == IdentityMethod.birthCertificateDigiLocker;
    if (byCertificate && verification!.parentSubjectHash != self.verification?.subjectHash) {
      throw const CustodyRefused('That birth certificate came from someone else\'s DigiLocker.');
    }
    final at = clock();
    final base = Patient(id: 'p-${_randomId()}', name: name, dateOfBirth: dob, sex: sex);
    final child = verification == null ? base : base.withVerification(verification);
    if (child.ageAt(at) >= 18) throw const CustodyRefused('An adult keeps their own profile. Use "An adult who wants me to manage" if they ask you to.');
    await repository.savePatient(child);
    await repository.saveCustody(Custody(
      patientId: child.id,
      kind: CustodyKind.childOfParent,
      custodianId: self.id,
      relation: relation,
      method: byCertificate ? ConsentMethod.birthCertificateDigiLocker : ConsentMethod.parentDeclaration,
      consentedAt: at,
      statement: byCertificate
          ? '${child.name}\'s birth certificate, shared from ${self.name}\'s DigiLocker, names ${self.name} as a parent.'
          : '${self.name} declared they are ${child.name}\'s parent.',
    ));
    await audit.append(AuditEntry(at: at, actorId: Actors.patient(self.id), patientId: child.id, action: AuditAction.edit, tokenId: 'family-custody-${child.id}', detail: 'Profile created by ${self.name} (parent)${verification == null ? '' : ' · ${verification.method.label}'}'));
    if (verification != null) {
      await _registerVerified(child.id, isOwner: false);
    } else {
      await assignLifeTrackIds();
    }
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
    IdentityAttestation? verification,
  }) async {
    await _settleOwner();
    final self = selfPatient ?? (throw const CustodyRefused('Set up your own profile first.'));
    if (!FamilyRole.forAdult.contains(FamilyRole.parse(relation)) && FamilyRole.parse(relation) != FamilyRole.spouse) {
      throw const CustodyRefused('Pick who they are to you.');
    }
    if (identityRequired && verification?.method != IdentityMethod.aadhaarDigiLocker) {
      throw const CustodyRefused('They verify with their own Aadhaar through DigiLocker, on this phone.');
    }
    if (verification != null) {
      name = verification.name;
      dob = verification.dateOfBirth;
      sex = Patient.sexFromGender(verification.gender);
    }
    String norm(String x) => x.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (norm(typedName) != norm(name)) throw const CustodyRefused('They must type their own name exactly as it is on the profile.');
    final at = clock();
    final adult = Patient(id: 'p-${_randomId()}', name: name, dateOfBirth: dob, sex: sex, verification: verification);
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
    if (verification != null) {
      await _registerVerified(adult.id, isOwner: false);
    } else {
      await assignLifeTrackIds();
    }
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
    if (r.kind == RecordKind.prescription) {
      await _tellLinkedFamily(r.patientId);
      await refreshReminders();
    }
    await _backUpQuietly();
  }

  /// Saves the Emergency ID, and sends the new card to linked family who
  /// were chosen to see it.
  Future<void> saveEmergencyCard(String patientId, EmergencyCard card) async {
    await emergency.save(patientId, card);
    await _tellLinkedFamily(patientId);
    await _backUpQuietly();
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

  /// Doctors this phone has shared with: registration number → name, as
  /// their verified certificate showed it (from the grant entries in the log).
  Map<String, String> doctorNames() {
    final re = RegExp(r'^(.+?) \(([^()]+)\) · ');
    return {
      for (final p in familyOnPhone())
        for (final e in audit.entriesFor(p.id))
          if (e.action == AuditAction.grantIssued)
            if (re.firstMatch(e.detail ?? '') case final m?) m.group(2)!: m.group(1)!,
    };
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
  /// Checks every profile's mailbox on this phone: prescriptions, family-link
  /// messages (the owner's), and doctors' requests by LifeTrack ID.
  Future<(int, int, int)> checkInbox() async {
    final at = clock();
    await assignLifeTrackIds();
    var (added, handled, refused) = (0, 0, 0);
    for (final p in familyOnPhone()) {
      final handlers = {
        if (p.id == selfPatientId) ...links!.handlers(ownerId: p.id, at: at),
        'access_request': requests!.handler(patientId: p.id, lifeTrackId: lifeTrackIdOf(p.id), at: at),
      };
      final (a, h, r) = await sharing!.collectInbox(p.id, at, handlers: handlers);
      added += a.length;
      handled += h;
      refused += r;
      if (a.isNotEmpty && p.id == selfPatientId) await _tellLinkedFamily(p.id);
    }
    if (added > 0) {
      await _backUpQuietly();
      await refreshReminders();
    }
    return (added, handled, refused);
  }

  // ---- ABHA -------------------------------------------------------------

  /// Adds, replaces or (with null) removes the ABHA of the profile on screen.
  /// Whoever may act for the profile may do this — the same rule as sharing.
  Future<void> setAbha({String? number, String? address}) async {
    final id = currentPatientId!;
    final actor = actingGrantor();
    final p = repository.patient(id)!;
    Abha? next;
    if (number != null) {
      final n = Abha.parseNumber(number) ?? (throw const FormatException('An ABHA number has 14 digits.'));
      final a = (address == null || address.trim().isEmpty)
          ? null
          : Abha.parseAddress(address) ?? (throw const FormatException('An ABHA address looks like name@abdm.'));
      next = Abha(number: n, address: a, addedAt: clock());
    }
    await repository.savePatient(p.withAbha(next));
    await audit.append(AuditEntry(
      at: clock(),
      actorId: actor,
      patientId: id,
      action: AuditAction.edit,
      detail: next == null ? 'ABHA removed' : 'ABHA ${next.masked} added (typed in, not verified)',
    ));
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
      vitals: repository.vitalsOf(id),
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

  // ---- backup -------------------------------------------------------------

  /// False when this build has no backup service configured; the UI then
  /// says so instead of offering it.
  bool backupEnabled = true;

  static const _backupBlob = 'backup_state';
  Map<String, Object?> _backup = {};

  /// The account code, when this phone backs up; null otherwise.
  String? get backupAccount => _backup['account'] as String?;
  DateTime? get lastBackupAt => _backup['at'] == null ? null : DateTime.parse(_backup['at']! as String);
  String? get lastBackupError => _backup['error'] as String?;
  bool get backupIncludesNotes => (_backup['notes'] as bool?) ?? false;

  /// The recovery code this phone keeps (one of three).
  String? get phoneRecoveryCode => _backup['phoneShare'] as String?;

  VaultKeys get _keys => VaultKeys.fromJson((_backup['keys']! as Map).cast());
  Future<void> _saveBackup() => sealed.write(_backupBlob, _backup);

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // Crockford: no I, L, O, U

  static String _code(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => _alphabet[r.nextInt(32)]).join();
  }

  /// A generated password: 20 characters, 100 bits. Generated, not chosen,
  /// because the server holds what an offline guess at a weak one needs.
  static String newBackupPassword() => [for (var i = 0; i < 4; i++) _code(5)].join('-');

  /// Accepts the password as typed: any case, spaces or dashes.
  static String normalisePassword(String typed) {
    final c = typed.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '').replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
    return [for (var i = 0; i < c.length; i += 5) c.substring(i, min(i + 5, c.length))].join('-');
  }

  static String normaliseAccount(String typed) {
    final c = typed.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    final body = c.startsWith('LT') ? c.substring(2) : c;
    return body.length == 10 ? 'LT-${body.substring(0, 5)}-${body.substring(5)}' : typed.trim().toUpperCase();
  }

  /// Everything on this phone that a backup carries. Personal notes only
  /// when the patient chose them; grants, links and the access log never —
  /// they belong to this phone's history.
  Future<Map<String, Object?>> _snapshot() async {
    final includeNotes = backupIncludesNotes;
    final patients = repository.patients;
    final records = [for (final p in patients) ...repository.recordsOf(p.id)].where((r) => r.backedUpByDefault || includeNotes).toList();
    return {
      'format': 1,
      'selfPatientId': selfPatientId,
      'patients': [for (final p in patients) p.toJson()],
      'custody': [for (final c in repository.custodies) c.toJson()],
      'profiles': {for (final p in patients) p.id: repository.profileOf(p.id).toJson()},
      'emergency': {for (final p in patients) p.id: (await emergency.load(p.id)).toJson()},
      'records': [for (final r in records) r.toJson()],
      'lifetrackIds': ids?.export() ?? const {},
      'vaccinations': _vaccines,
      // Home readings, like notes, only when the patient opted in (#6).
      if (includeNotes) 'customReminders': _custom,
      if (includeNotes) 'vitals': [for (final p in patients) for (final v in repository.vitalsOf(p.id)) v.toJson()],
      'originals': {
        for (final r in records)
          if (r.attachmentId != null)
            if (await attachments.load(r.attachmentId!).then((p) => p, onError: (_) => const <Uint8List>[]) case final pages when pages.isNotEmpty)
              r.attachmentId!: [for (final pg in pages) base64Encode(pg)],
      },
    };
  }

  String _describe(Map<String, Object?> snap) =>
      '${(snap['records']! as List).length} records, ${(snap['originals']! as Map).length} originals, ${(snap['patients']! as List).length} profiles';

  /// Turns backup on. Returns the recovery kit, shown once: the app keeps
  /// neither the password nor the two codes it hands out.
  Future<RecoveryKit> setUpBackup({bool includeNotes = false}) async {
    final self = selfPatient ?? (throw const CustodyRefused('Set up your own profile first.'));
    final account = 'LT-${_code(5)}-${_code(5)}';
    final password = newBackupPassword();
    _backup = {'notes': includeNotes};
    final snap = await _snapshot();
    final setup = await vault.create(account: account, password: password, body: snap, auditPatientId: self.id, detail: _describe(snap), at: clock());
    _backup = {
      'account': account,
      'keys': setup.keys.toJson(),
      'notes': includeNotes,
      'phoneShare': setup.shares[0].encode(),
      'at': clock().toIso8601String(),
    };
    await _saveBackup();
    return RecoveryKit(account: account, password: password, printCode: setup.shares[1].encode(), contactCode: setup.shares[2].encode());
  }

  /// Sends the current records to the backup. Throws when the service is
  /// unreachable; [_backUpQuietly] is the no-throw form used after changes.
  Future<void> backUpNow() async {
    final account = backupAccount;
    if (account == null) return;
    final snap = await _snapshot();
    try {
      await vault.update(account: account, keys: _keys, body: snap, auditPatientId: selfPatientId!, detail: _describe(snap), at: clock());
      _backup['at'] = clock().toIso8601String();
      _backup.remove('error');
    } on Object catch (e) {
      _backup['error'] = e is VaultError ? e.patientMessage : 'Could not reach the backup service.';
      await _saveBackup();
      rethrow;
    }
    await _saveBackup();
  }

  Future<void> _backUpQuietly() async {
    if (backupAccount == null) return;
    try {
      await backUpNow();
    } on Object {
      // Recorded in lastBackupError; the next change or "Back up now" retries.
    }
  }

  Future<void> setBackupIncludesNotes(bool on) async {
    _backup['notes'] = on;
    await _saveBackup();
    await _backUpQuietly();
  }

  /// Deletes the backup from the server (DPDP §12) and stops backing up.
  Future<void> turnOffBackup() async {
    final account = backupAccount;
    if (account == null) return;
    await vault.erase(account, _keys);
    _backup = {};
    await _saveBackup();
    await audit.append(AuditEntry(at: clock(), actorId: 'patient:$selfPatientId', patientId: selfPatientId ?? '', action: AuditAction.erasure, detail: 'backup deleted from the server'));
  }

  /// On a phone with no profile yet: brings back every profile, record,
  /// original and Emergency ID, and keeps backing up to the same account.
  /// Give either [password] or two [codes].
  Future<int> restoreFromBackup({required String account, String? password, List<String>? codes}) async {
    if (repository.patients.isNotEmpty) throw const CustodyRefused('Restore works only on a phone with no profile yet.');
    final acct = normaliseAccount(account);
    final at = clock();
    final VaultRestore got;
    if (password != null) {
      got = await vault.restoreWithPassword(account: acct, password: normalisePassword(password), auditPatientId: 'restore', at: at);
    } else {
      got = await vault.restoreWithShares(account: acct, shares: [for (final c in codes!) Share.decode(c)], auditPatientId: 'restore', at: at);
    }
    final b = got.body;
    for (final p in (b['patients']! as List).cast<Map>()) {
      await repository.savePatient(Patient.fromJson(p.cast()));
    }
    for (final c in (b['custody']! as List).cast<Map>()) {
      await repository.saveCustody(Custody.fromJson(c.cast()));
    }
    for (final MapEntry(:key, :value) in (b['profiles']! as Map).cast<String, Object?>().entries) {
      await repository.saveProfile(key, ClinicalProfile.fromJson((value! as Map).cast()));
    }
    for (final MapEntry(:key, :value) in (b['emergency']! as Map).cast<String, Object?>().entries) {
      final card = EmergencyCard.fromJson((value! as Map).cast());
      if (!card.isEmpty) await emergency.save(key, card);
    }
    for (final MapEntry(:key, :value) in (b['originals']! as Map).cast<String, Object?>().entries) {
      await attachments.save(key, [for (final pg in (value! as List).cast<String>()) base64Decode(pg)]);
    }
    final records = [for (final r in (b['records']! as List).cast<Map>()) HealthRecord.fromJson(r.cast())];
    await repository.addAll(records);
    for (final v in (b['vitals'] as List?) ?? const []) {
      await repository.addVital(VitalReading.fromJson((v as Map).cast()));
    }
    if (b['customReminders'] is Map) {
      _custom = (b['customReminders']! as Map).cast<String, Object?>();
      await sealed.write(_customBlob, _custom);
    }
    if (b['vaccinations'] is Map) {
      _vaccines = (b['vaccinations']! as Map).cast<String, Object?>();
      await sealed.write(_vaccinesBlob, _vaccines);
    }
    if (ids != null && b['lifetrackIds'] is Map) {
      await ids!.import((b['lifetrackIds']! as Map).cast());
    }
    final self = b['selfPatientId'] as String? ?? repository.patients.first.id;
    settings['selfPatientId'] = self;
    settings['currentPatientId'] = self;
    await _saveSettings();
    _backup = {
      'account': acct,
      'keys': got.keys.toJson(),
      'notes': records.any((r) => r.kind == RecordKind.note),
      'at': at.toIso8601String(),
    };
    await _saveBackup();
    await assignLifeTrackIds(); // the same IDs now point at this phone
    await refreshReminders();
    await audit.append(AuditEntry(
      at: at,
      actorId: Actors.patient(self),
      patientId: self,
      action: AuditAction.vaultRestore,
      detail: '${records.length} records restored to this phone from backup $acct via ${password != null ? 'password' : 'recovery codes'}',
    ));
    return records.length;
  }

  // ---- erasure (DPDP §12) -------------------------------------------------

  /// Deletes this profile's records, grants, Emergency ID and backup. The
  /// erasure itself stays as the only entry in the log.
  Future<void> eraseProfile() async {
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
    try {
      await ids?.remove(id);
    } on Object {
      // Offline: the ID's entry stays on the server until erased again.
    }
    await repository.eraseFor(id);
    if (_vaccines.remove(id) != null) await sealed.write(_vaccinesBlob, _vaccines);
    if (_custom.remove(id) != null) await sealed.write(_customBlob, _custom);
    consent.eraseFor(id);
    await emergency.erase(id);
    if (id == selfPatientId) {
      // The owner's erasure deletes the backup on the server too.
      try {
        await turnOffBackup();
      } on Object {
        _backup = {};
        await _saveBackup();
      }
    }
    await audit.eraseFor(
      id,
      AuditEntry(at: at, actorId: 'patient:$id', patientId: id, action: AuditAction.erasure, detail: 'records, grants, Emergency ID and backup deleted'),
    );
    if (id != selfPatientId && selfPatientId != null) {
      settings['currentPatientId'] = selfPatientId;
      await _saveSettings();
      await flush();
      await _backUpQuietly();
      await refreshReminders();
      return;
    }
    settings.remove('currentPatientId');
    settings.remove('selfPatientId');
    settings.remove('demo');
    settings.remove('reminders');
    await _saveSettings();
    await flush();
    await refreshReminders();
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Shown once when backup is turned on. LifeTrack keeps none of it.
class RecoveryKit {
  const RecoveryKit({required this.account, required this.password, required this.printCode, required this.contactCode});
  final String account;
  final String password;

  /// Two of the three recovery codes; the third stays on the phone. Any two
  /// open the backup without the password.
  final String printCode;
  final String contactCode;
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
