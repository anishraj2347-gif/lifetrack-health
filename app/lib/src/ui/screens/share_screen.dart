import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../consent/consent_token.dart';
import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'doctor_share_screen.dart';
import 'show_on_phone_screen.dart';

String describeActor(String actorId) {
  if (actorId == Actors.planeA) return t('On-device insights');
  if (actorId == Actors.cloud) return t('Cloud analysis');
  if (actorId.startsWith('doctor:')) return 'Doctor · ${actorId.substring(7)}';
  if (actorId.startsWith('patient:')) return t('You');
  if (actorId.startsWith('unauthenticated:')) return t('Someone without your PIN');
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
    return ListView(children: [
      Masthead(
        eyebrow: t('Share'),
        title: t('Show a doctor your records'),
        trailing: Badge2(grants.isEmpty ? t('No access') : '${grants.length} active', tone: grants.isEmpty ? BadgeTone.outline : BadgeTone.trace),
      ),
      const SizedBox(height: 12),
      ShadCard(
        color: LT.primary,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShowOnPhoneScreen())),
        child: Row(children: [
          IconTile(LucideIcons.smartphone, color: LT.ink, background: LT.accent),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Show on my phone'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
              SizedBox(height: 4),
              Text(t('Hand the phone to the doctor. Nothing is sent.'), style: TextStyle(fontSize: 12.5, color: LT.onDarkMuted)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, color: LT.onDarkMuted),
        ]),
      ),
      if (sharing != null) ...[
        ShadCard(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DoctorShareScreen()));
            if (context.mounted) AppScope.changed(context);
          },
          child: Row(children: [
            IconTile(LucideIcons.qrCode),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Share with a doctor'), style: LT.label),
                SizedBox(height: 4),
                Text(t('Scan their verified code; it\'s encrypted to their device'), style: LT.small),
              ]),
            ),
            Icon(LucideIcons.chevronRight, color: LT.inactive),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SlabButton(t('Check for updates'), variant: ButtonVariant.outline, icon: LucideIcons.inbox, onPressed: () async {
            final msg = ScaffoldMessenger.of(context);
            try {
              final (added, family, refused) = await s.checkInbox();
              msg.showSnackBar(SnackBar(
                content: Text(added == 0 && family == 0 && refused == 0
                    ? t('Nothing new.')
                    : [
                        if (added > 0) '$added prescription${added == 1 ? '' : 's'} added',
                        if (family > 0) '$family family update${family == 1 ? '' : 's'}',
                        if (refused > 0) '$refused refused — see your access log',
                      ].join(', ')),
              ));
              if (context.mounted) AppScope.changed(context);
            } on Object catch (e) {
              msg.showSnackBar(SnackBar(content: Text('Could not check: $e')));
            }
          }),
        ),
      ] else
        Note(t('Sharing with a doctor\'s device is not set up in this build. "Show on my phone" works without it.'), icon: LucideIcons.cloudOff),
      Eyebrow(t('Who has access now')),
      if (grants.isEmpty)
        ShadCard(
          child: Row(children: [
            IconTile(LucideIcons.shieldCheck, color: LT.trace, background: Color(0xFFECFDF5)),
            SizedBox(width: 14),
            Expanded(child: Text(t('Nobody has access right now.'), style: LT.label)),
          ]),
        ),
      for (final g in grants)
        ShadCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(iconForActor(g.grantedToActorId)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(describeActor(g.grantedToActorId), style: LT.label),
                const SizedBox(height: 4),
                Text(g.levels.isNotEmpty ? levelsLabel(g.levels) : g.scopes.map((c) => dataClassNames[c]).join(', '), style: LT.small),
                const SizedBox(height: 8),
                Badge2('Until ${dateTime(g.expiresAt)}', tone: BadgeTone.outline),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: SlabButton(t('End'), variant: ButtonVariant.outline, onPressed: () async {
                if (isClinicalShare(g) && sharing != null) {
                  await sharing.endAccess(g, s.clock());
                } else {
                  await s.revoke(g);
                }
                if (context.mounted) AppScope.changed(context);
              }),
            ),
          ]),
        ),
      const SizedBox(height: 28),
    ]);
  }
}
