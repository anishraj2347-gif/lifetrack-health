import 'dart:convert';
import 'dart:typed_data';

import '../audit/audit_log.dart';
import '../model/health_record.dart';
import '../storage/byte_store.dart';

/// The one card readable without unlocking the phone (blueprint §5.3).
///
/// Deliberately outside the sealed vault. Hygiene rules, because a stranger
/// can read it: fixed fields only, no free-text notes, length-bounded, no
/// date of birth or address. Only the patient edits it; nothing under
/// `lib/src/ai/` may import this file.
class EmergencyCard {
  const EmergencyCard({
    this.bloodType = '',
    this.allergies = '',
    this.conditions = '',
    this.medications = '',
    this.contactName = '',
    this.contactRelation = '',
    this.contactPhone = '',
  });

  static const maxFieldLength = 120;
  static const bloodTypes = ['A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−', ''];

  final String bloodType;
  final String allergies;
  final String conditions;
  final String medications;
  final String contactName;
  final String contactRelation;
  final String contactPhone;

  bool get isEmpty => [bloodType, allergies, conditions, medications, contactName].every((f) => f.trim().isEmpty);

  /// Problems that stop the card being saved.
  List<String> validate() => [
        if (!bloodTypes.contains(bloodType)) 'Blood type must be one of ${bloodTypes.where((b) => b.isNotEmpty).join(', ')}.',
        for (final (label, v) in [
          ('Allergies', allergies),
          ('Conditions', conditions),
          ('Medications', medications),
          ('Contact name', contactName),
          ('Relation', contactRelation),
        ])
          if (v.length > maxFieldLength) '$label is longer than $maxFieldLength characters.',
        if (contactPhone.isNotEmpty && !RegExp(r'^\+?[0-9 ]{8,16}$').hasMatch(contactPhone))
          'Contact phone should be digits only.',
      ];

  Map<String, Object?> toJson() => {
        'blood': bloodType,
        'allergies': allergies,
        'conditions': conditions,
        'meds': medications,
        'contactName': contactName,
        'contactRelation': contactRelation,
        'contactPhone': contactPhone,
      };

  static EmergencyCard fromJson(Map<String, Object?> j) => EmergencyCard(
        bloodType: (j['blood'] as String?) ?? '',
        allergies: (j['allergies'] as String?) ?? '',
        conditions: (j['conditions'] as String?) ?? '',
        medications: (j['meds'] as String?) ?? '',
        contactName: (j['contactName'] as String?) ?? '',
        contactRelation: (j['contactRelation'] as String?) ?? '',
        contactPhone: (j['contactPhone'] as String?) ?? '',
      );
}

class EmergencyCardStore {
  EmergencyCardStore(this.bytes, this.audit);

  static String _blob(String patientId) => 'emergency_card_$patientId';
  static const unauthenticatedActor = 'unauthenticated:lock_screen';

  final ByteStore bytes;
  final AuditLog audit;

  Future<EmergencyCard> load(String patientId) async {
    final raw = await bytes.read(_blob(patientId));
    if (raw == null) return const EmergencyCard();
    return EmergencyCard.fromJson((jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>());
  }

  /// A read from the lock screen. Audited, because it is the one read that
  /// needs no grant.
  Future<EmergencyCard> readFromLockScreen(String patientId, DateTime at) async {
    await audit.append(AuditEntry(
      at: at,
      actorId: unauthenticatedActor,
      patientId: patientId,
      action: AuditAction.emergencyRead,
      dataClass: DataClass.emergencyCard,
    ));
    return load(patientId);
  }

  Future<void> save(String patientId, EmergencyCard card) async {
    final problems = card.validate();
    if (problems.isNotEmpty) throw ArgumentError(problems.join(' '));
    await bytes.write(_blob(patientId), Uint8List.fromList(utf8.encode(jsonEncode(card.toJson()))));
  }

  Future<void> erase(String patientId) => bytes.delete(_blob(patientId));
}
