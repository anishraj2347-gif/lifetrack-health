import 'package:flutter/material.dart';

import '../../emergency/emergency_card.dart';
import '../../model/patient.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'emergency_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _name = TextEditingController();
  DateTime? _dob;
  Sex _sex = Sex.unspecified;
  bool _understood = false;
  String? _patientId;
  bool _busy = false;

  Future<void> _createProfile({required bool demo}) async {
    setState(() => _busy = true);
    final p = await AppScope.of(context).createProfile(
      name: _name.text.trim(),
      dob: _dob ?? DateTime(1990),
      sex: _sex,
      demo: demo,
    );
    if (!mounted) return;
    setState(() {
      _patientId = p.id;
      _busy = false;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: switch (_step) {
            0 => _profile(),
            1 => _custody(),
            _ => EmergencyEditor(
                patientId: _patientId!,
                initial: const EmergencyCard(),
                onboarding: true,
                onSaved: widget.onDone,
              ),
          },
        ),
      );

  Widget _progress() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(child: Container(height: 4, color: i <= _step ? LT.ink : LT.rule)),
                if (i < 2) const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 14),
            Text('STEP ${_step + 1} OF 3', style: LT.eyebrow),
          ],
        ),
      );

  Widget _profile() {
    final ready = _name.text.trim().isNotEmpty && _dob != null;
    return ListView(
      children: [
        _progress(),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Who are these\nrecords for?', style: TextStyle(fontFamily: LT.display, fontSize: 36, fontWeight: FontWeight.w800, height: 1.02)),
            SizedBox(height: 12),
            Text('This profile lives on this phone. Other family members create their own.', style: LT.lede),
          ]),
        ),
        LabeledField(
          label: 'Full name',
          child: TextField(controller: _name, onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.words),
        ),
        LabeledField(
          label: 'Date of birth',
          hint: 'Reference ranges depend on age. Adult ranges are never applied to a child.',
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: const RoundedRectangleBorder(),
              side: const BorderSide(color: LT.ink, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime(1990),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _dob = d);
            },
            child: Text(_dob == null ? 'Choose' : fullDate(_dob!), style: LT.label),
          ),
        ),
        LabeledField(
          label: 'Sex',
          hint: 'Some ranges differ by sex. If you leave this unset, those results are shown as not checked.',
          child: Wrap(spacing: 7, children: [
            for (final s in Sex.values)
              Chip2(s == Sex.unspecified ? 'Prefer not to say' : s.name, selected: _sex == s, onTap: () => setState(() => _sex = s)),
          ]),
        ),
        const Note('We ask for as little as we can. Nothing here is shared with a doctor until you grant access.'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: SlabButton('Continue', onPressed: ready && !_busy ? () => _createProfile(demo: false) : null),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SlabButton('Explore with sample records', outline: true, onPressed: _busy ? null : () => _createProfile(demo: true)),
        ),
      ],
    );
  }

  Widget _custody() => ListView(
        children: [
          _progress(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Where your\nrecords live', style: TextStyle(fontFamily: LT.display, fontSize: 36, fontWeight: FontWeight.w800, height: 1.02)),
              SizedBox(height: 12),
              Text('On this phone, encrypted with a key held in the phone\'s secure hardware.', style: LT.lede),
            ]),
          ),
          const _Row(
            icon: Icons.smartphone,
            color: LT.trace,
            title: 'Stays on this phone',
            body: 'Records, notes, your access log and the permissions you give. This version of the app has no internet permission at all.',
          ),
          const _Row(
            icon: Icons.cloud_off_outlined,
            color: LT.ink3,
            title: 'No backup yet',
            body: 'The encrypted backup service is not live in this version. Until it is, your records exist only here — if this phone is lost or reset, they are gone.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
            child: CheckboxListTile(
              value: _understood,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _understood = v ?? false),
              title: const Text('I understand my records are on this phone only, with no backup yet.', style: LT.small),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SlabButton('Continue', onPressed: _understood ? () => setState(() => _step = 2) : null),
          ),
        ],
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: LT.rule))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: LT.label),
              const SizedBox(height: 4),
              Text(body, style: LT.small),
            ]),
          ),
        ]),
      );
}
