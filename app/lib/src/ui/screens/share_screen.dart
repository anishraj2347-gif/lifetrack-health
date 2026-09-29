import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../consent/consent_token.dart';
import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

String describeActor(String actorId) {
  if (actorId == Actors.planeA) return 'On-device insights';
  if (actorId == Actors.cloud) return 'Cloud analysis';
  if (actorId.startsWith('doctor:')) return 'Doctor · ${actorId.substring(7)}';
  if (actorId.startsWith('patient:')) return 'You';
  if (actorId.startsWith('unauthenticated:')) return 'Someone without your PIN';
  return actorId;
}

const dataClassNames = {
  DataClass.prescriptions: 'Prescriptions',
  DataClass.reports: 'Reports',
  DataClass.scans: 'Scans',
  DataClass.personalNotes: 'Personal notes',
  DataClass.vitals: 'Vitals',
  DataClass.emergencyCard: 'Emergency ID',
};

IconData iconForActor(String actorId) {
  if (actorId == Actors.planeA) return LucideIcons.activity;
  if (actorId == Actors.cloud) return LucideIcons.cloud;
  if (actorId.startsWith('doctor:')) return LucideIcons.stethoscope;
  if (actorId.startsWith('unauthenticated:')) return LucideIcons.lockOpen;
  return LucideIcons.userRound;
}

class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final grants = s.activeGrants();
    return ListView(children: [
      Masthead(
        eyebrow: 'Share',
        title: 'Who can see your records',
        trailing: Badge2(grants.isEmpty ? 'No access' : '${grants.length} active', tone: grants.isEmpty ? BadgeTone.outline : BadgeTone.trace),
      ),
      const SizedBox(height: 12),
      if (grants.isEmpty)
        const ShadCard(
          child: Row(children: [
            IconTile(LucideIcons.shieldCheck, color: LT.trace, background: Color(0xFFECFDF5)),
            SizedBox(width: 14),
            Expanded(child: Text('Nobody has access right now.', style: LT.label)),
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
                const SizedBox(height: 3),
                Text(g.scopes.map((c) => dataClassNames[c]).join(', '), style: LT.small),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (g.type == GrantType.oneTime) const Badge2('One use'),
                  Badge2('Until ${dateTime(g.expiresAt)}', tone: BadgeTone.outline),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: SlabButton('Revoke', variant: ButtonVariant.outline, onPressed: () async {
                await s.revoke(g);
                if (context.mounted) AppScope.changed(context);
              }),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: SlabButton('Give a doctor access', icon: LucideIcons.userPlus, onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GrantDoctorScreen()));
          if (context.mounted) AppScope.changed(context);
        }),
      ),
    ]);
  }
}

class GrantDoctorScreen extends StatefulWidget {
  const GrantDoctorScreen({super.key});
  @override
  State<GrantDoctorScreen> createState() => _GrantDoctorScreenState();
}

class _GrantDoctorScreenState extends State<GrantDoctorScreen> {
  final _registry = TextEditingController();
  final _scopes = <DataClass>{DataClass.prescriptions, DataClass.reports};
  var _window = const Duration(hours: 24);
  var _type = GrantType.session;
  ConsentToken? _issued;
  String? _error;

  Future<void> _grant() async {
    final id = _registry.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]{3,20}$').hasMatch(id)) {
      setState(() => _error = 'Enter the doctor\'s registration number as printed on their prescription.');
      return;
    }
    try {
      final g = await AppScope.of(context).grantDoctor(doctorRegistryId: id, scopes: _scopes, window: _window, type: _type);
      setState(() => _issued = g);
    } on Exception catch (e) {
      setState(() => _error = e.toString().contains('ConsentConflict')
          ? 'This doctor already has access. Revoke it first to change what they can see or for how long.'
          : '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: _issued != null ? _done(_issued!) : _form(),
      );

  Widget _form() => ListView(children: [
        const Masthead(eyebrow: 'Share', title: 'Give a doctor access', description: 'Access ends on its own. You can revoke it sooner.'),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Doctor registration number',
          hint: 'Not yet checked against the national medical register — that check arrives with the doctor app.',
          child: TextField(controller: _registry, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'e.g. NMC-12345')),
        ),
        const Eyebrow('What they can see', padding: EdgeInsets.fromLTRB(20, 4, 20, 10)),
        ShadCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final c in [DataClass.prescriptions, DataClass.reports, DataClass.scans, DataClass.personalNotes])
              CheckboxListTile(
                dense: true,
                value: _scopes.contains(c),
                title: Text(dataClassNames[c]!, style: LT.label.copyWith(fontSize: 14.5)),
                onChanged: (v) => setState(() => v! ? _scopes.add(c) : _scopes.remove(c)),
              ),
          ]),
        ),
        const Eyebrow('For how long', padding: EdgeInsets.fromLTRB(20, 8, 20, 10)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            Chip2('One visit · 1 h', selected: _type == GrantType.oneTime, onTap: () => setState(() {
              _type = GrantType.oneTime;
              _window = const Duration(hours: 1);
            })),
            Chip2('24 hours', selected: _type == GrantType.session && _window.inHours == 24, onTap: () => setState(() {
              _type = GrantType.session;
              _window = const Duration(hours: 24);
            })),
            Chip2('48 hours', selected: _type == GrantType.session && _window.inHours == 48, onTap: () => setState(() {
              _type = GrantType.session;
              _window = const Duration(hours: 48);
            })),
          ]),
        ),
        const Note('48 hours is the longest any access can last. To extend it, you approve again. You can revoke it at any moment.'),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 28), child: SlabButton('Approve access', icon: LucideIcons.check, onPressed: _scopes.isEmpty ? null : _grant)),
      ]);

  Widget _done(ConsentToken g) => ListView(children: [
        const Masthead(eyebrow: 'Share', title: 'Access approved'),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: IconTile(LucideIcons.circleCheck, color: LT.trace, background: Color(0xFFECFDF5)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Text('${describeActor(g.grantedToActorId)} can see ${g.scopes.map((c) => dataClassNames[c]!.toLowerCase()).join(', ')} until ${dateTime(g.expiresAt)}.', style: LT.lede),
        ),
        const Note('The doctor app that receives this is not available yet, so this access cannot be used yet in this version. It is recorded, and you can revoke it from Share.'),
        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 28), child: SlabButton('Done', onPressed: () => Navigator.of(context).pop())),
      ]);
}
