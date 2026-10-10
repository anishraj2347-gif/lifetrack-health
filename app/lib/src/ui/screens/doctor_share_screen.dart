import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../consent/consent_token.dart';
import '../../share/access_requests.dart';
import '../../share/clinical_share_service.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/family_bar.dart';
import '../widgets/parts.dart';

/// P4: scan the doctor's verified code → see who they are → pick a level →
/// confirm medicines → share. Every step is the patient's own tap.
class DoctorShareScreen extends StatefulWidget {
  const DoctorShareScreen({super.key, this.request});

  /// A doctor's request by LifeTrack ID, already verified: the scan step is
  /// skipped and the levels they asked for are preselected. The patient can
  /// still lower them.
  final PendingRequest? request;
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

  /// How long the doctor can see it: 1 hour unless the patient picks more,
  /// or what a doctor's request asked for.
  int _hours = 1;

  @override
  void initState() {
    super.initState();
    final r = widget.request;
    if (r != null) {
      _doctor = r.doctor;
      _scanning = false;
      _levels
        ..clear()
        ..addAll(r.levels.isEmpty ? {AccessLevel.summary} : r.levels);
      _hours = r.request.accessHours ?? 1;
    }
  }

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
        filter: _lastTwoYears ? RecordFilter(from: at.subtract(Duration(days: 730))) : null,
        requested: widget.request?.levels,
        window: Duration(hours: _hours),
        at: at,
      );
      if (widget.request != null) await s.requests!.remove(widget.request!.request.requestId);
      if (!mounted) return;
      setState(() => _receipt = r);
      AppScope.changed(context);
    } on Object catch (e) {
      setState(() => _error = 'Not sent. ${plainError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GlassAppBar(),
        body: _receipt != null
            ? _done(_receipt!)
            : _doctor == null
                ? _scan()
                : _choose(_doctor!),
      );

  Widget _scan() => ListView(children: [
        Masthead(eyebrow: 'Share with a doctor', title: "Scan the doctor's code", description: 'Their LifeTrack screen shows a verified code. Nothing is shared until you choose.'),
        if (_scanning)
          Container(
            height: 320,
            margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(LT.radiusLg), color: LT.primary),
            child: Viewfinder(
              caption: "Point at the code on the doctor's screen",
              child: ReaderWidget(
                onScan: (code) {
                  final t = code.text;
                  if (t != null && t.isNotEmpty) _verify(t);
                },
                showGallery: false,
                showToggleCamera: false,
                showScannerOverlay: false,
                tryHarder: true,
              ),
            ),
          ),
        SizedBox(height: 12),
        if (_error != null)
          Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        LabeledField(
          label: 'Or paste the code',
          child: Padding(
            padding: EdgeInsets.only(top: 0),
            child: TextField(controller: _paste, maxLines: 2, decoration: InputDecoration(hintText: 'Code from the doctor\'s screen')),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 28),
          child: SlabButton('Check this doctor', variant: ButtonVariant.outline, icon: LucideIcons.shieldCheck, onPressed: () => _verify(_paste.text)),
        ),
      ]);

  Widget _choose(DoctorCertificate d) {
    final s = AppScope.of(context);
    final active = [for (final r in s.records()) if (r.isActiveAt(s.clock())) r];
    final p = s.currentPatient!;
    final whose = whoseRecords(context);
    final first = p.name.split(' ').first;
    return ListView(children: [
      // Whose records go, in words, before anything else: a caregiver who
      // switched profiles elsewhere must not share the wrong person's.
      Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: LT.raised,
            child: Text(FamilyBar.initials(p.name), style: TextStyle(fontWeight: FontWeight.w600, color: LT.ink)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text.rich(TextSpan(style: TextStyle(fontFamily: LT.body, fontSize: 15, color: LT.ink2), children: [
              TextSpan(text: 'Sharing '),
              TextSpan(text: p.id == s.selfPatientId ? 'your own records' : "${p.name}'s records", style: TextStyle(fontWeight: FontWeight.w600, color: LT.ink)),
            ])),
          ),
        ]),
      ),
      ShadCard(
        margin: EdgeInsets.fromLTRB(16, 8, 16, 16),
        color: LT.primary,
        child: Row(children: [
          IconTile(LucideIcons.stethoscope, color: LT.onDark, background: LT.onDarkChip),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LT.onDark)),
              Text('${d.speciality} · ${d.registrationNo}', style: TextStyle(fontSize: 14, color: LT.onDarkMuted)),
              Text(d.council, style: TextStyle(fontSize: 12, color: LT.onDarkMuted)),
            ]),
          ),
          Badge2('Verified', tone: BadgeTone.trace),
        ]),
      ),
      Eyebrow('What should this doctor see?', padding: EdgeInsets.fromLTRB(20, 0, 20, 10)),
      _level(AccessLevel.summary, 'Summary', 'Allergies, current medicines, conditions, latest results with their source', recommended: true),
      _level(AccessLevel.allReports, whose == 'your' ? 'All my reports' : "All of $whose reports", 'Every report, prescription and scan'),
      if (_levels.contains(AccessLevel.allReports))
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Chip2('Last 2 years only', exclusive: false, selected: _lastTwoYears, onTap: () => setState(() => _lastTwoYears = !_lastTwoYears)),
        ),
      _level(AccessLevel.familyIllnesses, 'Family illnesses', 'What you have told LifeTrack about your family, marked "patient-reported"'),
      _level(AccessLevel.homeReadings, 'Home BP & sugar readings', 'What you measured at home in the last 30 days, marked "measured at home"'),
      if (active.isNotEmpty) ...[
        Eyebrow('Are you still taking these?'),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('Tick the ones you still take; your doctor sees "confirmed today" on those. The others are still shown, without that mark.', style: LT.small),
        ),
        for (final r in active)
          CheckboxListTile(
            value: _stillTaking.contains(r.id),
            onChanged: (v) => setState(() => v! ? _stillTaking.add(r.id) : _stillTaking.remove(r.id)),
            title: Text('${r.title}${r.dose == null ? '' : ' · ${r.dose!.display}'}', style: LT.label.copyWith(fontSize: 15)),
            subtitle: Text(r.doctor ?? '', style: LT.small),
          ),
      ],
      Eyebrow('For how long?'),
      Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final h in AccessRequest.accessChoices) Chip2(hoursLabel(h), selected: _hours == h, onTap: () => setState(() => _hours = h)),
        ]),
      ),
      if (widget.request?.request.accessHours case final asked?)
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text('${d.name} asked for ${hoursLabel(asked)}. You can give less.', style: LT.small),
        ),
      Note('Access ends after ${hoursLabel(_hours)}; you can change the time or end it any time. Encrypted so only this doctor\'s device can open it. Personal notes are never included. The doctor keeps their own consult note.',
          icon: LucideIcons.lock),
      if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
        child: SlabButton(
          '${whose == 'your' ? 'Share' : 'Share $first\'s'} ${_levels.length == 1 ? levelsLabel(_levels) : 'records'} with ${d.name} · ${hoursLabel(_hours)}',
          icon: LucideIcons.send,
          onPressed: _busy || _levels.isEmpty ? null : _share,
        ),
      ),
    ]);
  }

  Widget _level(AccessLevel l, String title, String body, {bool recommended = false}) {
    final on = _levels.contains(l);
    return MergeSemantics(child: Semantics(checked: on, child: ShadCard(
      borderColor: on ? LT.ink : null,
      onTap: () => setState(() => on ? _levels.remove(l) : _levels.add(l)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GlassCheck(value: on),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              Text(title, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
              if (recommended) Badge2('Recommended'),
            ]),
            SizedBox(height: 4),
            Text(body, style: LT.small),
          ]),
        ),
      ]))));
  }

  Widget _done(ShareReceipt r) => ListView(children: [
        Padding(padding: EdgeInsets.only(top: 8), child: Center(child: DoneMark(size: 110))),
        Masthead(eyebrow: 'Shared', title: 'Sent to ${r.doctor.name}', description: 'Encrypted to their device. Access ends ${dateTime(r.grant.expiresAt)}.'),
        Note('If they have not opened it yet, ending access removes it. If they already have, their app is asked to close it — LifeTrack cannot take back what they have seen.', icon: LucideIcons.info),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: SlabButton('End access now', variant: ButtonVariant.outline, onPressed: () async {
            await AppScope.of(context).sharing!.endAccess(r.grant, AppScope.of(context).clock());
            if (!mounted) return;
            AppScope.changed(context);
            Navigator.of(context).pop();
          }),
        ),
        Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 28), child: SlabButton('Done', onPressed: () => Navigator.of(context).pop())),
      ]);
}

/// Whether [r] is a clinical share grant (vs an on-device one).
bool isClinicalShare(ConsentToken g) => g.granteeKeyId != null;

String levelsLabel(Set<AccessLevel> l) => [
      if (l.contains(AccessLevel.summary)) 'Summary',
      if (l.contains(AccessLevel.allReports)) 'All reports',
      if (l.contains(AccessLevel.familyIllnesses)) 'Family illnesses',
      if (l.contains(AccessLevel.homeReadings)) 'Home readings',
    ].join(' · ');

/// "1 hour", "4 hours", "1 day", "2 days".
String hoursLabel(int h) => h == 24 ? '1 day' : h == 48 ? '2 days' : h == 1 ? '1 hour' : '$h hours';
