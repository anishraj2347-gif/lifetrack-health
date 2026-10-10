import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../emergency/emergency_card.dart';
import '../../emergency/emergency_qr.dart';
import '../../security/plain_leftovers.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import 'onboarding_screen.dart' show StepIndicator;

/// What the "No known allergies" chip stores: said on purpose, unlike a
/// blank field, which means nobody filled it in.
const noKnownAllergies = 'No known allergies';

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
    // Masked: this screen opens from the lock screen for anyone holding the phone.
    final who = widget.fromLockScreen ? s.selfPatient : s.currentPatient;
    final abha = who?.abha;
    final ltId = who == null ? null : s.lifeTrackIdOf(who.id);
    final qrText = c == null || who == null
        ? ''
        : emergencyQrText(name: who.name, card: c, lifeTrackId: ltId, abhaMasked: abha?.masked, updated: s.clock());
    return Scaffold(
      appBar: GlassAppBar(),
      body: c == null
          ? Center(child: CircularProgressIndicator())
          : ListView(children: [
              Masthead(eyebrow: 'Emergency ID', title: who?.name ?? '', description: c.isEmpty ? null : 'For whoever treats you. Tap the card for its QR code.'),
              SizedBox(height: 14),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _IdCard(name: who?.name ?? '', card: c, lifeTrackId: ltId, abhaMasked: abha?.masked, qrText: qrText),
              ),
              if (c.isEmpty) ...[
                Note('This card is empty. Anyone treating you would see nothing here.', margin: EdgeInsets.fromLTRB(16, 0, 16, 12)),
                if (!widget.fromLockScreen)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: SlabButton('Fill in your Emergency ID', icon: LucideIcons.pencil, onPressed: () => _edit(c)),
                  ),
              ],
              ShadCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  // Blood type, allergies and ABHA are on the card above.
                  _field(LucideIcons.activity, 'Ongoing conditions', c.conditions),
                  _field(LucideIcons.pill, 'Current medicines', c.medications),
                  _field(LucideIcons.phone, 'Emergency contact', [c.contactName, c.contactRelation, c.contactPhone].where((x) => x.isNotEmpty).join(' · '), last: c.contactPhone.isEmpty),
                  if (c.contactPhone.isNotEmpty) _callButton(c, last: true),
                ]),
              ),
              if (!widget.fromLockScreen && !c.isEmpty)
                Note(
                  'A locked phone hides this card, because LifeTrack only opens once the phone is unlocked. '
                  'So also keep it where they can find it — save the wallet card below and print it, or set it as your lock-screen wallpaper, '
                  'and copy your allergies and contact into your phone\'s own emergency information (Settings › Safety & emergency).',
                  icon: LucideIcons.lockKeyhole,
                  margin: EdgeInsets.fromLTRB(16, 6, 16, 0),
                ),
              if (!widget.fromLockScreen && !c.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: SlabButton('Save wallet card', icon: LucideIcons.wallet, variant: ButtonVariant.outline, onPressed: () => _saveWalletCard(qrText, who!.name)),
                ),
              if (!widget.fromLockScreen && !c.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: SlabButton('Edit card', icon: LucideIcons.pencil, variant: ButtonVariant.outline, onPressed: () => _edit(c)),
                ),
              if (widget.fromLockScreen || c.isEmpty) SizedBox(height: 28),
            ]),
    );
  }

  Future<void> _edit(EmergencyCard c) async {
    final s = AppScope.of(context);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: GlassAppBar(),
        body: EmergencyEditor(
          patientId: s.currentPatientId!,
          initial: c,
          onSaved: () => Navigator.of(context).pop(),
        ),
      ),
    ));
    _load();
  }

  /// The QR as an image to print and keep in a wallet. It carries the card
  /// as it is now; after changing the card, save a new one.
  Future<void> _saveWalletCard(String text, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final img = await QrPainter(data: text, version: QrVersions.auto, gapless: true, eyeStyle: QrEyeStyle(color: Colors.black, eyeShape: QrEyeShape.square), dataModuleStyle: QrDataModuleStyle(color: Colors.black, dataModuleShape: QrDataModuleShape.square)).toImageData(900);
      final f = File('${(await getTemporaryDirectory()).path}/emergency-id.png');
      await f.writeAsBytes(img!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')], text: 'Emergency ID — $name. Scan with any phone camera.'));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save. ${plainError(e)}')));
    } finally {
      await deleteQuietly('${(await getTemporaryDirectory()).path}/emergency-id.png');
    }
  }

  /// Opens the phone's dialer with the number filled in — the person still
  /// presses call. No permission and no network: it is the system dialer.
  Widget _callButton(EmergencyCard c, {required bool last}) => Container(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: LT.rule))),
        child: SizedBox(
          height: 56,
          child: SlabButton(
            'Call ${c.contactName.isEmpty ? c.contactPhone : c.contactName.split(' ').first}${c.contactRelation.isEmpty ? '' : ' (${c.contactRelation})'}',
            icon: LucideIcons.phoneCall,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await launchUrl(Uri(scheme: 'tel', path: c.contactPhone.replaceAll(RegExp(r'[^0-9+]'), '')));
              if (!ok) messenger.showSnackBar(SnackBar(content: Text('Could not open the dialer. The number is ${c.contactPhone}.')));
            },
          ),
        ),
      );

  Widget _field(IconData icon, String label, String value, {bool last = false}) => Container(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: LT.rule))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: LT.ink3),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: LT.small),
              SizedBox(height: 2),
              // Blank is "not filled in", never "none": a paramedic must not
              // read an empty allergy field as "no known allergies".
              value.isEmpty
                  ? Text('Not filled in', style: LT.label.copyWith(fontSize: 16, fontStyle: FontStyle.italic, color: LT.ink3))
                  : Text(value, style: LT.label.copyWith(fontSize: 16)),
            ]),
          ),
        ]),
      );
}

