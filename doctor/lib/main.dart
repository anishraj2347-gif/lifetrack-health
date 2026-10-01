import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';

import 'patients.dart';
import 'session.dart';
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

  /// Patients · Prescriptions · My code. Wide screens keep the code in a
  /// side panel; phones get a bottom bar.
  int _tab = 0;
  String? _openKey;
  SignedPrescription? _prefill;

  void _openPatient(String key, {SignedPrescription? prefill}) => setState(() {
        _openKey = key;
        _prefill = prefill;
      });

  Widget _home() => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final Widget content = _openKey != null
            ? PatientScreen(
                key: ValueKey('$_openKey/${_prefill?.issuedAt}'),
                session: s,
                patientKey: _openKey!,
                prefill: _prefill,
                onClose: () => setState(() {
                  _openKey = null;
                  _prefill = null;
                }),
                onChanged: () => setState(() {}),
              )
            : switch (wide && _tab == 2 ? 0 : _tab) {
                0 => PatientsTab(session: s, onOpen: _openPatient, onChanged: () => setState(() {})),
                1 => PrescriptionsTab(session: s, onOpenPatient: _openPatient, onWriteAgain: (e) => _openPatient(e.patientKey, prefill: e.rx)),
                _ => MyCodePanel(session: s, error: _error),
              };
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 340, child: MyCodePanel(session: s, error: _error)),
            Expanded(
              child: Container(
                color: DT.ground,
                child: Column(children: [
                  if (_openKey == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<int>(
                          segments: [
                            ButtonSegment(value: 0, label: Text('Patients · ${s.patients.length}'), icon: const Icon(Icons.people_outline)),
                            ButtonSegment(value: 1, label: Text('Prescriptions · ${s.prescriptions.length}'), icon: const Icon(Icons.receipt_long_outlined)),
                          ],
                          selected: {_tab == 2 ? 0 : _tab},
                          onSelectionChanged: (v) => setState(() => _tab = v.first),
                        ),
                      ),
                    ),
                  Expanded(child: content),
                ]),
              ),
            ),
          ]);
        }
        return Scaffold(
          backgroundColor: DT.ground,
          body: content,
          bottomNavigationBar: _openKey != null
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    NavigationDestination(icon: Badge(isLabelVisible: s.inbox.isNotEmpty, label: Text('${s.inbox.length}'), child: const Icon(Icons.people_outline)), label: 'Patients'),
                    const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Prescriptions'),
                    const NavigationDestination(icon: Icon(Icons.qr_code_2), label: 'My code'),
                  ],
                ),
        );
      });
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

/// Ask a patient for access by their 12-digit LifeTrack ID. The patient sees
/// who is asking and for what, and approves, lowers or declines.
class RequestByIdCard extends StatefulWidget {
  const RequestByIdCard({super.key, required this.session, required this.onSent});
  final DoctorSession session;
  final VoidCallback onSent;
  @override
  State<RequestByIdCard> createState() => _RequestByIdCardState();
}

class _RequestByIdCardState extends State<RequestByIdCard> {
  final _id = TextEditingController();
  final _note = TextEditingController();
  final Set<String> _levels = {'summary'};
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  static const _labels = {'summary': 'Summary', 'allReports': 'All reports', 'familyIllnesses': 'Family illnesses', 'homeReadings': 'Home readings'};

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await widget.session.requestAccess(lifeTrackId: _id.text, levels: [for (final l in _labels.keys) if (_levels.contains(l)) l], note: _note.text);
      _ok = true;
      _msg = 'Request sent. It appears on the patient\'s phone when they check for updates.';
      _id.clear();
      _note.clear();
      widget.onSent();
    } on Object catch (e) {
      _ok = false;
      _msg = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Card0(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Request access by LifeTrack ID', style: DT.h2),
        const SizedBox(height: 4),
        Text('For a patient who is not in front of you. They approve on their phone.', style: DT.muted),
        const SizedBox(height: 12),
        Field('LifeTrack ID (12 digits)', _id, hint: '1482 0937 5516'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final e in _labels.entries)
            FilterChip(
              label: Text(e.value),
              selected: _levels.contains(e.key),
              onSelected: (v) => setState(() => v ? _levels.add(e.key) : _levels.remove(e.key)),
            ),
        ]),
        const SizedBox(height: 8),
        Field('Reason (optional)', _note, hint: 'Follow-up for diabetes'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: _busy || _levels.isEmpty ? null : _send, child: Text(_busy ? 'Sending…' : 'Send request')),
        ),
        if (_msg != null) ...[
          const SizedBox(height: 8),
          Text(_msg!, style: TextStyle(color: _ok ? DT.trace : DT.signal)),
        ],
        for (final r in s.sent.take(5)) ...[
          const SizedBox(height: 6),
          Text('${r.declined ? 'Declined' : 'Sent'} · ${r.lifeTrackId.substring(0, 4)} ${r.lifeTrackId.substring(4, 8)} ${r.lifeTrackId.substring(8)} · ${r.levels.map((l) => _labels[l]).join(', ')}',
              style: TextStyle(fontSize: 12.5, color: r.declined ? DT.signal : DT.ink3)),
        ],
      ]),
    );
  }
}
