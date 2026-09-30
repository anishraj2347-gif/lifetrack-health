import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/audit/log_view.dart';
import 'package:lifetrack/src/consent/consent_token.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/health_record.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  final at = DateTime(2026, 10, 1, 9);
  AuditEntry e(String actor, AuditAction a, {String? token, DataClass? dc, String? detail}) =>
      AuditEntry(at: at, actorId: actor, patientId: 'p', action: a, tokenId: token, dataClass: dc, detail: detail);

  test('each kind of entry lands in one view', () {
    expect(e('patient:p', AuditAction.clinicalShare, token: 'grant-p-doctor-MH1-x').topic, LogView.doctors);
    expect(e('doctor:MH1', AuditAction.view, dc: DataClass.reports).topic, LogView.doctors);
    expect(e('patient:p', AuditAction.grantRevoked, token: 'grant-p-doctor-MH1-x', detail: 'ended by patient').topic, LogView.doctors);
    expect(e(Actors.planeA, AuditAction.view, dc: DataClass.reports, token: 'grant-agent-p').topic, LogView.insights);
    expect(e('patient:p', AuditAction.grantIssued, token: 'grant-agent-p').topic, LogView.insights);
    expect(e('patient:p', AuditAction.grantIssued, token: 'family-link-ab').topic, LogView.family);
    expect(e('family:Vikram', AuditAction.grantRevoked, token: 'family-link-ab').topic, LogView.family);
    expect(e('unauthenticated:lock_screen', AuditAction.emergencyRead, dc: DataClass.emergencyCard).topic, LogView.emergency);
    expect(e('patient:p', AuditAction.edit, dc: DataClass.reports, detail: 'added "HbA1c"').topic, LogView.you);
    expect(e('patient:p', AuditAction.export).topic, LogView.you);
  });

  test('Refused gathers denials from every view; All shows everything', () {
    final denied = e('doctor:MH1', AuditAction.denied, dc: DataClass.personalNotes);
    expect(denied.topic, LogView.doctors);
    expect(denied.shownIn(LogView.refused), isTrue);
    expect(denied.shownIn(LogView.all), isTrue);
    expect(e('patient:p', AuditAction.edit).shownIn(LogView.refused), isFalse);
  });

  test('real flows are sorted by what they are, not by their wording', () async {
    final s = await AppServices.open(
      bytes: InMemoryByteStore(),
      deviceKey: SecretKey(List.filled(32, 8)),
      remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(),
      cloudFactory: defaultCloud,
      clock: () => at,
    );
    await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    final child = await s.addChild(name: 'Aarav', dob: DateTime(2019), sex: Sex.male, relation: 'son');
    expect(s.audit.entriesFor(child.id).single.topic, LogView.family);
    await s.enableInsights();
    await s.runInsights();
    await s.emergency.readFromLockScreen(s.selfPatientId!, at);
    await s.addRecord(HealthRecord(id: 'r', patientId: s.selfPatientId!, kind: RecordKind.note, title: 'n', date: at, source: RecordSource.smartCapture));
    final topics = s.audit.entriesFor(s.selfPatientId!).map((x) => x.topic).toSet();
    expect(topics, containsAll([LogView.insights, LogView.emergency, LogView.you]));
    await s.saveEmergencyCard(s.selfPatientId!, const EmergencyCard(bloodType: 'O+'));
  });
}
