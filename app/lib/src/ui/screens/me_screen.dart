import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../audit/audit_log.dart';
import '../../audit/log_view.dart';
import '../app_lock.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../../model/custody.dart';
import '../widgets/digilocker_step.dart';
import '../widgets/family_bar.dart';
import '../widgets/parts.dart';
import 'data_rights_screen.dart';
import 'abha_screen.dart';
import 'add_family_screen.dart';
import 'family_overview_screen.dart';
import '../../app/app_version.dart';
import 'backup_screens.dart';
import 'reminders_screen.dart';
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
              if (s.isDemo)
                const Badge2('Sample records', tone: BadgeTone.caution)
              else if (p.verification case final v?)
                Badge2('Verified · ${v.method.label}', tone: BadgeTone.trace)
              else
                const Badge2('Not verified', tone: BadgeTone.outline),
              if (s.lifeTrackIdOf(p.id) case final id?) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('LifeTrack ID copied.')));
                  },
                  child: Text('LifeTrack ID  ${LifeTrackId.display(id)}', style: LT.small.copyWith(color: LT.ink, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                ),
              ] else if (s.ids != null) ...[
                const SizedBox(height: 8),
                const Text('LifeTrack ID: assigned when the phone reaches LifeTrack', style: LT.small),
              ],
            ]),
          ),
        ]),
      ),
      if (!p.isVerified && !s.isDemo && s.verifier != null && p.id == s.selfPatientId)
        ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Verify your profile', style: LT.label),
            const SizedBox(height: 4),
            const Text('This profile was made before DigiLocker verification. Verify with your Aadhaar; your name, date of birth and gender become what DigiLocker confirms.', style: LT.small),
            const SizedBox(height: 8),
            DigiLockerStep(
              purpose: 'self',
              buttonLabel: 'Verify with DigiLocker (Aadhaar)',
              onVerified: (v) async {
                await s.applyVerification(p.id, v);
                if (context.mounted) AppScope.changed(context);
              },
            ),
          ]),
        ),
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _link(context, LucideIcons.heartPulse, 'Emergency ID', 'What a paramedic sees', const EmergencyScreen()),
          _link(context, LucideIcons.idCard, 'ABHA health ID', p.abha == null ? 'Optional · not added' : '${p.abha!.display} · not verified', const AbhaScreen()),
          _link(context, LucideIcons.bell, 'Reminders', s.reminderSettings.on ? 'On · ${s.reminderPlan().length} in the next 2 weeks' : 'Off', const RemindersScreen()),
          _link(context, LucideIcons.cloudUpload, 'Backup', s.backupAccount == null ? 'Off · records are only on this phone' : s.lastBackupError != null ? 'On · last attempt failed' : 'On · ${s.lastBackupAt == null ? 'not yet run' : 'last ${dateTime(s.lastBackupAt!)}'}', const BackupScreen()),
          _link(context, LucideIcons.history, 'Access log', '${s.auditEntries().length} ${s.auditEntries().length == 1 ? 'entry' : 'entries'} on this phone', const AuditScreen()),
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
      ShadCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          const IconTile(LucideIcons.eyeOff),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hide from screenshots', style: LT.label),
              SizedBox(height: 4),
              Text('Screenshots, screen recordings and the Recent apps preview come out blank while LifeTrack is open', style: LT.small),
            ]),
          ),
          Switch(
            value: s.screenPrivacyEnabled,
            onChanged: (v) async {
              await s.setScreenPrivacy(v);
              if (context.mounted) AppScope.changed(context);
            },
          ),
        ]),
      ),
      const Eyebrow('Family on this phone'),
      ShadCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyOverviewScreen())),
        child: Row(children: [
          const IconTile(LucideIcons.users),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Family overview', style: LT.label),
              const SizedBox(height: 4),
              Text('${s.familyOnPhone().length} on this phone · you are the head of family', style: LT.small),
            ]),
          ),
          const Icon(LucideIcons.chevronRight, color: LT.inactive),
        ]),
      ),
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
      if (s.demoTools) ...[
        const Eyebrow('Demonstration'),
        ShadCard(
          onTap: () async {
            await s.addSampleRecords();
            if (!context.mounted) return;
            AppScope.changed(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sample records added or brought up to date.')));
          },
          child: const Row(children: [
            IconTile(LucideIcons.sparkles),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Add sample records', style: LT.label),
                SizedBox(height: 4),
                Text('Demo builds only. Adds the sample reports to this profile, or updates them; your own records are untouched.', style: LT.small),
              ]),
            ),
          ]),
        ),
      ],
      const Eyebrow('Where your records are'),
      Note(
        s.backupAccount != null
            ? 'On this phone, encrypted under a key in its secure hardware, and an encrypted backup with LifeTrack under account ${s.backupAccount}.'
            : 'On this phone only, encrypted under a key in its secure hardware. Backup is off, so there is no copy anywhere else — if this phone is lost or reset, these records are gone.',
        icon: s.backupAccount != null ? LucideIcons.cloudCheck : LucideIcons.cloudOff,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Text('LifeTrack $appVersion', style: LT.small, textAlign: TextAlign.center),
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
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  LogView _view = LogView.all;

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
        AuditAction.accessRequested => 'asked for access',
      };

  static const _views = [
    (LogView.all, 'All', 'Everything, newest first.'),
    (LogView.doctors, 'Doctors', 'What you shared with doctors, what they read, and prescriptions they sent.'),
    (LogView.insights, 'Insights', 'Reads by on-device insights while you had them turned on.'),
    (LogView.family, 'Family', 'Family added to this phone, and adults linked from their own phones.'),
    (LogView.emergency, 'Emergency ID', 'Every time the Emergency ID was opened, including from the lock screen.'),
    (LogView.you, 'Your changes', 'Records you added or changed, settings, exports and erasure.'),
    (LogView.refused, 'Refused', 'Attempts that were turned away, from any source.'),
  ];

  /// Reads and refusals record a code (the grant's purpose, or why it was
  /// refused); everything else records a sentence.
  static const _codes = {
    'clinicalConsult': 'for a consultation',
    'onDeviceInsights': 'for on-device insights',
    'cloudAnalysis': 'for cloud analysis',
    'unknown': 'there was no such permission',
    'revoked': 'the permission had been withdrawn',
    'notYetValid': 'the permission had not started yet',
    'expired': 'the permission had ended',
    'spent': 'the one-time permission was already used',
    'wrongPatient': 'the permission was for someone else',
    'wrongActor': 'the permission was for someone else',
    'wrongPurpose': 'the permission was for another purpose',
    'outOfScope': 'not part of what you shared',
  };

  static bool _alert(AuditEntry e) => e.action == AuditAction.denied || e.action == AuditAction.emergencyRead;

  static String _day(DateTime d, DateTime now) {
    final a = DateTime(d.year, d.month, d.day), b = DateTime(now.year, now.month, now.day);
    final diff = b.difference(a).inDays;
    return diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : fullDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final names = s.doctorNames();
    final all = s.auditEntries();
    final entries = [for (final e in all) if (e.shownIn(_view)) e];
    final about = _views.firstWhere((v) => v.$1 == _view).$3;
    final rows = <Widget>[];
    String? day;
    for (final (i, e) in entries.indexed) {
      final d = _day(e.at, s.clock());
      if (d != day) {
        day = d;
        rows.add(Eyebrow(d, padding: const EdgeInsets.fromLTRB(20, 18, 20, 6)));
      }
      final lastOfDay = i == entries.length - 1 || _day(entries[i + 1].at, s.clock()) != d;
      final firstOfDay = rows.last is Eyebrow;
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 56,
            child: Column(children: [
              Container(width: 1, height: 8, color: firstOfDay ? Colors.transparent : LT.rule),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: _alert(e) ? const Color(0xFFFFF7ED) : LT.band, shape: BoxShape.circle),
                child: Icon(iconForActor(e.actorId), size: 15, color: _alert(e) ? LT.signal : LT.ink2),
              ),
              Expanded(child: Container(width: 1, color: lastOfDay ? Colors.transparent : LT.rule)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 20, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${describeActor(e.actorId, names)} ${_verb(e.action)}${e.dataClass == null || e.action == AuditAction.emergencyRead ? '' : ' · ${dataClassNames[e.dataClass]}'}',
                  style: LT.label.copyWith(fontSize: 14.5, color: _alert(e) ? LT.signal : LT.ink),
                ),
                if (e.detail != null) ...[const SizedBox(height: 4), Text(_codes[e.detail] ?? e.detail!, style: LT.small)],
                const SizedBox(height: 4),
                Text(time(e.at), style: LT.small.copyWith(fontSize: 12, color: LT.ink3)),
              ]),
            ),
          ),
        ]),
      ));
    }
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        const Masthead(eyebrow: 'Access log', title: 'Who opened what'),
        const Note('Every read, change and permission is recorded here, on this phone. LifeTrack has no way to edit or remove an entry; erasing your profile is the only thing that clears it.', icon: LucideIcons.history),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              for (final (v, label, _) in _views)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip2('$label · ${all.where((e) => e.shownIn(v)).length}', selected: _view == v, onTap: () => setState(() => _view = v)),
                ),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), child: Text(about, style: LT.small)),
        if (entries.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Nothing here yet.', style: LT.lede)),
        ...rows,
        const SizedBox(height: 28),
      ]),
    );
  }
}
