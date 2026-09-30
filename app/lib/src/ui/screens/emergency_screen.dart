import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../emergency/emergency_card.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'onboarding_screen.dart' show StepIndicator;

/// Read view of the Emergency ID. The allergy block is the one place a
/// signal flood is earned.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key, this.fromLockScreen = false});

  /// Opened from the app lock by whoever holds the phone: the owner's card,
  /// read-only, and the read is audited as unauthenticated (#7).
  final bool fromLockScreen;
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
    final card = widget.fromLockScreen
        ? await s.emergency.readFromLockScreen(s.selfPatientId!, s.clock())
        : await s.emergency.load(s.currentPatientId!);
    if (mounted) setState(() => _card = card);
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Masthead(eyebrow: 'Emergency ID', title: (widget.fromLockScreen ? s.selfPatient : s.currentPatient)?.name ?? '', trailing: const Icon(LucideIcons.heartPulse, color: LT.signal)),
              const SizedBox(height: 14),
              if (c.isEmpty) const Note('This card is empty. Anyone treating you would see nothing here.', margin: EdgeInsets.fromLTRB(16, 0, 16, 10)),
              if (c.allergies.isNotEmpty)
                ShadCard(
                  color: LT.signal,
                  borderColor: LT.signal,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(LucideIcons.triangleAlert, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Allergies', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xE6FFFFFF))),
                        const SizedBox(height: 4),
                        Text(c.allergies, style: const TextStyle(fontFamily: LT.body, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ]),
                ),
              ShadCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _field(LucideIcons.droplet, 'Blood type', c.bloodType),
                  _field(LucideIcons.activity, 'Ongoing conditions', c.conditions),
                  _field(LucideIcons.pill, 'Current medicines', c.medications),
                  _field(LucideIcons.phone, 'Emergency contact', [c.contactName, c.contactRelation, c.contactPhone].where((x) => x.isNotEmpty).join(' · '), last: true),
                ]),
              ),
              if (!widget.fromLockScreen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                child: SlabButton('Edit card', icon: LucideIcons.pencil, variant: ButtonVariant.outline, onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(),
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

  Widget _field(IconData icon, String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: LT.rule))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: LT.ink3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: LT.small),
              const SizedBox(height: 2),
              Text(value.isEmpty ? '—' : value, style: LT.label.copyWith(fontSize: 16)),
            ]),
          ),
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
    await AppScope.of(context).saveEmergencyCard(widget.patientId, card);
    widget.onSaved();
  }

  Widget _text(String label, TextEditingController c, {TextInputType? type}) => LabeledField(
        label: label,
        child: TextField(controller: c, keyboardType: type, maxLength: EmergencyCard.maxFieldLength, buildCounter: _noCounter),
      );

  static Widget? _noCounter(BuildContext _, {required int currentLength, required bool isFocused, required int? maxLength}) => null;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.onboarding) ...[const StepIndicator(step: 2), const SizedBox(height: 24)],
            const Text('If you cannot speak for yourself', style: LT.hero),
            const SizedBox(height: 8),
            const Text('This one card is kept outside your encrypted records so it can be shown to whoever is treating you.', style: LT.lede),
          ]),
        ),
        ShadCard(
          color: const Color(0xFFFFF7ED),
          borderColor: const Color(0xFFFED7AA),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          padding: const EdgeInsets.all(14),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(LucideIcons.eye, size: 16, color: LT.signal),
            SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, height: 1.5, color: LT.ink2), children: [
                TextSpan(text: 'A stranger can read this. ', style: TextStyle(fontWeight: FontWeight.w600, color: LT.ink)),
                TextSpan(text: 'Put in what a paramedic needs and nothing more — no address, no ID numbers.'),
              ])),
            ),
          ]),
        ),
        LabeledField(
          label: 'Blood type',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
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
          padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Text('You can leave any of these blank. Only you can edit this card — LifeTrack\'s insights never write to it.', style: LT.small),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: SlabButton(widget.onboarding ? 'Finish setup' : 'Save card', onPressed: _save),
        ),
      ]);
}
