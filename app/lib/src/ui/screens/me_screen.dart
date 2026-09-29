import 'package:flutter/material.dart';

import '../../audit/audit_log.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'data_rights_screen.dart';
import 'emergency_screen.dart';
import 'share_screen.dart' show describeActor, dataClassNames;

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    return ListView(children: [
      Masthead(eyebrow: s.isDemo ? 'Me · sample records' : 'Me', title: p.name),
      _link(context, 'Emergency ID', 'What a paramedic sees', const EmergencyScreen()),
      _link(context, 'Access log', '${s.auditEntries().length} entries on this phone', const AuditScreen()),
      _link(context, 'Your data and your rights', 'What is held where, and how to erase it', const DataRightsScreen()),
      const Eyebrow('Where your records are'),
      const Note(
        'On this phone only, encrypted under a key in its secure hardware. The encrypted backup service is not live in this version, so there is no copy anywhere else — if this phone is lost or reset, these records are gone.',
        margin: EdgeInsets.fromLTRB(20, 0, 20, 24),
      ),
    ]);
  }

  Widget _link(BuildContext context, String title, String sub, Widget page) => InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
          if (context.mounted) AppScope.changed(context);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LT.rule))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: LT.label.copyWith(fontSize: 17)),
                const SizedBox(height: 4),
                Text(sub, style: LT.small),
              ]),
            ),
            const Icon(Icons.chevron_right, color: LT.ink3),
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
        AuditAction.emergencyRead => 'opened the Emergency ID',
        AuditAction.vaultBackup => 'backed up',
        AuditAction.vaultRestore => 'restored from backup',
        AuditAction.erasure => 'erased the profile',
      };

  @override
  Widget build(BuildContext context) {
    final entries = AppScope.of(context).auditEntries();
    return Scaffold(
      appBar: AppBar(backgroundColor: LT.ground, elevation: 0, foregroundColor: LT.ink),
      body: ListView(children: [
        const Masthead(eyebrow: 'Access log', title: 'Who opened what'),
        const Note('Every read, change and permission is recorded here, on this phone. LifeTrack has no way to edit or remove an entry; erasing your profile is the only thing that clears it.'),
        const SizedBox(height: 10),
        if (entries.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Nothing yet.', style: LT.lede)),
        for (final e in entries)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: LT.rule))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dateTime(e.at).toUpperCase(), style: LT.eyebrow.copyWith(letterSpacing: 1)),
              const SizedBox(height: 5),
              Text(
                '${describeActor(e.actorId)} ${_verb(e.action)}${e.dataClass == null ? '' : ' · ${dataClassNames[e.dataClass]}'}',
                style: LT.label.copyWith(color: e.action == AuditAction.denied || e.action == AuditAction.emergencyRead ? LT.signal : LT.ink),
              ),
              if (e.detail != null) ...[const SizedBox(height: 3), Text(e.detail!, style: LT.small)],
            ]),
          ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
