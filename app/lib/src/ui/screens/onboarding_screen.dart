import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../emergency/emergency_card.dart';
import '../../model/patient.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart' show IdentityAttestation;

import '../../identity/identity_verifier.dart';
import '../widgets/add_person_parts.dart';
import '../widgets/digilocker_step.dart';
import '../widgets/person_avatar.dart';
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

  /// Optional, chosen before the profile exists; saved right after it.
  Uint8List? _photo;

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
    if (_photo != null && !demo && mounted) await AppScope.of(context).setPhoto(p.id, _photo);
    // "Look around with sample records": the whole sample family, not just one person.
    if (demo && mounted) await AppScope.of(context).addDemoFamily(photo: bundledPhoto);
    if (!mounted) return;
    setState(() {
      _patientId = p.id;
      _busy = false;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) => _step == 0 && _welcome
      // The welcome photo runs under the status bar; PhotoHero keeps the
      // buttons clear of the system bar at the bottom.
      ? Scaffold(backgroundColor: LT.night, body: _welcomeStep())
      // The profile page brings its own scaffold (photo under the status bar).
      : _step == 0
          ? _profile()
          : Scaffold(
        body: SafeArea(
          child: switch (_step) {
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

  Widget _restoreButton() => SlabButton('I\'ve used LifeTrack before — restore', variant: ButtonVariant.outline, onNight: true, icon: LucideIcons.cloudDownload, onPressed: _busy
      ? null
      : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RestoreScreen(onRestored: widget.onDone))));

  Widget _sampleButton() => SlabButton('Look around with sample records', variant: ButtonVariant.ghost, onNight: true, icon: LucideIcons.sparkles, onPressed: _busy ? null : () => _createProfile(demo: true));

  /// After the coffee template's opening screen: a family photo fading into
  /// black, the mark and name, one big line, what it does, then the way in.
  Widget _welcomeStep() => PhotoHero(Photos.family, children: [
        Center(child: Appear(child: BrandMark(size: 52))),
        SizedBox(height: 10),
        Text('LifeTrack', textAlign: TextAlign.center, style: TextStyle(fontFamily: LT.display, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: LT.onNightMuted)),
        SizedBox(height: 14),
        Stagger(
          index: 1,
          child: Text('Your family\'s health records, on your phone.',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: LT.display, fontSize: 30, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.6, color: Colors.white)),
        ),
        SizedBox(height: 12),
        Stagger(
          index: 2,
          child: Text('Photograph a paper report; LifeTrack reads it on this phone. Reminders for each medicine. Share what you choose, for as long as you choose.',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: LT.body, fontSize: 14, height: 1.55, color: LT.onNightMuted)),
        ),
        SizedBox(height: 28),
        SlabButton('Get started', icon: LucideIcons.arrowRight, iconAfter: true, onPressed: () => setState(() => _welcome = false)),
        if (AppScope.of(context).backupEnabled) ...[SizedBox(height: 10), _restoreButton()],
        if (AppScope.of(context).demoTools) ...[SizedBox(height: 6), _sampleButton()],
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

  Widget _photoSection(int number, String name) => StepSection(
        number: number,
        title: 'Add your photo',
        caption: 'Optional. It tells family profiles apart at a glance.',
        done: _photo != null,
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: 6, bottom: 4),
            child: PhotoEditButton(name: name, photo: _photo, onPicked: (p) => setState(() => _photo = p.jpeg)),
          ),
        ),
      );

  Widget _errorLine() => _error == null ? SizedBox.shrink() : Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal)));

  /// Real builds: the profile comes from DigiLocker (Aadhaar), not a form.
  Widget _verifiedStart() => AddPersonScaffold(
        photo: Photos.family,
        eyebrow: 'Step 1 of 3',
        progress: StepIndicator(step: _step),
        title: 'Create your profile',
        description: 'Made from DigiLocker with your Aadhaar: your name, date of birth and gender, exactly as confirmed. LifeTrack keeps no Aadhaar number.',
        bottom: SlabButton(_verified == null ? 'Verify first to continue' : 'Create my profile', icon: LucideIcons.arrowRight, iconAfter: true, onPressed: _verified == null || _busy ? null : () => _createProfile(demo: false)),
        children: [
          StepSection(
            number: 1,
            title: 'Verify with DigiLocker',
            done: _verified != null,
            padChild: false,
            child: DigiLockerStep(purpose: 'self', buttonLabel: 'Verify with DigiLocker (Aadhaar)', onVerified: (v) => setState(() => _verified = v)),
          ),
          _photoSection(2, _verified?.name ?? ''),
          _errorLine(),
          SizedBox(height: 10),
          Note('Everyone needs Aadhaar to create a profile. A newborn without Aadhaar is added later by a verified parent, from the parent\'s DigiLocker birth certificate.', icon: LucideIcons.info),
        ],
      );

  Widget _profile() {
    if (AppScope.of(context).identityRequired) return _verifiedStart();
    final ready = _name.text.trim().isNotEmpty && _dob != null;
    return AddPersonScaffold(
      photo: Photos.family,
      eyebrow: 'Step 1 of 3',
      progress: StepIndicator(step: _step),
      title: 'Who are these records for?',
      description: 'This profile lives on this phone. Other family members create their own.',
      bottom: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // A grey button alone does not say why; this does.
        if (!ready)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              _name.text.trim().isEmpty && _dob == null ? 'Enter a name and date of birth to continue' : _dob == null ? 'Pick a date of birth to continue' : 'Enter a name to continue',
              textAlign: TextAlign.center,
              style: LT.small,
            ),
          ),
        SlabButton('Create my profile', icon: LucideIcons.arrowRight, iconAfter: true, onPressed: ready && !_busy ? () => _createProfile(demo: false) : null),
      ]),
      children: [
        StepSection(
          number: 1,
          title: 'About you',
          done: ready,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
          ]),
        ),
        _photoSection(2, _name.text.trim()),
        _errorLine(),
        SizedBox(height: 10),
        Note('We ask for as little as we can. Nothing here is shared with a doctor until you grant access.', icon: LucideIcons.shieldCheck),
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
