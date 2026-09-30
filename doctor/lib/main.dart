import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'session.dart';
import 'summary.dart';
import 'theme.dart';

const _relay = String.fromEnvironment('LT_RELAY_URL', defaultValue: 'http://127.0.0.1:8787');

void main() => runApp(const DoctorApp());

class DoctorApp extends StatelessWidget {
  const DoctorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LifeTrack for doctors',
    debugShowCheckedModeBanner: false,
    theme: DT.theme(),
    home: FutureBuilder<DoctorSession>(
      future: DoctorSession.load(Uri.parse(_relay)),
      builder: (c, s) => s.hasData ? Shell(session: s.data!) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});
  final DoctorSession session;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  DoctorSession get s => widget.session;
  Timer? _poll;
  String? _error;
  ReceivedShare? _open;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      if (s.state == EnrolmentState.pending) await s.refreshStatus();
      if (s.state == EnrolmentState.approved && s.certificateQr != null) await s.pickUp();
      await s.closeExpired(DateTime.now());
      if (s.closedByPatient.isNotEmpty && mounted) {
        for (final name in s.closedByPatient) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name ended access. Their shared records are closed.')));
        }
        s.closedByPatient.clear();
      }
      if (_open != null && !s.inbox.contains(_open)) _open = null;
      _error = null;
    } on Object catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: switch (s.state) {
        EnrolmentState.none => EnrolScreen(session: s, onDone: () => setState(() {})),
        EnrolmentState.pending || EnrolmentState.rejected || EnrolmentState.revoked => _waiting(),
        EnrolmentState.approved => _home(),
      },
    ),
  );

  Widget _waiting() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card0(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.state == EnrolmentState.pending ? 'Waiting for your licence check' : 'Not approved', style: DT.h1),
            const SizedBox(height: 8),
            Text(s.note ?? 'A LifeTrack reviewer checks your registration with your medical council before you can see any patient record.', style: DT.muted),
            const SizedBox(height: 16),
            Text('${s.profile['name']} · ${s.registrationNo} · ${s.profile['council']}', style: DT.body),
            const SizedBox(height: 20),
            Row(
              children: [
                Pill('Check again', onTap: _tick),
                const SizedBox(width: 8),
                Pill(
                  'Start over',
                  dark: false,
                  onTap: () async {
                    await s.forget();
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _home() {
    final now = DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('LifeTrack for doctors', style: DT.muted),
              const SizedBox(height: 4),
              Text('${s.profile['name']}', style: DT.h1),
              Text('${s.profile['speciality']} · ${s.registrationNo}', style: DT.muted),
              const SizedBox(height: 20),
              Card0(
                dark: true,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: DT.raised, borderRadius: BorderRadius.circular(16)),
                      child: QrImageView(data: s.certificateQr!, size: 240, backgroundColor: DT.raised),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your verified code',
                      style: TextStyle(color: DT.onDark, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The patient scans this with LifeTrack, sees your name and registration, and chooses what to share.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DT.onDarkMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text('Copy code instead', style: DT.muted),
                children: [SelectableText(s.certificateQr!, style: const TextStyle(fontSize: 10))],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: DT.signal)),
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: DT.ground,
            child: _open == null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text('Shared with you', style: DT.h1),
                      const SizedBox(height: 4),
                      Text('Shares arrive here the moment a patient approves. They close when access ends.', style: DT.muted),
                      const SizedBox(height: 16),
                      if (s.inbox.isEmpty) Card0(child: Text('Nothing yet. Ask the patient to scan your code.', style: DT.body)),
                      for (final sh in s.inbox)
                        Card0(
                          onTap: () => setState(() => _open = sh),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: DT.accent,
                                child: Text(
                                  sh.patientName.characters.first,
                                  style: const TextStyle(color: DT.ink, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${sh.patientName} · ${sh.patient['age']}', style: DT.h2),
                                    Text(((sh.bundle['levels'] as List?) ?? const []).join(' · '), style: DT.muted),
                                  ],
                                ),
                              ),
                              Countdown(until: sh.expiresAt),
                            ],
                          ),
                        ),
                    ],
                  )
                : PatientScreen(session: s, share: _open!, onClose: () => setState(() => _open = null), now: now),
          ),
        ),
      ],
    );
  }
}

class EnrolScreen extends StatefulWidget {
  const EnrolScreen({super.key, required this.session, required this.onDone});
  final DoctorSession session;
  final VoidCallback onDone;
  @override
  State<EnrolScreen> createState() => _EnrolScreenState();
}

class _EnrolScreenState extends State<EnrolScreen> {
  final _name = TextEditingController();
  final _spec = TextEditingController();
  final _council = TextEditingController();
  final _reg = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text('LifeTrack for doctors', style: DT.muted),
          Text('Verify your licence', style: DT.h1),
          const SizedBox(height: 8),
          Text(
            'Your registration is checked with your medical council before you can see any patient record. This browser makes its own keys; only their public halves are sent.',
            style: DT.muted,
          ),
          const SizedBox(height: 20),
          Field('Full name', _name, hint: 'Dr. R. Mehta'),
          Field('Speciality', _spec, hint: 'Cardiology'),
          Field('Medical council', _council, hint: 'Delhi Medical Council'),
          Field('Registration number', _reg, hint: 'DMC-12345'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: DT.signal)),
            ),
          Pill(
            _busy ? 'Sending…' : 'Send for licence check',
            onTap: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.session.enrol(
                        name: _name.text.trim(),
                        speciality: _spec.text.trim(),
                        council: _council.text.trim(),
                        registrationNo: _reg.text.trim(),
                      );
                      widget.onDone();
                    } on Object catch (e) {
                      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
        ],
      ),
    ),
  );
}

