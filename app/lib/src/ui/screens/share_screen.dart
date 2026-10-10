import 'package:flutter/material.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart' show AccessRequest;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../consent/consent_token.dart';
import '../../model/health_record.dart';
import '../../share/access_requests.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'doctor_share_screen.dart';
import 'show_on_phone_screen.dart';
import 'tests_you_have_screen.dart';

/// [doctorNames] maps a doctor's registration number to the name their
/// verified certificate showed when the patient shared with them.
String describeActor(String actorId, [Map<String, String> doctorNames = const {}]) {
  if (actorId == Actors.planeA) return 'On-device insights';
  if (actorId == Actors.cloud) return 'Cloud analysis';
  if (actorId.startsWith('doctor:')) {
    final reg = actorId.substring(7);
    return doctorNames[reg] == null ? 'Doctor · $reg' : '${doctorNames[reg]} · $reg';
  }
  if (actorId.startsWith('patient:')) return 'You';
  if (actorId.startsWith('unauthenticated:')) return 'Opened from the lock screen (not unlocked)';
  if (actorId.startsWith('family:')) return actorId.substring(7);
  return actorId;
}

const dataClassNames = {
  DataClass.prescriptions: 'Prescriptions',
  DataClass.reports: 'Reports',
  DataClass.scans: 'Scans',
  DataClass.personalNotes: 'Personal notes',
  DataClass.vitals: 'Vitals',
  DataClass.emergencyCard: 'Emergency ID',
  DataClass.allergies: 'Allergies',
  DataClass.conditions: 'Conditions',
  DataClass.familyHistory: 'Family illnesses',
};

IconData iconForActor(String actorId) {
  if (actorId == Actors.planeA) return LucideIcons.activity;
  if (actorId == Actors.cloud) return LucideIcons.cloud;
  if (actorId.startsWith('doctor:')) return LucideIcons.stethoscope;
  if (actorId.startsWith('unauthenticated:')) return LucideIcons.lockOpen;
  if (actorId.startsWith('family:')) return LucideIcons.users;
  return LucideIcons.userRound;
}

