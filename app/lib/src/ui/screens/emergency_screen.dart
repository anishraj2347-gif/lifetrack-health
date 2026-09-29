import 'package:flutter/material.dart';

import '../../emergency/emergency_card.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// Read view of the Emergency ID. The allergy block is the one place a
/// signal flood is earned.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  EmergencyCard? _card;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.of(context);
    final card = await s.emergency.load(s.currentPatientId!);
    if (mounted) setState(() => _card = card);
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: LT.ground, elevation: 0, foregroundColor: LT.ink),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Masthead(eyebrow: 'Emergency ID', title: s.currentPatient?.name ?? ''),
              if (c.isEmpty) const Note('This card is empty. Anyone treating you would see nothing here.'),
              if (c.allergies.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  padding: const EdgeInsets.all(16),
                  color: LT.signal,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('ALLERGIES', style: TextStyle(fontFamily: LT.mono, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.6, color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text(c.allergies, style: const TextStyle(fontFamily: LT.body, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              _field('Blood type', c.bloodType),
              _field('Ongoing conditions', c.conditions),
              _field('Current medicines', c.medications),
              _field('Emergency contact', [c.contactName, c.contactRelation, c.contactPhone].where((x) => x.isNotEmpty).join(' · ')),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: SlabButton('Edit card', outline: true, onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(backgroundColor: LT.ground, elevation: 0, foregroundColor: LT.ink),
                      body: EmergencyEditor(
                        patientId: s.currentPatientId!,
                        initial: c,
                        onSaved: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ));
                  _load();
                }),
              ),
            ]),
    );
  }

  Widget _field(String label, String value) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LT.rule))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: LT.eyebrow),
          const SizedBox(height: 6),
          Text(value.isEmpty ? '—' : value, style: LT.label.copyWith(fontSize: 18)),
        ]),
      );
}

class EmergencyEditor extends StatefulWidget {
  const EmergencyEditor({super.key, required this.patientId, required this.initial, required this.onSaved, this.onboarding = false});
  final String patientId;
  final EmergencyCard initial;
  final VoidCallback onSaved;
  final bool onboarding;

  @override
  State<EmergencyEditor> createState() => _EmergencyEditorState();
}

class _EmergencyEditorState extends State<EmergencyEditor> {
  late String _blood = widget.initial.bloodType;
  late final _allergies = TextEditingController(text: widget.initial.allergies);
  late final _conditions = TextEditingController(text: widget.initial.conditions);
  late final _meds = TextEditingController(text: widget.initial.medications);
  late final _contact = TextEditingController(text: widget.initial.contactName);
  late final _relation = TextEditingController(text: widget.initial.contactRelation);
  late final _phone = TextEditingController(text: widget.initial.contactPhone);
  List<String> _problems = const [];

  Future<void> _save() async {
    final card = EmergencyCard(
      bloodType: _blood,
      allergies: _allergies.text.trim(),
      conditions: _conditions.text.trim(),
      medications: _meds.text.trim(),
      contactName: _contact.text.trim(),
      contactRelation: _relation.text.trim(),
      contactPhone: _phone.text.trim(),
    );
    final problems = card.validate();
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    await AppScope.of(context).emergency.save(widget.patientId, card);
    widget.onSaved();
  }

  Widget _text(String label, TextEditingController c, {TextInputType? type}) => LabeledField(
        label: label,
        child: TextField(controller: c, keyboardType: type, maxLength: EmergencyCard.maxFieldLength, buildCounter: _noCounter),
      );

  static Widget? _noCounter(BuildContext _, {required int currentLength, required bool isFocused, required int? maxLength}) => null;

  @override
  Widget build(BuildContext context) => ListView(children: [
        if (widget.onboarding)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Text('STEP 3 OF 3', style: LT.eyebrow),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('If you cannot\nspeak for yourself', style: TextStyle(fontFamily: LT.display, fontSize: 36, fontWeight: FontWeight.w800, height: 1.02)),
            SizedBox(height: 12),
            Text('This one card is kept outside your encrypted records so it can be shown to whoever is treating you.', style: LT.lede),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: LT.signal, width: 2)),
          child: const Text.rich(TextSpan(style: LT.small, children: [
            TextSpan(text: 'A stranger can read this. ', style: TextStyle(fontWeight: FontWeight.w600, color: LT.ink)),
            TextSpan(text: 'Put in what a paramedic needs and nothing more — no address, no ID numbers.'),
          ])),
        ),
        LabeledField(
          label: 'Blood type',
          child: Wrap(spacing: 7, runSpacing: 7, children: [
            for (final b in EmergencyCard.bloodTypes)
              Chip2(b.isEmpty ? 'Unknown' : b, selected: _blood == b, onTap: () => setState(() => _blood = b)),
          ]),
        ),
        _text('Allergies', _allergies),
        _text('Ongoing conditions', _conditions),
        _text('Current medicines', _meds),
        _text('Emergency contact', _contact),
        _text('Relation', _relation),
        _text('Contact phone', _phone, type: TextInputType.phone),
        for (final p in _problems) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 6), child: Text(p, style: LT.small.copyWith(color: LT.signal))),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text('You can leave any of these blank. Only you can edit this card — LifeTrack\'s insights never write to it.', style: TextStyle(fontSize: 12.5, color: LT.ink3, height: 1.5)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: SlabButton(widget.onboarding ? 'Finish setup' : 'Save card', onPressed: _save),
        ),
      ]);
}
