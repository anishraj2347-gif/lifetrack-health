import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../model/clinical_profile.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// Allergies, conditions and family illnesses for the profile on screen: the
/// facts a doctor reads first. The allergies here are the one list: they feed
/// the Emergency ID and every clinical share.
class ClinicalProfileScreen extends StatefulWidget {
  const ClinicalProfileScreen({super.key});
  @override
  State<ClinicalProfileScreen> createState() => _ClinicalProfileScreenState();
}

class _AllergyRow {
  _AllergyRow([Allergy? a])
      : substance = TextEditingController(text: a?.substance),
        reaction = TextEditingController(text: a?.reaction);
  final TextEditingController substance, reaction;
}

class _ConditionRow {
  _ConditionRow([Condition? c])
      : name = TextEditingController(text: c?.name),
        since = TextEditingController(text: c?.sinceYear?.toString());
  final TextEditingController name, since;
}

class _FamilyRow {
  _FamilyRow([FamilyIllness? f])
      : relation = f?.relation,
        condition = TextEditingController(text: f?.condition),
        onset = TextEditingController(text: f?.ageAtOnset?.toString());
  Relation? relation;
  final TextEditingController condition, onset;
}

const _relationNames = {
  Relation.mother: 'Mother',
  Relation.father: 'Father',
  Relation.sister: 'Sister',
  Relation.brother: 'Brother',
  Relation.grandparent: 'Grandparent',
  Relation.child: 'Child',
  Relation.other: 'Other relative',
};

class _ClinicalProfileScreenState extends State<ClinicalProfileScreen> {
  final _allergies = <_AllergyRow>[];
  final _conditions = <_ConditionRow>[];
  final _family = <_FamilyRow>[];
  bool _noneKnown = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final p = AppScope.of(context).clinicalProfile();
    _noneKnown = p.noneKnown;
    _allergies.addAll(p.allergies.map(_AllergyRow.new));
    _conditions.addAll(p.conditions.map(_ConditionRow.new));
    _family.addAll(p.familyIllnesses.map(_FamilyRow.new));
  }

  static String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// A problem to show, or null. Blank rows are simply left out.
  String? _problem(int thisYear) {
    if (_allergies.any((a) => _text(a.substance) == null && _text(a.reaction) != null)) return 'Name what each allergy is to, or remove the row.';
    if (_allergies.any((a) => a.substance.text.trim().length > ClinicalProfile.maxTextLength || a.reaction.text.trim().length > ClinicalProfile.maxTextLength)) return 'Keep each allergy under ${ClinicalProfile.maxTextLength} characters.';
    for (final c in _conditions) {
      if (_text(c.name) == null) {
        if (_text(c.since) != null) return 'Name each condition, or remove the row.';
        continue;
      }
      if (_text(c.since) != null) {
        final y = int.tryParse(c.since.text.trim());
        if (y == null || y < 1900 || y > thisYear) return 'The year should be between 1900 and $thisYear.';
      }
    }
    for (final f in _family) {
      if (_text(f.condition) == null) {
        if (f.relation != null || _text(f.onset) != null) return 'Say what the illness was, or remove the row.';
        continue;
      }
      if (f.relation == null) return 'Say who in the family had ${f.condition.text.trim()}.';
      if (_text(f.onset) != null) {
        final a = int.tryParse(f.onset.text.trim());
        if (a == null || a < 0 || a > 120) return 'Age should be a number from 0 to 120.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    final problem = _problem(s.clock().year);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final allergies = [for (final a in _allergies) if (_text(a.substance) != null) Allergy(substance: _text(a.substance)!, reaction: _text(a.reaction))];
    setState(() => _saving = true);
    try {
      await s.saveClinicalProfile(ClinicalProfile(
        allergies: allergies,
        noneKnown: allergies.isEmpty && _noneKnown,
        conditions: [
          for (final c in _conditions)
            if (_text(c.name) != null) Condition(name: _text(c.name)!, sinceYear: int.tryParse(c.since.text.trim())),
        ],
        familyIllnesses: [
          for (final f in _family)
            if (_text(f.condition) != null) FamilyIllness(relation: f.relation!, condition: _text(f.condition)!, ageAtOnset: int.tryParse(f.onset.text.trim())),
        ],
      ));
      if (!mounted) return;
      celebrate(context, 'Saved');
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _remove(String what, VoidCallback onTap) => IconButton(tooltip: 'Remove this $what', icon: Icon(LucideIcons.trash2, size: 18), onPressed: () => setState(onTap));

  Widget _add(String label, VoidCallback onTap) => Padding(
        padding: EdgeInsets.fromLTRB(16, 2, 16, 4),
        child: SlabButton(label, variant: ButtonVariant.outline, icon: LucideIcons.plus, onPressed: () => setState(onTap)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GlassAppBar(),
        body: ListView(children: [
          Masthead(
            eyebrow: 'Your profile',
            title: 'Allergies and conditions',
            description: 'What a doctor needs first. Allergies here also appear on the Emergency ID, and go to a doctor when you share.',
          ),
          Eyebrow('Allergies'),
          for (final (i, a) in _allergies.indexed)
            ShadCard(
              margin: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: a.substance, decoration: InputDecoration(hintText: 'Allergic to, e.g. Penicillin'))),
                  _remove('allergy', () => _allergies.removeAt(i)),
                ]),
                SizedBox(height: 8),
                TextField(controller: a.reaction, decoration: InputDecoration(hintText: 'What happens, e.g. rash (optional)')),
              ]),
            ),
          if (_allergies.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip2(noKnownAllergies, exclusive: false, selected: _noneKnown, onTap: () => setState(() => _noneKnown = !_noneKnown)),
              ),
            ),
          if (_allergies.isEmpty && !_noneKnown) Note('Leaving this empty tells a doctor allergies are not recorded. It does not mean there are none.', icon: LucideIcons.info, margin: EdgeInsets.fromLTRB(16, 0, 16, 10)),
          _add('Add an allergy', () {
            _allergies.add(_AllergyRow());
            _noneKnown = false;
          }),
          Eyebrow('Conditions'),
          for (final (i, c) in _conditions.indexed)
            ShadCard(
              margin: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: c.name, decoration: InputDecoration(hintText: 'Condition, e.g. Asthma'))),
                  _remove('condition', () => _conditions.removeAt(i)),
                ]),
                SizedBox(height: 8),
                TextField(controller: c.since, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'Since which year (optional)')),
              ]),
            ),
          _add('Add a condition', () => _conditions.add(_ConditionRow())),
          Eyebrow('Family illnesses'),
          for (final (i, f) in _family.indexed)
            ShadCard(
              margin: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<Relation>(
                      initialValue: f.relation,
                      isExpanded: true,
                      hint: Text('Who'),
                      items: [for (final e in _relationNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (x) => setState(() => f.relation = x),
                    ),
                  ),
                  _remove('family illness', () => _family.removeAt(i)),
                ]),
                SizedBox(height: 8),
                TextField(controller: f.condition, decoration: InputDecoration(hintText: 'Illness, e.g. Heart attack')),
                SizedBox(height: 8),
                TextField(controller: f.onset, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'Their age when it began (optional)')),
              ]),
            ),
          _add('Add a family illness', () => _family.add(_FamilyRow())),
          if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
            child: SlabButton(_saving ? 'Saving…' : 'Save', icon: LucideIcons.check, onPressed: _saving ? null : _save),
          ),
        ]),
      );
}
