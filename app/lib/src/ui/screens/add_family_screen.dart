import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../model/custody.dart';
import '../../model/patient.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'family_link_screens.dart';

enum _Who { child, delegating }

/// F2/F3: add someone whose records you will keep on this phone.
class AddFamilyScreen extends StatefulWidget {
  const AddFamilyScreen({super.key});
  @override
  State<AddFamilyScreen> createState() => _AddFamilyScreenState();
}

class _AddFamilyScreenState extends State<AddFamilyScreen> {
  _Who? _who;
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _typed = TextEditingController();
  DateTime? _dob;
  Sex _sex = Sex.unspecified;
  bool _parent = false;
  bool _consentStep = false;
  String? _error;

  Future<void> _save() async {
    final s = AppScope.of(context);
    try {
      final p = _who == _Who.child
          ? await s.addChild(name: _name.text.trim(), dob: _dob!, sex: _sex, relation: _relation.text.trim())
          : await s.addDelegatingAdult(name: _name.text.trim(), dob: _dob!, sex: _sex, relation: _relation.text.trim(), typedName: _typed.text);
      await s.switchTo(p.id);
      if (!mounted) return;
      AppScope.changed(context);
      Navigator.of(context).pop();
    } on CustodyRefused catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: _who == null
            ? _choose()
            : _consentStep
                ? _consent()
                : _details(),
      );

  Widget _choose() => ListView(children: [
        const Masthead(eyebrow: 'Family', title: 'Who are you adding?', description: 'Their records will be kept on this phone, encrypted like yours.'),
        const SizedBox(height: 12),
        _option(LucideIcons.baby, 'A child under 18', 'You are their parent. You add their records and can show them to a doctor.', () => setState(() => _who = _Who.child)),
        _option(LucideIcons.handHeart, 'An adult who wants me to manage', 'For example a parent without a smartphone. They agree in person, and can stop it at any time.',
            () => setState(() => _who = _Who.delegating)),
        if (AppScope.of(context).links != null)
          _option(LucideIcons.link, 'An adult with their own phone', 'They keep their own records and you are linked by invite. Linking never gives you their records.', () async {
            await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const FamilyInviteScreen()));
          })
        else
          const Note('Linking an adult with their own phone needs the relay, which is not set up in this build.', icon: LucideIcons.cloudOff),
      ]);

  Widget _option(IconData icon, String title, String body, VoidCallback onTap) => ShadCard(
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(body, style: LT.small),
            ]),
          ),
          const Icon(LucideIcons.chevronRight, color: LT.inactive),
        ]),
      );

  Widget _details() {
    final child = _who == _Who.child;
    final ready = _name.text.trim().isNotEmpty && _dob != null && _relation.text.trim().isNotEmpty && (!child || _parent);
    return ListView(children: [
      Masthead(eyebrow: child ? 'Add a child' : 'Add an adult who wants you to manage', title: child ? 'Your child' : 'Who asked you?'),
      const SizedBox(height: 16),
      LabeledField(label: 'Full name', child: TextField(controller: _name, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}))),
      LabeledField(
        label: 'Date of birth',
        child: FieldButton(
          text: _dob == null ? 'Pick a date' : fullDate(_dob!),
          placeholder: _dob == null,
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: child ? DateTime(2018) : DateTime(1955), firstDate: DateTime(1900), lastDate: DateTime.now());
            if (d != null) setState(() => _dob = d);
          },
        ),
      ),
      LabeledField(
        label: 'Sex',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in Sex.values) Chip2(x == Sex.unspecified ? 'Prefer not to say' : x.name, selected: _sex == x, onTap: () => setState(() => _sex = x)),
        ]),
      ),
      LabeledField(
        label: child ? 'They are your…' : 'They are your…',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in child ? const ['son', 'daughter'] : const ['mother', 'father', 'grandmother', 'grandfather', 'spouse'])
            Chip2(r, selected: _relation.text == r, onTap: () => setState(() => _relation.text = r)),
        ]),
      ),
      if (child)
        ShadCard(
          onTap: () => setState(() => _parent = !_parent),
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          child: Row(children: [
            Checkbox(value: _parent, onChanged: (v) => setState(() => _parent = v ?? false)),
            const Expanded(child: Text('I am this child\'s parent.', style: TextStyle(fontSize: 14))),
          ]),
        ),
      if (child)
        const Note('Only a parent can add a child. Proof of parenthood (DigiLocker) is not connected yet, so this is recorded as your declaration. At 18 your child decides for themselves.',
            icon: LucideIcons.info),
      if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        child: SlabButton(child ? 'Add child' : 'Next: their consent', onPressed: !ready ? null : (child ? _save : () => setState(() => _consentStep = true))),
      ),
    ]);
  }

  /// The adult reads this themselves, on this phone, and types their name.
  Widget _consent() {
    final s = AppScope.of(context);
    final statement = Custody.delegationStatement(adultName: _name.text.trim(), custodianName: s.selfPatient!.name);
    return ListView(children: [
      Masthead(eyebrow: 'Hand the phone to ${_name.text.trim()}', title: 'Please read this yourself'),
      ShadCard(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        color: LT.raised,
        child: Text(statement, style: const TextStyle(fontSize: 20, height: 1.5, fontWeight: FontWeight.w500, color: LT.ink)),
      ),
      LabeledField(
        label: 'If you agree, type your name',
        hint: 'Exactly as: ${_name.text.trim()}',
        child: TextField(controller: _typed, textCapitalization: TextCapitalization.words, style: const TextStyle(fontSize: 18), onChanged: (_) => setState(() {})),
      ),
      const Note('This is recorded as consent given in person on this phone. A one-time code to your own number is not connected yet.', icon: LucideIcons.info),
      if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: SlabButton('I agree', icon: LucideIcons.check, onPressed: _typed.text.trim().isEmpty ? null : _save),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        child: SlabButton('I do not agree', variant: ButtonVariant.outline, onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }
}
