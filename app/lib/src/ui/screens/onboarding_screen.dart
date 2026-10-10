import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../emergency/emergency_card.dart';
import '../../model/patient.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart' show IdentityAttestation;

import '../../identity/identity_verifier.dart';
import '../widgets/digilocker_step.dart';
import 'backup_screens.dart';
import 'emergency_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// The first thing anyone sees: what LifeTrack is, before any form.
  bool _welcome = true;
  int _step = 0;
  final _name = TextEditingController();
  DateTime? _dob;
  Sex _sex = Sex.unspecified;
  bool _understood = false;
  String? _patientId;
  bool _busy = false;

  IdentityAttestation? _verified;
  String? _error;

  Future<void> _createProfile({required bool demo}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final Patient p;
    try {
      p = await AppScope.of(context).createProfile(
        name: _name.text.trim(),
        dob: _dob ?? DateTime(1990),
        sex: _sex,
        demo: demo,
        verification: demo ? null : _verified,
      );
    } on PersonExists catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    }
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
            0 when _welcome => _welcomeStep(),
            0 => _profile(),
            1 => _custody(),
            _ => EmergencyEditor(
                patientId: _patientId!,
                initial: EmergencyCard(),
                onboarding: true,
                onSaved: widget.onDone,
              ),
          },
        ),
      );

  Widget _restoreButton() => SlabButton('I\'ve used LifeTrack before — restore', variant: ButtonVariant.outline, icon: LucideIcons.cloudDownload, onPressed: _busy
      ? null
      : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RestoreScreen(onRestored: widget.onDone))));

  Widget _sampleButton() => SlabButton('Look around with sample records', variant: ButtonVariant.ghost, icon: LucideIcons.sparkles, onPressed: _busy ? null : () => _createProfile(demo: true));

  /// Mark, name, one line, three things it does, then the way in.
  Widget _welcomeStep() => ListView(padding: EdgeInsets.fromLTRB(20, 36, 20, 28), children: [
        Center(child: Appear(child: BrandMark(size: 120))),
        SizedBox(height: 20),
        Text('LifeTrack', textAlign: TextAlign.center, style: TextStyle(fontFamily: LT.display, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1, color: LT.ink)),
        SizedBox(height: 6),
        Text('Your family\'s health records, on your phone.', textAlign: TextAlign.center, style: LT.lede),
        SizedBox(height: 28),
        for (final (i, (icon, title, body)) in const [
          (LucideIcons.fileText, 'Every report in one place', 'Photograph a paper report; LifeTrack reads it on this phone.'),
          (LucideIcons.bellRing, 'Never miss a dose', 'Reminders for each medicine, for you and your family.'),
          (LucideIcons.qrCode, 'Show a doctor in seconds', 'Share what you choose, for as long as you choose.'),
        ].indexed)
          Stagger(
            index: i + 1,
            child: ShadCard(
              margin: EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(children: [
                IconTile(icon),
                SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text(body, style: LT.small),
                  ]),
                ),
              ]),
            ),
          ),
        SizedBox(height: 18),
        SlabButton('Get started', icon: LucideIcons.arrowRight, iconAfter: true, onPressed: () => setState(() => _welcome = false)),
        if (AppScope.of(context).backupEnabled) ...[SizedBox(height: 10), _restoreButton()],
        SizedBox(height: 6),
        _sampleButton(),
      ]);

  /// Progress first, above the picture, so where you are is the first thing read.
  Widget _progress() => Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 0), child: StepIndicator(step: _step));

  Widget _intro(String title, String body) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: LT.hero),
          SizedBox(height: 8),
          Text(body, style: LT.lede),
        ]),
      );

  /// Real builds: the profile comes from DigiLocker (Aadhaar), not a form.
  Widget _verifiedStart() => ListView(
        children: [
          _progress(),
          PhotoBanner(Photos.family, height: 200),
          _intro('Verify who you are', 'Your profile is made from DigiLocker with your Aadhaar: your name, date of birth and gender, exactly as confirmed. LifeTrack keeps no Aadhaar number.'),
          DigiLockerStep(purpose: 'self', buttonLabel: 'Verify with DigiLocker (Aadhaar)', onVerified: (v) => setState(() => _verified = v)),
          if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
          if (_verified != null)
            Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: SlabButton('Continue', onPressed: _busy ? null : () => _createProfile(demo: false)),
            ),
          Note('Everyone needs Aadhaar to create a profile. A newborn without Aadhaar is added later by a verified parent, from the parent\'s DigiLocker birth certificate.', icon: LucideIcons.info),
          SizedBox(height: 28),
        ],
      );

  Widget _profile() {
    if (AppScope.of(context).identityRequired) return _verifiedStart();
    final ready = _name.text.trim().isNotEmpty && _dob != null;
    return ListView(
      children: [
        _progress(),
        PhotoBanner(Photos.family, height: 200),
        _intro('Who are these records for?', 'This profile lives on this phone. Other family members create their own.'),
        LabeledField(
          label: 'Full name',
          child: TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: 'e.g. Anjali Sharma'),
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
                // Start on years: someone born in 1952 should not page back month by month.
                initialDatePickerMode: DatePickerMode.year,
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
        Note('We ask for as little as we can. Nothing here is shared with a doctor until you grant access.', icon: LucideIcons.shieldCheck),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: SlabButton('Continue', onPressed: ready && !_busy ? () => _createProfile(demo: false) : null),
        ),
        // A grey button alone does not say why; this does.
        if (!ready)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              _name.text.trim().isEmpty && _dob == null ? 'Enter a name and date of birth to continue' : _dob == null ? 'Pick a date of birth to continue' : 'Enter a name to continue',
              textAlign: TextAlign.center,
              style: LT.small,
            ),
          ),
        SizedBox(height: 28),
      ],
    );
  }

  Widget _custody() => ListView(
        children: [
          _progress(),
          _intro('Where your records live', 'On this phone, encrypted with a key held in the phone\'s secure hardware.'),
          const _Row(
            icon: LucideIcons.smartphone,
            tone: BadgeTone.trace,
            title: 'Stays on this phone',
            body: 'Records, notes, your access log and the permissions you give. Nothing leaves this phone unless you share it with a doctor or a linked family member.',
          ),
          const _Row(
            icon: LucideIcons.cloudOff,
            tone: BadgeTone.caution,
            title: 'No backup until you turn it on',
            body: 'Until you turn on backup in Me › Backup, your records exist only here — if this phone is lost or reset, they are gone.',
          ),
          ShadCard(
            margin: EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: EdgeInsets.fromLTRB(8, 4, 12, 4),
            onTap: () => setState(() => _understood = !_understood),
            child: Row(children: [
              Checkbox(value: _understood, onChanged: (v) => setState(() => _understood = v ?? false)),
              Expanded(child: Text('I understand my records are only on this phone until I turn on backup.', style: TextStyle(fontSize: 14, color: LT.ink))),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 28),
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
                // Done: black; the step you are on: lime ("now"); ahead: a rule.
                decoration: BoxDecoration(color: i < step ? LT.button : i == step ? LT.accent : LT.rule, borderRadius: BorderRadius.circular(3), border: i == step ? Border.all(color: LT.ink.withValues(alpha: 0.35), width: 0.8) : null),
              ),
            ),
            if (i < 2) const SizedBox(width: 6),
          ],
        ]),
        SizedBox(height: 10),
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
      BadgeTone.trace => (LT.traceInk, Color(0xFFECFDF5)),
      BadgeTone.caution => (LT.cautionInk, LT.caution),
      _ => (LT.ink, LT.band),
    };
    return ShadCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconTile(icon, color: fg, background: bg),
        SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: LT.label),
            SizedBox(height: 4),
            Text(body, style: LT.small),
          ]),
        ),
      ]),
    );
  }
}
