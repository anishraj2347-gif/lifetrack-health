import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../audit/audit_log.dart';
import '../app_lock.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../../model/custody.dart';
import '../widgets/family_bar.dart';
import '../widgets/parts.dart';
import 'data_rights_screen.dart';
import 'add_family_screen.dart';
import 'emergency_screen.dart';
import 'family_link_screens.dart';
import 'share_screen.dart' show describeActor, dataClassNames, iconForActor;

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final initials = p.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: LT.band,
            child: Text(initials, style: LT.label.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: LT.title.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
              if (s.isDemo) const Badge2('Sample records', tone: BadgeTone.caution) else const Badge2('On this phone', tone: BadgeTone.trace),
            ]),
          ),
        ]),
      ),
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _link(context, LucideIcons.heartPulse, 'Emergency ID', 'What a paramedic sees', const EmergencyScreen()),
          _link(context, LucideIcons.history, 'Access log', '${s.auditEntries().length} entries on this phone', const AuditScreen()),
          _link(context, LucideIcons.scale, 'Your data and your rights', 'What is held where, and how to erase it', const DataRightsScreen(), last: true),
        ]),
      ),
      if (AppLockGate.of(context) case final lock? when lock.available)
        ShadCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            const IconTile(LucideIcons.lock),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('App lock', style: LT.label),
                SizedBox(height: 4),
                Text('Fingerprint, face or phone PIN when LifeTrack opens', style: LT.small),
              ]),
            ),
            Switch(
              value: s.appLockEnabled,
              onChanged: (v) async {
                if (await lock.setEnabled(v) && context.mounted) AppScope.changed(context);
              },
            ),
          ]),
        ),
      const Eyebrow('Family on this phone'),
      for (final f in s.familyOnPhone().where((f) => f.id != s.selfPatientId))
        () {
          final c = s.custodyOf(f.id)!;
          return ShadCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(backgroundColor: LT.raised, child: Text(FamilyBar.initials(f.name), style: const TextStyle(color: LT.ink, fontWeight: FontWeight.w600))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(FamilyBar.authorityLine(c), style: LT.small),
                  if (c.consentedAt != null) Text('Since ${fullDate(c.consentedAt!)}', style: LT.small.copyWith(fontSize: 12)),
                  if (c.kind == CustodyKind.delegatedByAdult)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SlabButton('End management', variant: ButtonVariant.outline, onPressed: () async {
                        await s.endDelegation(f.id);
                        if (context.mounted) AppScope.changed(context);
                      }),
                    ),
                ]),
              ),
            ]),
          );
        }(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: SlabButton('Add a family member', variant: ButtonVariant.outline, icon: LucideIcons.userPlus, onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddFamilyScreen()));
          if (context.mounted) AppScope.changed(context);
        }),
      ),
      const LinkedAdultsSection(),
      const Eyebrow('Where your records are'),
      const Note(
        'On this phone only, encrypted under a key in its secure hardware. The encrypted backup service is not live in this version, so there is no copy anywhere else — if this phone is lost or reset, these records are gone.',
        icon: LucideIcons.cloudOff,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 28),
      ),
    ]);
  }

  Widget _link(BuildContext context, IconData icon, String title, String sub, Widget page, {bool last = false}) => InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
          if (context.mounted) AppScope.changed(context);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: LT.rule))),
          child: Row(children: [
            IconTile(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: LT.label),
                const SizedBox(height: 4),
                Text(sub, style: LT.small),
              ]),
            ),
            const Icon(LucideIcons.chevronRight, size: 18, color: LT.inactive),
          ]),
        ),
      );
}

/// Who opened what. The app has no way to edit or delete an entry; the only
/// removal is erasing the whole profile, which leaves the erasure as the
/// first entry. That is the claim, and it is the whole claim — the copy does
/// not promise more than the code does.
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  static String _verb(AuditAction a) => switch (a) {
        AuditAction.view => 'read',
        AuditAction.edit => 'changed',
        AuditAction.denied => 'was refused',
        AuditAction.grantIssued => 'gave access',
        AuditAction.grantRevoked => 'revoked access',
        AuditAction.cloudEgress => 'sent a de-identified summary off this phone',
        AuditAction.clinicalShare => 'shared records, encrypted to one doctor',
        AuditAction.prescriptionReceived => 'added a signed prescription',
        AuditAction.emergencyRead => 'opened the Emergency ID',
        AuditAction.vaultBackup => 'backed up',
        AuditAction.vaultRestore => 'restored from backup',
        AuditAction.erasure => 'erased the profile',
        AuditAction.export => 'exported an unencrypted copy of the records',
      };

  @override
  Widget build(BuildContext context) {
    final entries = AppScope.of(context).auditEntries();
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        const Masthead(eyebrow: 'Access log', title: 'Who opened what'),
        const Note('Every read, change and permission is recorded here, on this phone. LifeTrack has no way to edit or remove an entry; erasing your profile is the only thing that clears it.', icon: LucideIcons.history),
        const SizedBox(height: 14),
        if (entries.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Nothing yet.', style: LT.lede)),
        for (final (i, e) in entries.indexed)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 56,
                child: Column(children: [
                  Container(width: 1, height: 8, color: i == 0 ? Colors.transparent : LT.rule),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: e.action == AuditAction.denied || e.action == AuditAction.emergencyRead ? const Color(0xFFFFF7ED) : LT.band,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconForActor(e.actorId), size: 15, color: e.action == AuditAction.denied || e.action == AuditAction.emergencyRead ? LT.signal : LT.ink2),
                  ),
                  Expanded(child: Container(width: 1, color: i == entries.length - 1 ? Colors.transparent : LT.rule)),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 20, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${describeActor(e.actorId)} ${_verb(e.action)}${e.dataClass == null ? '' : ' · ${dataClassNames[e.dataClass]}'}',
                      style: LT.label.copyWith(fontSize: 14.5, color: e.action == AuditAction.denied || e.action == AuditAction.emergencyRead ? LT.signal : LT.ink),
                    ),
                    if (e.detail != null) ...[const SizedBox(height: 2), Text(e.detail!, style: LT.small)],
                    const SizedBox(height: 2),
                    Text(dateTime(e.at), style: LT.small.copyWith(fontSize: 12, color: LT.inactive)),
                  ]),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 28),
      ]),
    );
  }
}