class PatientScreen extends StatefulWidget {
  const PatientScreen({super.key, required this.session, required this.share, required this.onClose, required this.now});
  final DoctorSession session;
  final ReceivedShare share;
  final VoidCallback onClose;
  final DateTime now;
  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen> {
  final _med = TextEditingController();
  final _ing = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _note = TextEditingController();
  final _dose = [0, 0, 1];
  final _qual = TextEditingController(text: 'MBBS, MD');
  String? _timing = 'after_food';

  static const _timings = {'before_food': 'Before food', 'after_food': 'After food', 'with_food': 'With food', null: 'Any time'};
  SignedPrescription? _sent;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final sh = widget.share;
    final p = sh.patient;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            TextButton(onPressed: widget.onClose, child: const Text('← All shares')),
            const Spacer(),
            Countdown(until: sh.expiresAt),
          ],
        ),
        Card0(
          dark: true,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['name']} · ${p['sex'] == 'female'
                          ? 'F'
                          : p['sex'] == 'male'
                          ? 'M'
                          : '—'} · ${p['age']}',
                      style: const TextStyle(color: DT.onDark, fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    if (sh.bundle['sharedBy'] != null)
                      Text(
                        'Shared on their behalf by ${sh.bundle['sharedBy']}',
                        style: const TextStyle(color: DT.accent, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    Text(
                      'Read-only · shared ${sh.receivedAt.toString().substring(11, 16)} · ${((sh.bundle['levels'] as List?) ?? const []).join(' · ')}',
                      style: const TextStyle(color: DT.onDarkMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (c, box) {
            final wide = box.maxWidth > 900;
            final left = SummaryPanel(bundle: sh.bundle);
            final right = _prescribe(sh);
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: left),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: right),
                    ],
                  )
                : Column(children: [left, right]);
          },
        ),
      ],
    );
  }

  Widget _prescribe(ReceivedShare sh) {
    if (_sent != null) {
      final rx = _sent!;
      return Card0(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sent to ${sh.patientName}', style: DT.h2),
            const SizedBox(height: 6),
            Text('Signed and encrypted to their phone. It appears in their records as signed by you.', style: DT.muted),
            const Divider(height: 24),
            Text('Your copy — keep it in your consult record', style: DT.muted),
            const SizedBox(height: 6),
            SelectableText(
              '${rx.medicine}${rx.ingredient == null ? '' : ' (${rx.ingredient})'}\n'
              'Dose ${rx.morning}-${rx.afternoon}-${rx.night} · ${_timings[rx.timing]} · ${rx.days} days\n'
              '${rx.note ?? ''}\n'
              '${rx.doctorName}, ${rx.qualification} · Reg. ${rx.registrationNo}\n'
              'Issued ${rx.issuedAt.toLocal().toString().substring(0, 16)} for ${sh.patientName}',
              style: DT.body,
            ),
            const SizedBox(height: 12),
            Pill('Write another', dark: false, onTap: () => setState(() => _sent = null)),
          ],
        ),
      );
    }
    return Card0(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Write a prescription', style: DT.h2),
          Text('For ${sh.patientName} only.', style: DT.muted),
          const SizedBox(height: 12),
          Field('Medicine', _med, hint: 'Atorvastatin 10 mg'),
          Field('Active ingredient', _ing, hint: 'atorvastatin'),
          Text('Dose · morning, afternoon, night', style: DT.label),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _dose[i] = (_dose[i] + 1) % 4),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _dose[i] > 0 ? DT.ink : DT.raised, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        '${_dose[i]}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: _dose[i] > 0 ? DT.accent : DT.ink),
                      ),
                    ),
                  ),
                ),
                if (i < 2) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text('When to take it', style: DT.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry(key: k, value: label) in _timings.entries)
                ChoiceChip(
                  label: Text(label),
                  selected: _timing == k,
                  onSelected: (_) => setState(() => _timing = k),
                  selectedColor: DT.ink,
                  labelStyle: TextStyle(color: _timing == k ? DT.onDark : DT.ink, fontWeight: FontWeight.w500),
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Field('Days', _days),
          Field('Note to patient', _note, hint: 'Repeat lipid panel in 3 months'),
          Field('Your qualification', _qual),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: DT.signal)),
            ),
          Pill(
            'Sign and send',
            onTap: () async {
              if (_med.text.trim().isEmpty) {
                setState(() => _error = 'Name the medicine.');
                return;
              }
              final s = widget.session;
              try {
                final rx = await s.sendPrescription(
                  sh,
                  SignedPrescription(
                    patientId: (sh.bundle['patientRef'] as String?) ?? '',
                    doctorRegistryId: s.registrationNo,
                    doctorName: s.profile['name']!,
                    qualification: _qual.text.trim(),
                    registrationNo: s.registrationNo,
                    medicine: _med.text.trim(),
                    ingredient: _ing.text.trim().isEmpty ? null : _ing.text.trim().toLowerCase(),
                    morning: _dose[0],
                    afternoon: _dose[1],
                    night: _dose[2],
                    days: int.tryParse(_days.text) ?? 30,
                    issuedAt: DateTime.now().toUtc(),
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                    timing: _timing,
                  ),
                );
                setState(() {
                  _sent = rx;
                  _error = null;
                });
              } on Object catch (e) {
                setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
              }
            },
          ),
        ],
      ),
    );
  }
}

class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.until});
  final DateTime until;
  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.until.difference(DateTime.now());
    final txt = d.isNegative ? 'Closed' : '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')} left';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const ShapeDecoration(color: DT.accent, shape: StadiumBorder()),
      child: Text(
        txt,
        style: const TextStyle(fontWeight: FontWeight.w600, color: DT.ink),
      ),
    );
  }
}
