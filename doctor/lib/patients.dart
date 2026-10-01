import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'main.dart' show Countdown, RequestByIdCard;
import 'practice.dart';
import 'print_rx.dart';
import 'session.dart';
import 'summary.dart';
import 'theme.dart';

const accessLabels = {'summary': 'Summary', 'allReports': 'All reports', 'familyIllnesses': 'Family illnesses', 'homeReadings': 'Home readings'};
const timingLabels = {'before_food': 'Before food', 'after_food': 'After food', 'with_food': 'With food', null: 'Any time'};

/// Narrow screens (phones) get tighter padding.
EdgeInsets pagePadding(BuildContext context) => EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24);

String doseLine(SignedPrescription rx) => 'Dose ${rx.morning}-${rx.afternoon}-${rx.night} · ${timingLabels[rx.timing] ?? 'Any time'} · ${rx.days} days';

Future<void> printRx(DoctorSession s, RxEntry e) => printPrescription(
      rx: e.rx,
      patientName: e.patientName,
      patientLine: e.patientLine,
      council: s.profile['council'] ?? '',
      speciality: s.profile['speciality'] ?? '',
    );

/// The next follow-up date the doctor set for [key] that is today or later.
DateTime? nextFollowUp(DoctorSession s, String key, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final dates = [for (final n in s.notesFor(key)) if (n.followUp != null && !n.followUp!.isBefore(today)) n.followUp!]..sort();
  return dates.firstOrNull;
}

// ---------------------------------------------------------------------------

/// The doctor's verified QR, for a patient in front of them to scan.
class MyCodePanel extends StatelessWidget {
  const MyCodePanel({super.key, required this.session, this.error});
  final DoctorSession session;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final size = (MediaQuery.sizeOf(context).width - 120).clamp(160.0, 240.0);
    return ListView(
      padding: pagePadding(context),
      children: [
        Text('LifeTrack for doctors', style: DT.muted),
        const SizedBox(height: 4),
        Text('${s.profile['name']}', style: DT.h1),
        Text('${s.profile['speciality']} · ${s.registrationNo}', style: DT.muted),
        const SizedBox(height: 20),
        Card0(
          dark: true,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: DT.raised, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: s.certificateQr!, size: size, backgroundColor: DT.raised),
            ),
            const SizedBox(height: 12),
            const Text('Your verified code', style: TextStyle(color: DT.onDark, fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'The patient scans this with LifeTrack, sees your name and registration, and chooses what to share.',
              textAlign: TextAlign.center,
              style: TextStyle(color: DT.onDarkMuted, fontSize: 12.5),
            ),
          ]),
        ),
        ExpansionTile(
          title: Text('Copy code instead', style: DT.muted),
          children: [SelectableText(s.certificateQr!, style: const TextStyle(fontSize: 10))],
        ),
        Card0(
          child: Text(
            'What this browser keeps — your keys, patients, prescriptions and notes — is encrypted under a key held by this browser, which this page can use but not read out. Use this on your own device, with its screen lock on.',
            style: DT.muted,
          ),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: DT.signal))),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Everyone who has shared with this doctor: open shares first, then the
