import '../../consent/consent_token.dart';
import '../../consent/record_access.dart';
import '../../model/health_record.dart';
import '../../model/patient.dart';
import '../insight.dart';
import 'deterministic_insights.dart';

/// Plane A's reader: obtains records only through `RecordAccess` under its
/// own actor and the grant the patient approved, then runs the pure engine.
class InsightEngine {
  InsightEngine(this.access);

  final RecordAccess access;

  Future<InsightRun> runFor({required Patient patient, required String tokenId, required DateTime at}) async {
    final reports = await access.read(
      tokenId: tokenId,
      actorId: Actors.planeA,
      patientId: patient.id,
      dataClass: DataClass.reports,
      purpose: GrantPurpose.onDeviceInsights,
      at: at,
    );
    final prescriptions = await access.read(
      tokenId: tokenId,
      actorId: Actors.planeA,
      patientId: patient.id,
      dataClass: DataClass.prescriptions,
      purpose: GrantPurpose.onDeviceInsights,
      at: at,
    );
    return DeterministicInsights.run(patient: patient, records: [...reports, ...prescriptions], at: at);
  }
}