class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final grants = s.activeGrants();
    final sharing = s.sharing;
    final list = ListView(physics: AlwaysScrollableScrollPhysics(), children: [
      Masthead(
        eyebrow: 'Share',
        title: 'Show a doctor your records',
        trailing: Badge2(grants.isEmpty ? 'No access' : '${grants.length} active', tone: grants.isEmpty ? BadgeTone.outline : BadgeTone.trace),
      ),
      if (grants.isEmpty) PhotoBanner(Photos.doctor, height: 150),
      SizedBox(height: 12),
      ShadCard(
        color: LT.primary,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShowOnPhoneScreen())),
        child: Row(children: [
          IconTile(LucideIcons.smartphone, color: LT.onDark, background: LT.onDarkChip),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Show on my phone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
              SizedBox(height: 4),
              Text('Hand the phone to the doctor. Nothing is sent; they can see only this summary until you unlock.', style: TextStyle(fontSize: 14, color: LT.onDarkMuted)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, color: LT.onDarkMuted),
        ]),
      ),
      if (sharing != null) ...[
        ShadCard(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DoctorShareScreen()));
            if (context.mounted) AppScope.changed(context);
          },
          child: Row(children: [
            IconTile(LucideIcons.qrCode),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Share with a doctor', style: LT.label),
                SizedBox(height: 4),
                Text("Scan their verified code; it's encrypted to their device", style: LT.small),
              ]),
            ),
            Icon(LucideIcons.chevronRight, color: LT.inactive),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SlabButton('Check for prescriptions and updates', variant: ButtonVariant.outline, icon: LucideIcons.inbox, onPressed: () => _check(context)),
        ),
      ] else
        Note('Sharing with a doctor\'s device is not set up in this build. "Show on my phone" works without it.', icon: LucideIcons.cloudOff),
      TestsYouHaveCard(margin: EdgeInsets.fromLTRB(16, 0, 16, 12)),
      if (sharing != null) const _Requests(),
      Eyebrow('Who has access now'),
      if (grants.isEmpty)
        ShadCard(
          child: Row(children: [
            IconTile(LucideIcons.shieldCheck, color: LT.traceInk, background: Color(0xFFECFDF5)),
            SizedBox(width: 14),
            Expanded(child: Text('Nobody has access right now.', style: LT.label)),
          ]),
        ),
      for (final g in grants)
        ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconTile(iconForActor(g.grantedToActorId)),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(describeActor(g.grantedToActorId, s.doctorNames()), style: LT.label),
                  SizedBox(height: 4),
                  Text(g.levels.isNotEmpty ? levelsLabel(g.levels) : g.scopes.map((c) => dataClassNames[c]).join(', '), style: LT.small),
                  SizedBox(height: 8),
                  Badge2('Until ${dateTime(g.expiresAt)}', tone: BadgeTone.outline),
                ]),
              ),
            ]),
            SizedBox(height: 12),
            Row(children: [
              if (isClinicalShare(g) && sharing != null) ...[
                Expanded(child: SlabButton('Change time', variant: ButtonVariant.outline, icon: LucideIcons.clock, onPressed: () => _changeTime(context, g))),
                SizedBox(width: 8),
              ],
              Expanded(
                child: SlabButton('End access', variant: ButtonVariant.outline, icon: LucideIcons.circleX, onPressed: () async {
                  final who = describeActor(g.grantedToActorId, s.doctorNames());
                  final sure = await confirmAction(context, title: 'End access now?', body: '$who will need a new share to see these records again.', confirm: 'End access');
                  if (!sure) return;
                  if (isClinicalShare(g) && sharing != null) {
                    await sharing.endAccess(g, s.clock());
                  } else {
                    await s.revoke(g);
                  }
                  if (context.mounted) AppScope.changed(context);
                }),
              ),
            ]),
          ]),
        ),
      SizedBox(height: 28),
    ]);
    if (sharing == null) return list;
    // Pull down to collect prescriptions and family updates.
    return RefreshIndicator(
      color: LT.ink,
      backgroundColor: LT.surface,
      onRefresh: () => _check(context),
      child: list,
    );
  }

  static Future<void> _check(BuildContext context) async {
    final s = AppScope.of(context);
    final msg = ScaffoldMessenger.of(context);
    try {
      final (added, family, refused) = await s.checkInbox();
      msg.showSnackBar(SnackBar(
        content: Text(added == 0 && family == 0 && refused == 0
            ? 'Nothing new.'
            : [
                if (added > 0) '$added prescription${added == 1 ? '' : 's'} added — see Records',
                if (family > 0) '$family family update${family == 1 ? '' : 's'}',
                if (refused > 0) '$refused refused — see your access log',
              ].join(', ')),
      ));
      if (context.mounted) AppScope.changed(context);
    } on Object catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not check. ${plainError(e)}')));
    }
  }

  /// Longer or shorter, from now: the doctor's copy is replaced with one that
  /// ends at the new time.
  Future<void> _changeTime(BuildContext context, ConsentToken g) async {
    final s = AppScope.of(context);
    final hours = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Change how long', style: LT.title),
            SizedBox(height: 4),
            Text('Counted from now. Now until ${dateTime(g.expiresAt)}.', style: LT.small),
            SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in AccessRequest.accessChoices) Chip2(hoursLabel(h), selected: false, onTap: () => Navigator.of(c).pop(h)),
            ]),
          ]),
        ),
      ),
    );
    if (hours == null || !context.mounted) return;
    try {
      final r = await s.sharing!.changeTime(g, Duration(hours: hours), s.clock());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r.doctor.name} can now see it until ${dateTime(r.grant.expiresAt)}.')));
    } on Object catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Time not changed. ${plainError(e)}')));
    }
    if (context.mounted) AppScope.changed(context);
  }
}

/// Doctors who asked by LifeTrack ID. Verified on arrival; nothing is shared
/// until the patient reviews and approves.
class _Requests extends StatelessWidget {
  const _Requests();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return FutureBuilder<List<PendingRequest>>(
      future: s.pendingRequests(),
      builder: (context, snap) {
        final list = snap.data ?? <PendingRequest>[];
        if (list.isEmpty) return SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow('Doctors asking for access'),
          for (final p in list)
            ShadCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconTile(LucideIcons.stethoscope),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.doctor.name, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('${p.doctor.speciality} · ${p.doctor.registrationNo}', style: LT.small),
                    ]),
                  ),
                  Badge2('Verified', tone: BadgeTone.trace),
                ]),
                SizedBox(height: 10),
                Text('Asks for: ${levelsLabel(p.levels)}${p.request.accessHours == null ? '' : ' · for ${hoursLabel(p.request.accessHours!)}'}', style: LT.label),
                if (p.request.note != null && p.request.note!.trim().isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text('"${p.request.note!.trim()}"', style: LT.small),
                ],
                SizedBox(height: 4),
                Text('Request ends ${dateTime(p.request.expiresAt.toLocal())}', style: LT.small.copyWith(fontSize: 12, color: LT.ink3)),
                SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: SlabButton('Review', icon: LucideIcons.eye, onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DoctorShareScreen(request: p)));
                      if (context.mounted) AppScope.changed(context);
                    }),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: SlabButton('Decline', variant: ButtonVariant.outline, onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await s.declineRequest(p);
                        messenger.showSnackBar(SnackBar(content: Text('Declined. ${p.doctor.name} has been told.')));
                      } on Object {
                        messenger.showSnackBar(SnackBar(content: Text('Declined here, but the doctor could not be told yet.')));
                      }
                      if (context.mounted) AppScope.changed(context);
                    }),
                  ),
                ]),
              ]),
            ),
        ]);
      },
    );
  }
}
