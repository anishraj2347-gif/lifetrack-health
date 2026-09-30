import '../model/clinical_profile.dart';
import '../model/health_record.dart';
import '../model/patient.dart';
import 'sealed_store.dart';

/// The patient's records and profiles, sealed under the device key.
///
/// The whole set is rewritten on every change; [ByteStore.write]'s atomicity
/// contract is what makes that safe.
class RecordRepository {
  RecordRepository._(this._store, this._records, this._patients, this._profiles);

  static const recordsBlob = 'records';
  static const patientsBlob = 'patients';
  static const profilesBlob = 'clinical_profiles';

  final SealedStore _store;
  final List<HealthRecord> _records;
  final Map<String, Patient> _patients;
  final Map<String, ClinicalProfile> _profiles;

  static Future<RecordRepository> open(SealedStore store) async {
    final r = await store.read(recordsBlob) as List?;
    final p = await store.read(patientsBlob) as List?;
    final c = (await store.read(profilesBlob) as Map?)?.cast<String, Object?>() ?? const {};
    return RecordRepository._(
      store,
      [for (final e in r ?? const []) HealthRecord.fromJson((e as Map).cast<String, Object?>())],
      {
        for (final e in p ?? const [])
          (e as Map)['id']! as String: Patient.fromJson(e.cast<String, Object?>()),
      },
      {for (final MapEntry(:key, :value) in c.entries) key: ClinicalProfile.fromJson((value! as Map).cast())},
    );
  }

  bool get isEmpty => _records.isEmpty && _patients.isEmpty;

  Patient? patient(String id) => _patients[id];
  List<Patient> get patients => List.unmodifiable(_patients.values);

  /// Unfiltered read. Package-private by convention: only [RecordAccess] and
  /// the patient's own screens (who need no grant to read their own phone)
  /// call it. Agents never do — `plane_boundary_test.dart` enforces that.
  List<HealthRecord> recordsOf(String patientId) =>
      (_records.where((r) => r.patientId == patientId).toList()..sort((a, b) => b.date.compareTo(a.date)));

  /// Unfiltered, like [recordsOf]: the patient's own screens and
  /// `RecordAccess` only.
  ClinicalProfile profileOf(String patientId) => _profiles[patientId] ?? const ClinicalProfile();

  Future<void> saveProfile(String patientId, ClinicalProfile profile) async {
    _profiles[patientId] = profile;
    await _store.write(profilesBlob, {for (final MapEntry(:key, :value) in _profiles.entries) key: value.toJson()});
  }

  Future<void> savePatient(Patient p) async {
    _patients[p.id] = p;
    await _store.write(patientsBlob, [for (final x in _patients.values) x.toJson()]);
  }

  Future<void> add(HealthRecord r) async {
    _records.removeWhere((x) => x.id == r.id);
    _records.add(r);
    await _flush();
  }

  Future<void> addAll(Iterable<HealthRecord> rs) async {
    final ids = {for (final r in rs) r.id};
    _records.removeWhere((x) => ids.contains(x.id));
    _records.addAll(rs);
    await _flush();
  }

  Future<void> eraseFor(String patientId) async {
    _records.removeWhere((r) => r.patientId == patientId);
    _patients.remove(patientId);
    _profiles.remove(patientId);
    await _flush();
    await _store.write(profilesBlob, {for (final MapEntry(:key, :value) in _profiles.entries) key: value.toJson()});
    await _store.write(patientsBlob, [for (final x in _patients.values) x.toJson()]);
  }

  Future<void> _flush() => _store.write(recordsBlob, [for (final r in _records) r.toJson()]);
}