/// whole register, most recent first.
class PatientsTab extends StatefulWidget {
  const PatientsTab({super.key, required this.session, required this.onOpen, required this.onChanged});
  final DoctorSession session;
  final ValueChanged<String> onOpen;
  final VoidCallback onChanged;
  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final now = DateTime.now();
    bool match(String name, String? id) => _q.isEmpty || name.toLowerCase().contains(_q) || (id ?? '').contains(_q.replaceAll(' ', ''));
    final open = [for (final sh in s.inbox) if (match(sh.patientName, sh.patient['lifeTrackId'] as String?)) sh];
    final all = [for (final p in s.patients) if (match(p.name, p.lifeTrackId)) p];
    return ListView(
      padding: pagePadding(context),
      children: [
        Text('My patients', style: DT.h1),
        const SizedBox(height: 4),
        Text('Everyone who has shared with you. Shared records close when access ends; your notes and prescriptions stay here.', style: DT.muted),
        const SizedBox(height: 14),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name or LifeTrack ID'),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 14),
        RequestByIdCard(session: s, onSent: widget.onChanged),
        if (open.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Shared now', style: DT.h2),
          const SizedBox(height: 8),
          for (final sh in open)
            Card0(
              onTap: () => widget.onOpen(sh.patientKey),
              child: Row(children: [
                _Avatar(sh.patientName, accent: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text([sh.patientName, if (sh.patientLine.isNotEmpty) sh.patientLine].join(' · '), style: DT.h2),
                    Text([for (final l in (sh.bundle['levels'] as List?) ?? const []) accessLabels[l] ?? '$l'].join(' · '), style: DT.muted),
                  ]),
                ),
                Countdown(until: sh.expiresAt),
              ]),
            ),
        ],
        const SizedBox(height: 4),
        Text('All patients · ${s.patients.length}', style: DT.h2),
        const SizedBox(height: 8),
        if (s.patients.isEmpty)
          Card0(child: Text('No patients yet. Ask a patient to scan your code, or request access by their LifeTrack ID.', style: DT.body))
        else if (all.isEmpty)
          Card0(child: Text('No patient matches "$_q".', style: DT.body)),
        for (final p in all)
          Card0(
            onTap: () => widget.onOpen(p.key),
            child: Row(children: [
              _Avatar(p.name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([p.name, if (p.sexAge.isNotEmpty) p.sexAge].join(' · '), style: DT.h2),
                  Text(
                    'Last shared ${fmtDate(p.lastShared)} · ${p.shares} ${p.shares == 1 ? 'time' : 'times'}'
                    '${s.prescriptionsFor(p.key).isEmpty ? '' : ' · ${s.prescriptionsFor(p.key).length} Rx'}',
                    style: DT.muted,
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Wrap(direction: Axis.vertical, crossAxisAlignment: WrapCrossAlignment.end, spacing: 4, children: [
                s.openShareFor(p.key) != null ? const Tag('Open', color: DT.accent) : const Tag('Closed'),
                if (nextFollowUp(s, p.key, now) case final f?) Tag('Follow-up ${fmtDate(f)}', color: DT.caution, ink: DT.cautionInk),
              ]),
            ]),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.accent = false});
  final String name;
  final bool accent;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: accent ? DT.accent : DT.surface,
        child: Text(name.isEmpty ? '?' : name.characters.first, style: const TextStyle(color: DT.ink, fontWeight: FontWeight.w600)),
      );
}

// ---------------------------------------------------------------------------

/// Every prescription this doctor signed, newest first.
class PrescriptionsTab extends StatefulWidget {
  const PrescriptionsTab({super.key, required this.session, required this.onOpenPatient, required this.onWriteAgain});
  final DoctorSession session;
  final ValueChanged<String> onOpenPatient;
  final ValueChanged<RxEntry> onWriteAgain;
  @override
  State<PrescriptionsTab> createState() => _PrescriptionsTabState();
}

class _PrescriptionsTabState extends State<PrescriptionsTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final shown = [
      for (final e in s.prescriptions)
        if (_q.isEmpty || e.patientName.toLowerCase().contains(_q) || e.rx.medicine.toLowerCase().contains(_q) || (e.rx.ingredient ?? '').contains(_q)) e,
    ];
    return ListView(
      padding: pagePadding(context),
      children: [
        Text('Prescriptions', style: DT.h1),
        const SizedBox(height: 4),
        Text('Every prescription you signed and sent, newest first. Print one again, or write it again for the same patient while their access is open.', style: DT.muted),
        const SizedBox(height: 14),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by medicine or patient'),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 14),
        if (s.prescriptions.isEmpty) Card0(child: Text('None yet. Prescriptions you sign appear here.', style: DT.body)),
        for (final e in shown) RxCard(session: s, entry: e, onOpenPatient: widget.onOpenPatient, onWriteAgain: widget.onWriteAgain),
      ],
    );
  }
}