/// The Emergency ID as a card in the hand: black, credit-card shaped, the
/// few things a stranger needs at a glance. Tap and it turns over (450 ms)
/// to a white side with the QR code — plain text any phone camera reads.
/// Grows taller rather than clipping when the phone's text is large.
class _IdCard extends StatefulWidget {
  const _IdCard({required this.name, required this.card, required this.lifeTrackId, required this.abhaMasked, required this.qrText});
  final String name;
  final EmergencyCard card;
  final String? lifeTrackId;
  final String? abhaMasked;
  final String qrText;
  @override
  State<_IdCard> createState() => _IdCardState();
}

class _IdCardState extends State<_IdCard> {
  bool _back = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final canFlip = !widget.card.isEmpty;
    return Semantics(
      button: canFlip,
      label: canFlip ? (_back ? 'Emergency QR code. Tap to show the card.' : 'Tap to show the QR code') : null,
      child: GestureDetector(
        onTap: canFlip ? () => setState(() => _back = !_back) : null,
        child: LayoutBuilder(builder: (context, box) {
          final minH = box.maxWidth / 1.586;
          return TweenAnimationBuilder<double>(
            tween: Tween(end: _back ? 1 : 0),
            duration: Duration(milliseconds: still ? 0 : 450),
            curve: Curves.easeInOutCubic,
            builder: (context, t, _) {
              final showBack = t >= 0.5;
              final angle = t * 3.14159265;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(showBack ? angle - 3.14159265 : angle),
                child: Stack(children: [
                  Visibility(visible: !showBack, maintainSize: true, maintainAnimation: true, maintainState: true, child: _front(minH)),
                  if (showBack) Positioned.fill(child: _backFace()),
                ]),
              );
            },
          );
        }),
      ),
    );
  }

  Widget _front(double minH) {
    final c = widget.card;
    String orDash(String v) => v.trim().isEmpty ? 'Not filled in' : v;
    final muted = TextStyle(fontSize: 12, color: LT.onDarkMuted, letterSpacing: 0.2);
    return Container(
      constraints: BoxConstraints(minHeight: minH),
      decoration: ShapeDecoration(
        color: LT.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LT.radiusLg), side: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
        shadows: [BoxShadow(color: Colors.black.withValues(alpha: LT.dark ? 0.45 : 0.25), blurRadius: 28, offset: Offset(0, 12))],
      ),
      foregroundDecoration: ShapeDecoration(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LT.radiusLg)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.center, colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0)]),
      ),
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: OnDark(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(LucideIcons.ambulance, size: 18, color: LT.onDark),
            SizedBox(width: 8),
            Expanded(child: Text('EMERGENCY ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.6, color: LT.onDark))),
            if (!c.isEmpty) Icon(LucideIcons.qrCode, size: 18, color: LT.onDarkMuted),
          ]),
          SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Name', style: muted),
                Text(widget.name, style: TextStyle(fontFamily: LT.display, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: LT.onDark)),
              ]),
            ),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Blood type', style: muted),
              Text(c.bloodType.isEmpty ? '—' : c.bloodType, style: TextStyle(fontFamily: LT.display, fontSize: 34, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -0.5, color: LT.onDark)),
            ]),
          ]),
          SizedBox(height: 12),
          Text('Allergies', style: muted),
          SizedBox(height: 2),
          // Real allergies stand out in the signal colour (its one other
          // meaning in the app); blank is "not filled in", never "none".
          if (c.allergies.isNotEmpty && c.allergies != noKnownAllergies)
            Container(
              padding: EdgeInsets.fromLTRB(10, 6, 12, 6),
              decoration: BoxDecoration(color: LT.signalFill, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.triangleAlert, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Flexible(child: Text(c.allergies, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
              ]),
            )
          else
            Text(orDash(c.allergies), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: c.allergies.isEmpty ? FontWeight.w400 : FontWeight.w600, fontStyle: c.allergies.isEmpty ? FontStyle.italic : null, color: LT.onDark)),
          SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 6, children: [
            if (widget.lifeTrackId case final id?)
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('LifeTrack ID', style: muted),
                Text(LifeTrackId.display(id), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: LT.onDark, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            if (widget.abhaMasked case final a?)
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('ABHA', style: muted),
                Text(a, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: LT.onDark)),
              ]),
          ]),
        ]),
      ),
    );
  }

  /// QR codes are always black on white.
  Widget _backFace() => Container(
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LT.radiusLg)),
          shadows: [BoxShadow(color: Colors.black.withValues(alpha: LT.dark ? 0.45 : 0.20), blurRadius: 28, offset: Offset(0, 12))],
        ),
        padding: EdgeInsets.all(14),
        child: Row(children: [
          AspectRatio(aspectRatio: 1, child: QrImageView(data: widget.qrText, padding: EdgeInsets.zero, backgroundColor: Colors.white)),
          SizedBox(width: 14),
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Scan for these details', style: TextStyle(fontFamily: LT.body, fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0E0E0E))),
                SizedBox(height: 6),
                Flexible(child: Text('Any phone camera — no app or internet needed. Tap to turn back.', overflow: TextOverflow.fade, style: TextStyle(fontFamily: LT.body, fontSize: 13, height: 1.4, color: Color(0xFF45443F)))),
              ]),
            ),
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
  List<String> _problems = [];

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
    if (!mounted) return;
    celebrate(context, 'Emergency ID saved');
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
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.onboarding) ...[StepIndicator(step: 2), SizedBox(height: 24)],
            Text('If you cannot speak for yourself', style: LT.hero),
            SizedBox(height: 8),
            Text('This one card is kept outside your encrypted records so it can be shown to whoever is treating you.', style: LT.lede),
          ]),
        ),
        ShadCard(
          color: Color(0xFFFFF7ED),
          borderColor: Color(0xFFFED7AA),
          margin: EdgeInsets.fromLTRB(16, 0, 16, 18),
          padding: EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // The fill is light in both modes, so the inks are fixed too —
            // theme inks turn near-white in dark mode and vanish here.
            Icon(LucideIcons.eye, size: 16, color: LT.signalFill),
            SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                style: TextStyle(fontSize: 14, height: 1.5, color: LT.cautionInk),
                TextSpan(children: [
                TextSpan(text: 'A stranger can read this. ', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF431407))),
                TextSpan(text: 'Put in what a paramedic needs and nothing more — no address, no ID numbers.'),
              ]),
              ),
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
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Chip2(noKnownAllergies, exclusive: false, selected: _allergies.text.trim() == noKnownAllergies, onTap: () => setState(() {
              _allergies.text = _allergies.text.trim() == noKnownAllergies ? '' : noKnownAllergies;
            })),
          ),
        ),
        _text('Ongoing conditions', _conditions),
        _text('Current medicines', _meds),
        _text('Emergency contact', _contact),
        _text('Relation', _relation),
        _text('Contact phone', _phone, type: TextInputType.phone),
        for (final p in _problems) Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 6), child: Text(p, style: LT.small.copyWith(color: LT.signal))),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Text('You can leave any of these blank. Only you can edit this card — LifeTrack\'s insights never write to it.', style: LT.small),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: SlabButton(widget.onboarding ? 'Finish setup' : 'Save card', onPressed: _save),
        ),
      ]);
}
