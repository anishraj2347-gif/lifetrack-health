import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../consent/consent_token.dart';
import '../../share/clinical_share_service.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// P4: scan the doctor's verified code → see who they are → pick a level →
/// confirm medicines → share. Every step is the patient's own tap.
class DoctorShareScreen extends StatefulWidget {
  const DoctorShareScreen({super.key});
  @override
  State<DoctorShareScreen> createState() => _DoctorShareScreenState();
}

class _DoctorShareScreenState extends State<DoctorShareScreen> {
  DoctorCertificate? _doctor;
  String? _error;
  bool _scanning = true;
  bool _busy = false;
  final _paste = TextEditingController();
  final Set<AccessLevel> _levels = {AccessLevel.summary};
  bool _lastTwoYears = false;
  final Set<String> _stillTaking = {};
  ShareReceipt? _receipt;

  Future<void> _verify(String code) async {
    final sharing = AppScope.of(context).sharing!;
    try {
      final d = await sharing.scan(code, AppScope.of(context).clock());
      if (!mounted) return;
      setState(() {
        _doctor = d;
        _scanning = false;
        _error = null;
      });
    } on CertificateRejected catch (e) {
      setState(() => _error = e.patientMessage);
    }
  }

  Future<void> _share() async {
    final s = AppScope.of(context);
    setState(() => _busy = true);
    final at = s.clock();
    try {
      await s.confirmMedicines(_stillTaking, at);
      final grantor = s.actingGrantor();
      final r = await s.sharing!.share(
        grantorId: grantor,
        sharedBy: s.sharedByNote(),
        patientId: s.currentPatientId!,
        doctor: _doctor!,
        levels: _levels,
        filter: _lastTwoYears ? RecordFilter(from: at.subtract(const Duration(days: 730))) : null,
        at: at,
      );
      if (!mounted) return;
      setState(() => _receipt = r);
      AppScope.changed(context);
    } on Object catch (e) {
      setState(() => _error = 'Could not send: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: _receipt != null
            ? _done(_receipt!)
            : _doctor == null
                ? _scan()
                : _choose(_doctor!),
      );

  Widget _scan() => ListView(children: [
        Masthead(eyebrow: t('Share with a doctor'), title: t('Scan the doctor\'s code'), description: t('Their LifeTrack screen shows a verified code. Nothing is shared until you choose.')),
        if (_scanning)
          Container(
            height: 320,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(LT.radiusLg), color: LT.primary),
            child: ReaderWidget(
              onScan: (code) {
                final text = code.text;
                if (text != null && text.isNotEmpty) _verify(text);
              },
              showGallery: false,
              showToggleCamera: false,
              tryHarder: true,
            ),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        LabeledField(
          label: t('Or paste the code'),
          child: Padding(
            padding: const EdgeInsets.only(top: 0),
            child: TextField(controller: _paste, maxLines: 2, decoration: InputDecoration(hintText: t('Code from the doctor\'s screen'))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          child: SlabButton(t('Check this doctor'), variant: ButtonVariant.outline, icon: LucideIcons.shieldCheck, onPressed: () => _verify(_paste.text)),
        ),
      ]);

  Widget _choose(DoctorCertificate d) {
    final s = AppScope.of(context);
    final active = [for (final r in s.records()) if (r.isActiveAt(s.clock())) r];
    return ListView(children: [
      ShadCard(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        color: LT.primary,
        child: Row(children: [
          const IconTile(LucideIcons.stethoscope, color: LT.ink, background: LT.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
              Text('${d.speciality} · ${d.registrationNo}', style: const TextStyle(fontSize: 12.5, color: LT.onDarkMuted)),
              Text(d.council, style: const TextStyle(fontSize: 12, color: LT.onDarkMuted)),
            ]),
          ),
          Badge2(t('Verified'), tone: BadgeTone.trace),
        ]),
      ),
      Eyebrow(t('What should this doctor see?'), padding: EdgeInsets.fromLTRB(20, 0, 20, 10)),
      _level(AccessLevel.summary, t('Summary'), t('Allergies, current medicines, conditions, latest results with their source'), recommended: true),
      _level(AccessLevel.allReports, t('All my reports'), t('Every report, prescription and scan')),
      if (_levels.contains(AccessLevel.allReports))
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Chip2(t('Last 2 years only'), selected: _lastTwoYears, onTap: () => setState(() => _lastTwoYears = !_lastTwoYears)),
        ),
      _level(AccessLevel.familyIllnesses, t('Family illnesses'), t('What you have told LifeTrack about your family, marked "patient-reported"')),
      if (active.isNotEmpty) ...[
        Eyebrow(t('Are you still taking these?')),
        for (final r in active)
          CheckboxListTile(
            value: _stillTaking.contains(r.id),
            onChanged: (v) => setState(() => v! ? _stillTaking.add(r.id) : _stillTaking.remove(r.id)),
            title: Text('${r.title}${r.dose == null ? '' : ' · ${r.dose!.display}'}', style: LT.label.copyWith(fontSize: 14.5)),
            subtitle: Text(r.doctor ?? '', style: LT.small),
          ),
      ],
      Note(t('For this visit, up to 4 hours. Encrypted so only this doctor\'s device can open it. Personal notes are never included. The doctor keeps their own consult note; you can end access any time.'),
          icon: LucideIcons.lock),
      if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        child: SlabButton('Share with ${d.name}', icon: LucideIcons.send, onPressed: _busy || _levels.isEmpty ? null : _share),
      ),
    ]);
  }

  Widget _level(AccessLevel l, String title, String body, {bool recommended = false}) {
    final on = _levels.contains(l);
    return ShadCard(
      color: on ? LT.raised : LT.surface,
      borderColor: on ? LT.primary : null,
      onTap: () => setState(() => on ? _levels.remove(l) : _levels.add(l)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(on ? LucideIcons.circleCheck : LucideIcons.circle, size: 20, color: on ? LT.ink : LT.inactive),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              Text(title, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
              if (recommended) Badge2(t('Recommended')),
            ]),
            const SizedBox(height: 4),
            Text(body, style: LT.small),
          ]),
        ),
      ]),
    );
  }

  Widget _done(ShareReceipt r) => ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: IconTile(LucideIcons.circleCheck, color: LT.ink, background: LT.accent),
        ),
        Masthead(eyebrow: t('Shared'), title: 'Sent to ${r.doctor.name}', description: 'Encrypted to their device. Access ends ${dateTime(r.grant.expiresAt)}.'),
        Note(t('If they have not opened it yet, ending access removes it. If they already have, their app is asked to close it — LifeTrack cannot take back what they have seen.'), icon: LucideIcons.info),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: SlabButton(t('End access now'), variant: ButtonVariant.outline, onPressed: () async {
            await AppScope.of(context).sharing!.endAccess(r.grant, AppScope.of(context).clock());
            if (!mounted) return;
            AppScope.changed(context);
            Navigator.of(context).pop();
          }),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), child: SlabButton(t('Done'), onPressed: () => Navigator.of(context).pop())),
      ]);
}

/// Whether [r] is a clinical share grant (vs an on-device one).
bool isClinicalShare(ConsentToken g) => g.granteeKeyId != null;

String levelsLabel(Set<AccessLevel> l) => [
      if (l.contains(AccessLevel.summary)) t('Summary'),
      if (l.contains(AccessLevel.allReports)) t('All reports'),
      if (l.contains(AccessLevel.familyIllnesses)) t('Family illnesses'),
    ].join(' · ');

