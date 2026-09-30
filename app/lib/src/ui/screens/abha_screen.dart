import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../model/abha.dart';
import '../../model/custody.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// The ABHA of the profile on screen: add, view, show as a QR, remove.
/// Optional — nothing in LifeTrack depends on it.
class AbhaScreen extends StatefulWidget {
  const AbhaScreen({super.key});
  @override
  State<AbhaScreen> createState() => _AbhaScreenState();
}

class _AbhaScreenState extends State<AbhaScreen> {
  final _number = TextEditingController();
  final _address = TextEditingController();
  bool _editing = false;
  String? _error;

  Future<void> _save() async {
    try {
      await AppScope.of(context).setAbha(number: _number.text, address: _address.text);
      if (!mounted) return;
      AppScope.changed(context);
      setState(() {
        _editing = false;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on CustodyRefused catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final abha = p.abha;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(eyebrow: 'ABHA health ID', title: p.name, description: 'Ayushman Bharat Health Account — the 14-digit health ID hospitals and labs on ABDM use.'),
        const SizedBox(height: 14),
        if (abha != null && !_editing) ..._show(abha) else ..._form(abha),
        const Eyebrow("Don't have an ABHA?"),
        const ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('You can use LifeTrack fully without one.', style: LT.label),
            SizedBox(height: 8),
            Text(
              'ABHA is free and voluntary. You can make one on the ABHA app or at abha.abdm.gov.in with an OTP to your Aadhaar-linked mobile, or with a driving licence. '
              'Many hospitals can also make one at their registration desk.',
              style: LT.small,
            ),
            SizedBox(height: 8),
            Text('LifeTrack never asks for your Aadhaar number.', style: LT.small),
          ]),
        ),
        const SizedBox(height: 28),
      ]),
    );
  }

  List<Widget> _show(Abha a) => [
        ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ABHA number', style: LT.small),
            const SizedBox(height: 4),
            Text(a.display, style: LT.title.copyWith(fontSize: 24, letterSpacing: 0.5)),
            if (a.address != null) ...[
              const SizedBox(height: 12),
              const Text('ABHA address', style: LT.small),
              const SizedBox(height: 4),
              Text(a.address!, style: LT.label.copyWith(fontSize: 16)),
            ],
            const SizedBox(height: 12),
            const Badge2('Typed in · not verified with ABDM', tone: BadgeTone.caution),
          ]),
        ),
        const Note('LifeTrack cannot check an ABHA with ABDM yet, so check the digits against your ABHA card. The Emergency ID shows only the last four.', icon: LucideIcons.info),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: SlabButton('Show QR for registration', icon: LucideIcons.qrCode, onPressed: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AbhaQrScreen()));
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SlabButton('Edit', variant: ButtonVariant.outline, icon: LucideIcons.pencil, onPressed: () {
            _number.text = a.display;
            _address.text = a.address ?? '';
            setState(() => _editing = true);
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SlabButton('Remove from LifeTrack', variant: ButtonVariant.ghost, icon: LucideIcons.trash2, onPressed: () async {
            await AppScope.of(context).setAbha();
            if (mounted) AppScope.changed(context);
          }),
        ),
      ];

  List<Widget> _form(Abha? existing) => [
        LabeledField(
          label: 'ABHA number',
          hint: '14 digits, as printed on your ABHA card',
          child: TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d -]')), LengthLimitingTextInputFormatter(17)],
            decoration: const InputDecoration(hintText: 'e.g. 91-1234-5678-9012'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        LabeledField(
          label: 'ABHA address (optional)',
          child: TextField(
            controller: _address,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'e.g. anjali.sharma@abdm'),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: SlabButton(existing == null ? 'Add ABHA' : 'Save', icon: LucideIcons.check, onPressed: Abha.parseNumber(_number.text) == null ? null : _save),
        ),
        if (existing != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: SlabButton('Cancel', variant: ButtonVariant.outline, onPressed: () => setState(() => _editing = false)),
          ),
      ];
}

/// For a registration desk to copy the ABHA into their system. Shown only
/// inside the unlocked app. This is not ABDM's "Scan & Share" code, which
/// runs the other way (the patient scans the hospital's code) and needs the
/// ABDM integration.
class AbhaQrScreen extends StatelessWidget {
  const AbhaQrScreen({super.key});

  static String payload(String name, DateTime dob, String sex, Abha a) => jsonEncode({
        'type': 'abha',
        'abhaNumber': a.display,
        if (a.address != null) 'abhaAddress': a.address,
        'name': name,
        'dob': dob.toIso8601String().substring(0, 10),
        'gender': sex,
        'verified': a.verified,
      });

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).currentPatient!;
    final a = p.abha!;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(eyebrow: 'ABHA for registration', title: p.name),
        ShadCard(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(children: [
            QrImageView(data: payload(p.name, p.dateOfBirth, p.sex.name, a), size: 250, backgroundColor: Colors.white),
            const SizedBox(height: 12),
            Text(a.display, style: LT.title.copyWith(fontSize: 22, letterSpacing: 0.5)),
            if (a.address != null) ...[const SizedBox(height: 4), Text(a.address!, style: LT.small)],
          ]),
        ),
        const Note(
          'Holds your ABHA number and address, name, date of birth and sex — nothing from your records. '
          'If their system cannot scan it, they can type the number shown.',
          icon: LucideIcons.info,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 28),
        ),
      ]),
    );
  }
}
