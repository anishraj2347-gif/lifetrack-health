import 'package:lifetrack_protocol/lifetrack_protocol.dart';

/// The doctor's own register, kept encrypted in this browser. It holds who
/// shared and when, the prescriptions this doctor wrote, and their private
/// consult notes — not the patient's shared records, which close when access
/// ends.
class PatientEntry {
  PatientEntry({
    required this.key,
    required this.name,
    this.sex,
    this.age,
    this.lifeTrackId,
    required this.firstSeen,
    required this.lastShared,
    this.shares = 1,
    this.levels = const [],
  });

  /// Stable per patient: their LifeTrack ID, else their reply mailbox.
  final String key;
  String name;
  String? sex;
  int? age;
  String? lifeTrackId;
  final DateTime firstSeen;
  DateTime lastShared;
  int shares;
  List<String> levels;

  String get sexAge => [
        if (sex == 'female') 'F' else if (sex == 'male') 'M',
        if (age != null) '$age y',
      ].join(' · ');

  Map<String, Object?> toJson() => {
        'key': key,
        'name': name,
        'sex': sex,
        'age': age,
        'lifeTrackId': lifeTrackId,
        'firstSeen': firstSeen.toIso8601String(),
        'lastShared': lastShared.toIso8601String(),
        'shares': shares,
        'levels': levels,
      };

  static PatientEntry fromJson(Map<String, Object?> j) => PatientEntry(
        key: j['key']! as String,
        name: j['name']! as String,
        sex: j['sex'] as String?,
        age: j['age'] as int?,
        lifeTrackId: j['lifeTrackId'] as String?,
        firstSeen: DateTime.parse(j['firstSeen']! as String),
        lastShared: DateTime.parse(j['lastShared']! as String),
        shares: (j['shares'] as int?) ?? 1,
        levels: [for (final l in (j['levels'] as List?) ?? const []) l as String],
      );
}

/// A prescription this doctor signed and sent.
class RxEntry {
  RxEntry({required this.patientKey, required this.patientName, required this.patientLine, required this.rx});
  final String patientKey;
  final String patientName;
  final String patientLine;
  final SignedPrescription rx;

  Map<String, Object?> toJson() => {'patientKey': patientKey, 'patientName': patientName, 'patientLine': patientLine, 'rx': rx.toJson()};

  static RxEntry fromJson(Map<String, Object?> j) => RxEntry(
        patientKey: j['patientKey']! as String,
        patientName: j['patientName']! as String,
        patientLine: (j['patientLine'] as String?) ?? '',
        rx: SignedPrescription.fromJson((j['rx']! as Map).cast()),
      );
}

/// The doctor's private note for one visit. Never sent to the patient or to
/// LifeTrack.
class ConsultNote {
  ConsultNote({
    required this.id,
    required this.patientKey,
    required this.at,
    this.complaint = '',
    this.findings = '',
    this.advice = '',
    this.followUp,
  });

  final String id;
  final String patientKey;
  final DateTime at;
  final String complaint;
  final String findings;
  final String advice;
  final DateTime? followUp;

  static const maxField = 2000;

  bool get isEmpty => complaint.trim().isEmpty && findings.trim().isEmpty && advice.trim().isEmpty && followUp == null;

  Map<String, Object?> toJson() => {
        'id': id,
        'patientKey': patientKey,
        'at': at.toIso8601String(),
        'complaint': complaint,
        'findings': findings,
        'advice': advice,
        'followUp': followUp?.toIso8601String(),
      };

  static ConsultNote fromJson(Map<String, Object?> j) => ConsultNote(
        id: j['id']! as String,
        patientKey: j['patientKey']! as String,
        at: DateTime.parse(j['at']! as String),
        complaint: (j['complaint'] as String?) ?? '',
        findings: (j['findings'] as String?) ?? '',
        advice: (j['advice'] as String?) ?? '',
        followUp: j['followUp'] == null ? null : DateTime.parse(j['followUp']! as String),
      );
}
