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
    final self = p.id == s.selfPatientId;
    return ListView(children: [
      Masthead(eyebrow: 'Me', title: self ? 'Profile and settings' : "${p.name.split(' ').first}'s profile"),
      // The person whose records are open, as a black card like the family
      // overview's: lime avatar (the one selected), name, check, ID.
      ShadCard(
        color: LT.primary,
        margin: EdgeInsets.fromLTRB(16, 10, 16, 12),
        padding: EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: LT.accent, shape: BoxShape.circle),
              child: Text(initials, style: TextStyle(fontFamily: LT.display, fontSize: 19, fontWeight: FontWeight.w700, color: LT.onAccent)),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: TextStyle(fontFamily: LT.display, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: LT.onDark)),
                SizedBox(height: 6),
                if (s.isDemo)
                  Badge2('Sample records', tone: BadgeTone.caution)
                else if (p.verification case final v?)
                  Badge2('Verified · ${v.method.label}', tone: BadgeTone.trace)
                else
                  Badge2('Not verified', tone: BadgeTone.outline),
              ]),
            ),
          ]),
          if (s.lifeTrackIdOf(p.id) case final id?) ...[
            SizedBox(height: 14),
            Semantics(
              button: true,
              label: 'Copy LifeTrack ID ${LifeTrackId.display(id)}',
              excludeSemantics: true,
              child: Material(
                color: LT.onDarkChip,
                shape: StadiumBorder(),
                child: InkWell(
                  customBorder: StadiumBorder(),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('LifeTrack ID copied.')));
                  },
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(children: [
                        Text('LifeTrack ID', style: TextStyle(fontSize: 12, color: LT.onDarkMuted)),
                        SizedBox(width: 10),
                        Expanded(child: Text(LifeTrackId.display(id), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1, color: LT.onDark, fontFeatures: [FontFeature.tabularFigures()]))),
                        Icon(LucideIcons.copy, size: 16, color: LT.onDark),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ] else if (s.ids != null) ...[
            SizedBox(height: 12),
            Text('LifeTrack ID: assigned when the phone reaches LifeTrack', style: TextStyle(fontSize: 14, color: LT.onDarkMuted)),
          ],
        ]),
      ),
      if (!p.isVerified && !s.isDemo && s.verifier != null && p.id == s.selfPatientId)
        ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Verify your profile', style: LT.label),
            SizedBox(height: 4),
            Text('This profile was made before DigiLocker verification. Verify with your Aadhaar; your name, date of birth and gender become what DigiLocker confirms.', style: LT.small),
            SizedBox(height: 8),
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
      // Settings for the person on screen, then settings for the phone
      // itself — so it is clear which follow a switch of profile.
      Eyebrow(self ? 'Your profile' : "${p.name.split(' ').first}'s profile", padding: EdgeInsets.fromLTRB(20, 10, 20, 10)),
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _link(context, LucideIcons.ambulance, 'Emergency ID', 'For whoever treats you · keep a copy outside the phone too', EmergencyScreen()),
          _link(context, LucideIcons.idCard, 'ABHA health ID', p.abha == null ? 'Optional · not added' : '${p.abha!.display} · not verified', AbhaScreen()),
          _link(context, LucideIcons.bell, 'Reminders', s.reminderSettings.on ? 'On · ${s.reminderPlan().length} in the next 2 weeks' : 'Off', RemindersScreen()),
          _link(context, LucideIcons.cloudUpload, 'Backup', s.backupAccount == null ? 'Off · records are only on this phone' : s.lastBackupError != null ? 'On · last attempt failed' : 'On · ${s.lastBackupAt == null ? 'not yet run' : 'last ${dateTime(s.lastBackupAt!)}'}', BackupScreen()),
          _link(context, LucideIcons.history, 'Access log', '${s.auditEntries().length} ${s.auditEntries().length == 1 ? 'entry' : 'entries'} on this phone', AuditScreen()),
          _link(context, LucideIcons.scale, 'Your data and your rights', 'What is held where, and how to erase it', DataRightsScreen(), last: true),
        ]),
      ),
      Eyebrow('This phone'),
      // One card for the phone's own settings, rows divided like the profile's.
      ShadCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          if (AppLockGate.of(context) case final lock? when lock.available)
            _switchRow(LucideIcons.lock, 'App lock', 'Fingerprint, face or phone PIN when LifeTrack opens', s.appLockEnabled, (v) async {
              if (await lock.setEnabled(v) && context.mounted) AppScope.changed(context);
            }),
          _switchRow(LucideIcons.eyeOff, 'Hide from screenshots', 'Screenshots, screen recordings and the Recent apps preview come out blank while LifeTrack is open', s.screenPrivacyEnabled, (v) async {
            await s.setScreenPrivacy(v);
            if (context.mounted) AppScope.changed(context);
          }),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const IconTile(LucideIcons.sunMoon),
                const SizedBox(width: 14),
                Expanded(child: Text('Appearance', style: LT.label)),
              ]),
              const SizedBox(height: 12),
              Segmented(
                options: const [('system', 'Follow phone'), ('light', 'Light'), ('dark', 'Dark')],
                value: s.themeChoice,
                onChanged: (v) => crossfadeTheme(context, () async {
                  await s.setThemeChoice(v);
                  appearance.value = themeModeOf(v);
                  if (context.mounted) AppScope.changed(context);
                }),
              ),
            ]),
          ),
        ]),
      ),
      Eyebrow('Family on this phone'),
      ShadCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FamilyOverviewScreen())),
        child: Row(children: [
          IconTile(LucideIcons.users),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Family overview', style: LT.label),
              SizedBox(height: 4),
              Text('${s.familyOnPhone().length} on this phone · you are the head of family', style: LT.small),
            ]),
          ),
          Icon(LucideIcons.chevronRight, color: LT.inactive),
        ]),
      ),
      for (final f in s.familyOnPhone().where((f) => f.id != s.selfPatientId))
        () {
          final c = s.custodyOf(f.id)!;
          return ShadCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(backgroundColor: LT.raised, child: Text(FamilyBar.initials(f.name), style: TextStyle(color: LT.ink, fontWeight: FontWeight.w600))),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(FamilyBar.authorityLine(c), style: LT.small),
                  if (c.consentedAt != null) Text('Since ${fullDate(c.consentedAt!)}', style: LT.small.copyWith(fontSize: 12)),
                  if (c.kind == CustodyKind.delegatedByAdult)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
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
        padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: SlabButton('Add a family member', variant: ButtonVariant.outline, icon: LucideIcons.userPlus, onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddFamilyScreen()));
          if (context.mounted) AppScope.changed(context);
        }),
      ),
      LinkedAdultsSection(),
      if (s.demoTools) ...[
        Eyebrow('Demonstration'),
        ShadCard(
          onTap: () async {
            await s.addSampleRecords();
            if (!context.mounted) return;
            AppScope.changed(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sample records added or brought up to date.')));
          },
          child: Row(children: [
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
      Eyebrow('Where your records are'),
      Note(
        s.backupAccount != null
            ? 'On this phone, encrypted under a key in its secure hardware, and an encrypted backup with LifeTrack under account ${s.backupAccount}.'
            : 'On this phone only, encrypted under a key in its secure hardware. Backup is off, so there is no copy anywhere else — if this phone is lost or reset, these records are gone.',
        icon: s.backupAccount != null ? LucideIcons.cloudCheck : LucideIcons.cloudOff,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Text('LifeTrack $appVersion', style: LT.small, textAlign: TextAlign.center),
      ),
    ]);
  }

  Widget _switchRow(IconData icon, String title, String sub, bool value, ValueChanged<bool> onChanged) => Container(
        padding: EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: LT.rule))),
        child: Row(children: [
          IconTile(icon),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: LT.label),
              SizedBox(height: 4),
              Text(sub, style: LT.small),
            ]),
          ),
          Switch(value: value, onChanged: onChanged),
        ]),
      );

  Widget _link(BuildContext context, IconData icon, String title, String sub, Widget page, {bool last = false}) => InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
          if (context.mounted) AppScope.changed(context);
        },
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: LT.rule))),
          child: Row(children: [
            IconTile(icon),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: LT.label),
                SizedBox(height: 4),
                Text(sub, style: LT.small),
              ]),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: LT.inactive),
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
        AuditAction.export => 'exported a copy of the records',
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
        rows.add(Eyebrow(d, padding: EdgeInsets.fromLTRB(20, 18, 20, 6)));
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
                decoration: BoxDecoration(color: _alert(e) ? Color(0xFFFFF7ED) : LT.band, shape: BoxShape.circle),
                child: Icon(iconForActor(e.actorId), size: 15, color: _alert(e) ? LT.signal : LT.ink2),
              ),
              Expanded(child: Container(width: 1, color: lastOfDay ? Colors.transparent : LT.rule)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 12, 20, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${describeActor(e.actorId, names)} ${_verb(e.action)}${e.dataClass == null || e.action == AuditAction.emergencyRead ? '' : ' · ${dataClassNames[e.dataClass]}'}',
                  style: LT.label.copyWith(fontSize: 15, color: _alert(e) ? LT.signal : LT.ink),
                ),
                if (e.detail != null) ...[SizedBox(height: 4), Text(_codes[e.detail] ?? e.detail!, style: LT.small)],
                SizedBox(height: 4),
                Text(time(e.at), style: LT.small.copyWith(fontSize: 12, color: LT.ink3)),
              ]),
            ),
          ),
        ]),
      ));
    }
    return Scaffold(
      appBar: GlassAppBar(),
      extendBodyBehindAppBar: true,
      body: ListView(children: [
        Masthead(eyebrow: 'Access log', title: 'Who opened what'),
        Note('Every read, change and permission is recorded here, on this phone. LifeTrack has no way to edit or remove an entry; erasing your profile is the only thing that clears it.', icon: LucideIcons.history),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              for (final (v, label, _) in _views)
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip2('$label · ${all.where((e) => e.shownIn(v)).length}', selected: _view == v, onTap: () => setState(() => _view = v)),
                ),
            ],
          ),
        ),
        Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 0), child: Text(about, style: LT.small)),
        if (entries.isEmpty) Padding(padding: EdgeInsets.all(20), child: Text('Nothing here yet.', style: LT.lede)),
        ...rows,
        SizedBox(height: 28),
      ]),
    );
  }
}