class RxCard extends StatelessWidget {
  const RxCard({super.key, required this.session, required this.entry, this.onOpenPatient, this.onWriteAgain});
  final DoctorSession session;
  final RxEntry entry;
  final ValueChanged<String>? onOpenPatient;
  final ValueChanged<RxEntry>? onWriteAgain;

  @override
  Widget build(BuildContext context) {
    final rx = entry.rx;
    final open = session.openShareFor(entry.patientKey) != null;
    return Card0(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text('${rx.medicine}${rx.ingredient == null ? '' : ' (${rx.ingredient})'}', style: DT.h2)),
          Text(fmtDate(rx.issuedAt), style: DT.muted),
        ]),
        const SizedBox(height: 2),
        Text([entry.patientName, if (entry.patientLine.isNotEmpty) entry.patientLine].join(' · '), style: DT.label),
        Text(doseLine(rx), style: DT.muted),
        if (rx.note != null && rx.note!.isNotEmpty) Text(rx.note!, style: DT.muted),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => printRx(session, entry), icon: const Icon(Icons.print_outlined, size: 18), label: const Text('Print / PDF')),
          if (onOpenPatient != null) OutlinedButton(onPressed: () => onOpenPatient!(entry.patientKey), child: const Text('Open patient')),
          if (onWriteAgain != null)
            Tooltip(
              message: open ? 'Prefills a new prescription' : 'Their access is closed — ask for access again to prescribe',
              child: OutlinedButton(onPressed: open ? () => onWriteAgain!(entry) : null, child: const Text('Write again')),
            ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

/// One patient: their shared records while access is open, a prescription
/// form, the doctor's private notes and the prescriptions already written.
class PatientScreen extends StatefulWidget {
  const PatientScreen({super.key, required this.session, required this.patientKey, required this.onClose, required this.onChanged, this.prefill});
  final DoctorSession session;
  final String patientKey;
  final VoidCallback onClose;
  final VoidCallback onChanged;
  final SignedPrescription? prefill;
  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen> {
  DoctorSession get s => widget.session;

  @override
  Widget build(BuildContext context) {
    final sh = s.openShareFor(widget.patientKey);
    final p = s.patientByKey(widget.patientKey);
    final name = sh?.patientName ?? p?.name ?? 'Patient';
    final line = sh?.patientLine ?? p?.sexAge ?? '';
    final ltId = (sh?.patient['lifeTrackId'] as String?) ?? p?.lifeTrackId;
    final notes = NotesCard(session: s, patientKey: widget.patientKey, onChanged: () => setState(() {}));
    final history = _HistoryCard(session: s, patientKey: widget.patientKey);
    return ListView(
      padding: pagePadding(context),
      children: [
        Row(children: [
          TextButton(onPressed: widget.onClose, child: const Text('← Patients')),
          const Spacer(),
          if (sh != null) Countdown(until: sh.expiresAt) else const Tag('Access closed'),
        ]),
        Card0(
          dark: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([name, if (line.isNotEmpty) line].join(' · '), style: const TextStyle(color: DT.onDark, fontSize: 20, fontWeight: FontWeight.w600)),
            if (ltId != null) Text('LifeTrack ID ${fmtLifeTrackId(ltId)}', style: const TextStyle(color: DT.onDarkMuted, fontSize: 12.5)),
            if (sh?.bundle['sharedBy'] != null)
              Text('Shared on their behalf by ${sh!.bundle['sharedBy']}', style: const TextStyle(color: DT.accent, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              sh != null
                  ? 'Read-only · shared ${fmtDateTime(sh.receivedAt)} · ${[for (final l in (sh.bundle['levels'] as List?) ?? const []) accessLabels[l] ?? '$l'].join(' · ')}'
                  : p == null
                      ? ''
                      : 'First shared ${fmtDate(p.firstSeen)} · last ${fmtDate(p.lastShared)} · ${p.shares} ${p.shares == 1 ? 'time' : 'times'}',
              style: const TextStyle(color: DT.onDarkMuted, fontSize: 12.5),
            ),
          ]),
        ),
        LayoutBuilder(builder: (c, box) {
          final wide = box.maxWidth > 900;
          final left = sh != null ? SummaryPanel(bundle: sh.bundle) : _ClosedCard(session: s, lifeTrackId: ltId, onSent: widget.onChanged);
          final right = Column(children: [
            if (sh != null)
              PrescribeCard(
                session: s,
                share: sh,
                prefill: widget.prefill,
                onSent: () {
                  setState(() {});
                  widget.onChanged();
                },
              ),
            notes,
            history,
          ]);
          return wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: left),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: right),
                ])
              : Column(children: [left, right]);
        }),
      ],
    );
  }
}

