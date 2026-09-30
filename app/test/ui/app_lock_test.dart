import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/app/app_services.dart';
import 'package:lifetrack/src/audit/audit_log.dart';
import 'package:lifetrack/src/crypto/key_derivation.dart';
import 'package:lifetrack/src/emergency/emergency_card.dart';
import 'package:lifetrack/src/model/patient.dart';
import 'package:lifetrack/src/security/unlocker.dart';
import 'package:lifetrack/src/storage/byte_store.dart';
import 'package:lifetrack/src/ui/lifetrack_app.dart';
import 'package:lifetrack/src/vault/backup_vault.dart';

class FakeUnlocker implements Unlocker {
  FakeUnlocker({this.hasLock = true});
  bool hasLock;
  bool answer = true;
  int asked = 0;
  @override
  Future<bool> available() async => hasLock;
  @override
  Future<bool> unlock(String reason) async {
    asked++;
    return answer;
  }
}

void main() {
  var now = DateTime(2026, 10, 1, 9);
  late AppServices services;

  Future<void> start(WidgetTester tester, FakeUnlocker u) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      services = await AppServices.open(
        bytes: InMemoryByteStore(),
        deviceKey: SecretKey(List.filled(32, 5)),
        remote: InMemoryRemoteVaultStore(),
        kdf: KdfParams.weakForTests(),
        cloudFactory: defaultCloud,
        clock: () => now,
      );
      await services.createProfile(name: 'Anjali Sharma', dob: DateTime(1984), sex: Sex.female);
      await services.emergency.save(services.selfPatientId!, const EmergencyCard(bloodType: 'B+', allergies: 'Penicillin'));
    });
    await tester.pumpWidget(LifeTrackApp(boot: () async => services, unlocker: u));
    await tester.pumpAndSettle();
  }

  setUp(() => now = DateTime(2026, 10, 1, 9));

  testWidgets('opens locked and asks at once; a refusal keeps it locked', (tester) async {
    final u = FakeUnlocker()..answer = false;
    await start(tester, u);
    expect(u.asked, 1);
    expect(find.text('LifeTrack is locked'), findsOneWidget);
    expect(find.text('Anjali Sharma'), findsNothing);
    u.answer = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('LifeTrack is locked'), findsNothing);
  });

  testWidgets('the Emergency ID opens from the lock, read-only, and the read is logged', (tester) async {
    final u = FakeUnlocker()..answer = false;
    await start(tester, u);
    await tester.tap(find.text('Emergency ID'));
    await tester.pumpAndSettle();
    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.text('Edit card'), findsNothing);
    expect(services.audit.entriesFor(services.selfPatientId!).any((e) => e.actorId == EmergencyCardStore.unauthenticatedActor && e.action == AuditAction.emergencyRead), isTrue);
  });

  testWidgets('a phone with no screen lock opens straight in', (tester) async {
    final u = FakeUnlocker(hasLock: false);
    await start(tester, u);
    expect(u.asked, 0);
    expect(find.text('LifeTrack is locked'), findsNothing);
  });

  testWidgets('after a minute away it locks again, closing any open screen', (tester) async {
    final u = FakeUnlocker();
    await start(tester, u);
    await tester.tap(find.bySemanticsLabel('Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emergency ID'));
    await tester.pumpAndSettle();
    expect(find.text('Edit card'), findsOneWidget);

    u.answer = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Edit card'), findsOneWidget, reason: 'a short switch away does not lock');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('LifeTrack is locked'), findsOneWidget);
    expect(find.text('Edit card'), findsNothing);
  });

  testWidgets('turning the lock off needs the phone lock first', (tester) async {
    final u = FakeUnlocker();
    await start(tester, u);
    await tester.tap(find.bySemanticsLabel('Me'));
    await tester.pumpAndSettle();
    u.answer = false;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(services.appLockEnabled, isTrue);
    u.answer = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(services.appLockEnabled, isFalse);
  });
}
