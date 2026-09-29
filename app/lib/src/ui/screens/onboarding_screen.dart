import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  Widget _intro(String title, String body) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StepIndicator(step: _step),
          const SizedBox(height: 24),
          Text(title, style: LT.hero),
          const SizedBox(height: 8),
          Text(body, style: LT.lede),
        ]),
      );

  Widget _profile() {
    final ready = _name.text.trim().isNotEmpty && _dob != null;
    return ListView(
      children: [
        _intro('Who are these records for?', 'This profile lives on this phone. Other family members create their own.'),
        LabeledField(
          label: 'Full name',
          child: TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Anjali Sharma'),
          ),
        ),
        LabeledField(
          label: 'Date of birth',
          hint: 'Reference ranges depend on age. Adult ranges are never applied to a child.',
          child: FieldButton(
            text: _dob == null ? 'Pick a date' : fullDate(_dob!),
            placeholder: _dob == null,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime(1990),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _dob = d);
            },
          ),
        ),
        LabeledField(
          label: 'Sex',
          hint: 'Some ranges differ by sex. If you leave this unset, those results are shown as not checked.',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in Sex.values)
              Chip2(s == Sex.unspecified ? 'Prefer not to say' : s.name, selected: _sex == s, onTap: () => setState(() => _sex = s)),
          ]),
        ),
        const Note('We ask for as little as we can. Nothing here is shared with a doctor until you grant access.', icon: LucideIcons.shieldCheck),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: SlabButton('Continue', onPressed: ready && !_busy ? () => _createProfile(demo: false) : null),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: SlabButton('Explore with sample records', variant: ButtonVariant.outline, icon: LucideIcons.sparkles, onPressed: _busy ? null : () => _createProfile(demo: true)),
        ),
      ],
    );
  }

  Widget _custody() => ListView(
        children: [
          _intro('Where your records live', 'On this phone, encrypted with a key held in the phone\'s secure hardware.'),
          const _Row(
            icon: LucideIcons.smartphone,
            tone: BadgeTone.trace,
            title: 'Stays on this phone',
            body: 'Records, notes, your access log and the permissions you give. This version of the app has no internet permission at all.',
          ),
          const _Row(
            icon: LucideIcons.cloudOff,
            tone: BadgeTone.caution,
            title: 'No backup yet',
            body: 'The encrypted backup service is not live in this version. Until it is, your records exist only here — if this phone is lost or reset, they are gone.',
          ),
          ShadCard(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
            onTap: () => setState(() => _understood = !_understood),
            child: Row(children: [
              Checkbox(value: _understood, onChanged: (v) => setState(() => _understood = v ?? false)),
              const Expanded(child: Text('I understand my records are on this phone only, with no backup yet.', style: TextStyle(fontSize: 14, color: LT.ink))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: SlabButton('Continue', onPressed: _understood ? () => setState(() => _step = 2) : null),
          ),
        ],
      );
}

/// Three-segment progress with a "Step n of 3" caption.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.step});
  final int step;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(color: i <= step ? LT.primary : LT.rule, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            if (i < 2) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 10),
        Text('Step ${step + 1} of 3', style: LT.eyebrow),
      ]);
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.tone, required this.title, required this.body});
  final IconData icon;
  final BadgeTone tone;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (tone) {
      BadgeTone.trace => (LT.trace, const Color(0xFFECFDF5)),
      BadgeTone.caution => (LT.cautionInk, LT.caution),
      _ => (LT.ink, LT.band),
    };
    return ShadCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconTile(icon, color: fg, background: bg),
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
}