class _ClosedCard extends StatefulWidget {
  const _ClosedCard({required this.session, required this.lifeTrackId, required this.onSent});
  final DoctorSession session;
  final String? lifeTrackId;
  final VoidCallback onSent;
  @override
  State<_ClosedCard> createState() => _ClosedCardState();
}

class _ClosedCardState extends State<_ClosedCard> {
  final Set<String> _levels = {'summary'};
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await widget.session.requestAccess(lifeTrackId: widget.lifeTrackId!, levels: [for (final l in accessLabels.keys) if (_levels.contains(l)) l]);
      _ok = true;
      _msg = 'Request sent. It appears on their phone; nothing is shared until they approve.';
      widget.onSent();
    } on Object catch (e) {
      _ok = false;
      _msg = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card0(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Their shared records are closed', style: DT.h2),
          const SizedBox(height: 4),
          Text('Access ended. Your own notes and the prescriptions you wrote are below.', style: DT.muted),
          const SizedBox(height: 12),
          if (widget.lifeTrackId == null)
            Text('To see their records again, ask them to scan your code.', style: DT.body)
          else ...[
            Text('Ask for access again', style: DT.label),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in accessLabels.entries)
                FilterChip(label: Text(e.value), selected: _levels.contains(e.key), onSelected: (v) => setState(() => v ? _levels.add(e.key) : _levels.remove(e.key))),
            ]),
            const SizedBox(height: 10),
            FilledButton(onPressed: _busy || _levels.isEmpty ? null : _ask, child: Text(_busy ? 'Sending…' : 'Send request')),
          ],
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: _ok ? DT.trace : DT.signal))),
        ]),
      );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.session, required this.patientKey});
  final DoctorSession session;
  final String patientKey;
  @override
  Widget build(BuildContext context) {
    final list = session.prescriptionsFor(patientKey);
    return Card0(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Prescriptions you wrote · ${list.length}', style: DT.h2),
        const SizedBox(height: 8),
        if (list.isEmpty) Text('None yet.', style: DT.muted),
        for (final e in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.rx.medicine, style: DT.label),
                  Text('${fmtDate(e.rx.issuedAt)} · ${doseLine(e.rx)}', style: DT.muted),
                ]),
              ),
              IconButton(tooltip: 'Print / PDF', onPressed: () => printRx(session, e), icon: const Icon(Icons.print_outlined, size: 20)),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

