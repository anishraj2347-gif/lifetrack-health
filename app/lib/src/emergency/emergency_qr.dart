import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import 'emergency_card.dart';

/// The Emergency ID as plain text for a QR: any phone camera shows it, with
/// no app and no internet. Only the card's own fields, the name and the
/// LifeTrack ID — no records. Empty fields are left out.
String emergencyQrText({
  required String name,
  required EmergencyCard card,
  String? lifeTrackId,
  String? abhaMasked,
  required DateTime updated,
}) {
  final contact = [card.contactName, card.contactRelation, card.contactPhone].where((x) => x.trim().isNotEmpty).join(', ');
  final lines = [
    'EMERGENCY ID — LifeTrack',
    'Name: $name',
    if (lifeTrackId != null) 'LifeTrack ID: ${LifeTrackId.display(lifeTrackId)}',
    if (card.bloodType.isNotEmpty) 'Blood group: ${card.bloodType}',
    if (card.allergies.trim().isNotEmpty) 'ALLERGIES: ${card.allergies.trim()}',
    if (card.conditions.trim().isNotEmpty) 'Conditions: ${card.conditions.trim()}',
    if (card.medications.trim().isNotEmpty) 'Medicines: ${card.medications.trim()}',
    if (contact.isNotEmpty) 'Emergency contact: $contact',
    if (abhaMasked != null) 'ABHA: $abhaMasked',
    'Card as of ${updated.toIso8601String().substring(0, 10)}',
  ];
  return lines.join('\n');
}
