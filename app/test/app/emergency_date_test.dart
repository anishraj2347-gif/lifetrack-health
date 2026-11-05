import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/emergency/emergency_qr.dart';
import 'package:lifetrack/src/model/clinical_profile.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/app_scope.dart';
import 'package:lifetrack/src/ui/screens/emergency_screen.dart';
import 'package:lifetrack/src/ui/theme.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

void main() {
  var now = DateTime(2026, 3, 1, 9);
  Future<AppServices> open([InMemoryByteStore? b]) async {
    final s = await AppServices.open(
      bytes: b ?? InMemoryByteStore(), deviceKey: SecretKey(List.filled(32, 7)), remote: InMemoryRemoteVaultStore(),
      kdf: KdfParams.weakForTests(), cloudFactory: defaultCloud, clock: () => now,
    );
    if (s.currentPatientId == null) await s.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
    return s;
  }

  setUp(() => now = DateTime(2026, 3, 1, 9));

  test('the card remembers when it was edited, across a restart', () async {
    final bytes = InMemoryByteStore();
    final s = await open(bytes);
    await s.saveEmergencyCard(s.selfPatientId!, const EmergencyCard(bloodType: 'B+'));
    now = DateTime(2026, 11, 6);
    final again = await open(bytes);
    final card = await again.emergency.load(again.selfPatientId!);
    expect(card.updatedAt, DateTime(2026, 3, 1, 9));
    expect(emergencyQrText(name: 'A', card: card), contains('Card last edited 2026-03-01'));
  });

  test('saving without a change keeps the date; a real change moves it', () async {
    final s = await open();
    final me = s.selfPatientId!;
    await s.saveEmergencyCard(me, const EmergencyCard(bloodType: 'B+'));
    now = DateTime(2026, 6, 1);
    await s.saveEmergencyCard(me, const EmergencyCard(bloodType: 'B+'));
    expect((await s.emergency.load(me)).updatedAt, DateTime(2026, 3, 1, 9));
    await s.saveEmergencyCard(me, const EmergencyCard(bloodType: 'O+'));
    expect((await s.emergency.load(me)).updatedAt, DateTime(2026, 6, 1));
  });

  test('a change to the allergy list dates the card; other profile edits do not', () async {
    final s = await open();
    final me = s.selfPatientId!;
    await s.saveEmergencyCard(me, const EmergencyCard(bloodType: 'B+'));
    now = DateTime(2026, 6, 1);
    await s.saveClinicalProfile(const ClinicalProfile(conditions: [Condition(name: 'Asthma')]));
    expect((await s.emergency.load(me)).updatedAt, DateTime(2026, 3, 1, 9));
    await s.saveClinicalProfile(const ClinicalProfile(allergies: [Allergy(substance: 'Latex')]));
    expect((await s.emergency.load(me)).updatedAt, DateTime(2026, 6, 1));
  });

  test('a card from before the date was kept says so, and never prints today', () async {
    final s = await open();
    final me = s.selfPatientId!;
    await s.sealed.write('emergency_card_$me', const EmergencyCard(bloodType: 'B+').toJson());
    final card = await s.emergency.load(me);
    expect(card.updatedAt, isNull);
    final qr = emergencyQrText(name: 'A', card: card);
    expect(qr, contains('Card last edited: date not recorded'));
    expect(qr, isNot(contains('2026')));
  });

  test('the date is stored in the fixed fields and stays through a JSON round trip', () {
    final c = EmergencyCard.fromJson((jsonDecode(jsonEncode(EmergencyCard(bloodType: 'A+', updatedAt: DateTime(2026, 2, 3)).toJson())) as Map).cast());
    expect(c.updatedAt, DateTime(2026, 2, 3));
    expect(EmergencyCard.fromJson(const {'updated': 'not a date'}).updatedAt, isNull);
  });

  testWidgets('the card shows the real date', (t) async {
    final s = (await t.runAsync(() async {
      final x = await open();
      await x.saveEmergencyCard(x.selfPatientId!, const EmergencyCard(bloodType: 'B+'));
      now = DateTime(2026, 11, 6);
      return x;
    }))!;
    await t.pumpWidget(AppScope(services: s, child: MaterialApp(theme: LT.theme(), home: const EmergencyScreen())));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(find.text('Last edited 1 Mar 2026'), findsOneWidget);
  });
}