/// The doctor's private notes for one patient: add, edit, delete.
class NotesCard extends StatefulWidget {
  const NotesCard({super.key, required this.session, required this.patientKey, required this.onChanged});
  final DoctorSession session;
  final String patientKey;
  final VoidCallback onChanged;
  @override
  State<NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<NotesCard> {
  ConsultNote? _editing;
  bool _adding = false;
  final _complaint = TextEditingController();
  final _findings = TextEditingController();
  final _advice = TextEditingController();
  DateTime? _followUp;
  String? _error;

  void _start(ConsultNote? n) => setState(() {
        _editing = n;
        _adding = n == null;
        _complaint.text = n?.complaint ?? '';
        _findings.text = n?.findings ?? '';
        _advice.text = n?.advice ?? '';
        _followUp = n?.followUp;
        _error = null;
      });

  void _stop() => setState(() {
        _editing = null;
        _adding = false;
      });

  Future<void> _save() async {
    final n = ConsultNote(
      id: _editing?.id ?? DoctorSession.newNoteId(),
      patientKey: widget.patientKey,
      at: _editing?.at ?? DateTime.now(),
      complaint: _complaint.text.trim(),
      findings: _findings.text.trim(),
      advice: _advice.text.trim(),
      followUp: _followUp,
    );
    if (n.isEmpty) return setState(() => _error = 'Write something first.');
    try {
      await widget.session.saveNote(n);
      _stop();
      widget.onChanged();
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.session.notesFor(widget.patientKey);
    final form = _adding || _editing != null;
    return Card0(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Consult notes · ${list.length}', style: DT.h2)),
          if (!form) TextButton.icon(onPressed: () => _start(null), icon: const Icon(Icons.add, size: 18), label: const Text('Add note')),
        ]),
        Text('Private to you. Encrypted in this browser; never sent to the patient or to LifeTrack.', style: DT.muted),
        const SizedBox(height: 10),
        if (form) ...[
          Field('Complaint', _complaint, hint: 'Tiredness for 2 weeks', maxLines: 3),
          Field('Findings / impression', _findings, hint: 'BP 138/88; HbA1c trending down', maxLines: 4),
          Field('Advice / plan', _advice, hint: 'Continue metformin; walk 30 min daily', maxLines: 4),
          Text('Follow-up', style: DT.label),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text(_followUp == null ? 'Set a date' : fmtDate(_followUp!)),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, initialDate: _followUp ?? now.add(const Duration(days: 14)), firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 2));
                if (d != null) setState(() => _followUp = d);
              },
            ),
            if (_followUp != null) TextButton(onPressed: () => setState(() => _followUp = null), child: const Text('No follow-up')),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: DT.signal))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Pill(_editing != null ? 'Save changes' : 'Save note', onTap: _save),
            Pill('Cancel', dark: false, onTap: _stop),
          ]),
          const Divider(height: 28),
        ],
        if (list.isEmpty && !form) Text('No notes yet.', style: DT.muted),
        for (final n in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtDateTime(n.at), style: DT.label),
                  if (n.complaint.isNotEmpty) Text('Complaint: ${n.complaint}', style: DT.body),
                  if (n.findings.isNotEmpty) Text('Findings: ${n.findings}', style: DT.body),
                  if (n.advice.isNotEmpty) Text('Plan: ${n.advice}', style: DT.body),
                  if (n.followUp != null) Text('Follow-up ${fmtDate(n.followUp!)}', style: const TextStyle(color: DT.cautionInk, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) async {
                  if (v == 'edit') _start(n);
                  if (v == 'copy') await Clipboard.setData(ClipboardData(text: [n.complaint, n.findings, n.advice].where((x) => x.isNotEmpty).join('\n')));
                  if (v == 'delete' && context.mounted) {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Delete this note?'),
                        content: Text('The note from ${fmtDateTime(n.at)} is removed from this browser.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await widget.session.deleteNote(n.id);
                      setState(() {});
                      widget.onChanged();
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'copy', child: Text('Copy text')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

/// Write, sign and send a prescription for the patient whose share is open.
class PrescribeCard extends StatefulWidget {
  const PrescribeCard({super.key, required this.session, required this.share, required this.onSent, this.prefill});
  final DoctorSession session;
  final ReceivedShare share;
  final VoidCallback onSent;
  final SignedPrescription? prefill;
  @override
  State<PrescribeCard> createState() => _PrescribeCardState();
}

class _PrescribeCardState extends State<PrescribeCard> {
  late final _med = TextEditingController(text: widget.prefill?.medicine);
  late final _ing = TextEditingController(text: widget.prefill?.ingredient);
  late final _days = TextEditingController(text: '${widget.prefill?.days ?? 30}');
  late final _note = TextEditingController(text: widget.prefill?.note);
  late final _dose = [widget.prefill?.morning ?? 0, widget.prefill?.afternoon ?? 0, widget.prefill?.night ?? 1];
  late final _qual = TextEditingController(text: widget.prefill?.qualification ?? 'MBBS, MD');
  late String? _timing = widget.prefill == null ? 'after_food' : widget.prefill!.timing;
  SignedPrescription? _sent;
  String? _error;
  bool _busy = false;

  Future<void> _send() async {
    if (_med.text.trim().isEmpty) return setState(() => _error = 'Name the medicine.');
    final days = int.tryParse(_days.text.trim());
    if (days == null || days < 1 || days > 365) return setState(() => _error = 'Days must be a number from 1 to 365.');
    if (_dose.every((d) => d == 0)) return setState(() => _error = 'Set at least one dose.');
    final s = widget.session;
    final sh = widget.share;
    setState(() => _busy = true);
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
          days: days,
          issuedAt: DateTime.now().toUtc(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          timing: _timing,
        ),
      );
      setState(() {
        _sent = rx;
        _error = null;
      });
      widget.onSent();
    } on Object catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sh = widget.share;
    if (_sent != null) {
      final rx = _sent!;
      return Card0(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sent to ${sh.patientName}', style: DT.h2),
          const SizedBox(height: 6),
          Text('Signed and encrypted to their phone. It appears in their records as signed by you, and in your Prescriptions.', style: DT.muted),
          const Divider(height: 24),
          SelectableText('${rx.medicine}${rx.ingredient == null ? '' : ' (${rx.ingredient})'}\n${doseLine(rx)}${rx.note == null ? '' : '\n${rx.note}'}', style: DT.body),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Pill('Print / save as PDF', onTap: () => printRx(widget.session, RxEntry(patientKey: sh.patientKey, patientName: sh.patientName, patientLine: sh.patientLine, rx: rx))),
            Pill('Write another', dark: false, onTap: () => setState(() => _sent = null)),
          ]),
        ]),
      );
    }
    return Card0(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Write a prescription', style: DT.h2),
        Text('For ${sh.patientName} only.', style: DT.muted),
        const SizedBox(height: 12),
        Field('Medicine', _med, hint: 'Atorvastatin 10 mg'),
        Field('Active ingredient', _ing, hint: 'atorvastatin'),
        Text('Dose · morning, afternoon, night (tap to change)', style: DT.label),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Semantics(
                button: true,
                label: '${['Morning', 'Afternoon', 'Night'][i]} ${_dose[i]}',
                child: InkWell(
                  onTap: () => setState(() => _dose[i] = (_dose[i] + 1) % 4),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _dose[i] > 0 ? DT.ink : DT.raised, borderRadius: BorderRadius.circular(12)),
                    child: Text('${_dose[i]}', style: TextStyle(fontWeight: FontWeight.w600, color: _dose[i] > 0 ? DT.accent : DT.ink)),
                  ),
                ),
              ),
            ),
            if (i < 2) const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 12),
        Text('When to take it', style: DT.label),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final MapEntry(key: k, value: label) in timingLabels.entries)
            ChoiceChip(
              label: Text(label),
              selected: _timing == k,
              onSelected: (_) => setState(() => _timing = k),
              selectedColor: DT.ink,
              labelStyle: TextStyle(color: _timing == k ? DT.onDark : DT.ink, fontWeight: FontWeight.w500),
              shape: const StadiumBorder(),
              showCheckmark: false,
            ),
        ]),
        const SizedBox(height: 12),
        Field('Days', _days),
        Field('Note to patient', _note, hint: 'Repeat lipid panel in 3 months', maxLines: 3),
        Field('Your qualification', _qual),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: DT.signal))),
        Pill(_busy ? 'Sending…' : 'Sign and send', onTap: _busy ? null : _send),
      ]),
    );
  }
}
