import '../consent/consent_token.dart';
import '../model/health_record.dart';
import 'audit_log.dart';

/// The access log's views. Each entry belongs to exactly one topic; the
/// Refused view cuts across them.
enum LogView { all, doctors, insights, family, emergency, you, refused }

extension LogViewOf on AuditEntry {
  /// Decided from who acted, what happened and which grant it rests on —
  /// never from the wording of [detail].
  LogView get topic {
    final t = tokenId ?? '';
    if (action == AuditAction.emergencyRead || dataClass == DataClass.emergencyCard) return LogView.emergency;
    if (t.startsWith('family-') || actorId.startsWith('family:')) return LogView.family;
    if (actorId.startsWith('doctor:') ||
        action == AuditAction.clinicalShare ||
        action == AuditAction.prescriptionReceived ||
        t.contains('-doctor-') ||
        (detail ?? '').startsWith('doctor:')) {
      return LogView.doctors;
    }
    if (Actors.isAgent(actorId) || action == AuditAction.cloudEgress || t.startsWith('grant-agent-') || t.startsWith('grant-cloud-')) {
      return LogView.insights;
    }
    return LogView.you;
  }

  bool shownIn(LogView v) => switch (v) {
        LogView.all => true,
        LogView.refused => action == AuditAction.denied,
        _ => topic == v,
      };
}
