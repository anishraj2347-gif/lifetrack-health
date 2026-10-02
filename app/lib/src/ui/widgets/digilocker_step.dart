import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifetrack_protocol/lifetrack_protocol.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../identity/identity_verifier.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'parts.dart';

/// "Verify with DigiLocker": opens DigiLocker in the browser, waits, and
/// shows what DigiLocker confirmed. [purpose] is `self` (their own Aadhaar)
/// or `newborn` (the owner's DigiLocker birth certificate).
class DigiLockerStep extends StatefulWidget {
  const DigiLockerStep({super.key, required this.purpose, required this.onVerified, this.buttonLabel});
  final String purpose;
  final ValueChanged<IdentityAttestation> onVerified;
  final String? buttonLabel;

  @override
  State<DigiLockerStep> createState() => _DigiLockerStepState();
}

class _DigiLockerStepState extends State<DigiLockerStep> {
  bool _waiting = false;
  String? _error;
  IdentityAttestation? _done;

  /// Set while the service waits for the hand-back code.
  Completer<String?>? _code;
  bool _codeWrong = false;
  final _codeField = TextEditingController();

  @override
  void dispose() {
    _code?.complete(null);
    _codeField.dispose();
    super.dispose();
  }

  Future<String?> _askCode(bool wrong) {
    final c = Completer<String?>();
    if (mounted) {
      setState(() {
        _code = c;
        _codeWrong = wrong;
        _codeField.clear();
      });
    } else {
      c.complete(null);
    }
    return c.future;
  }

  void _answer(String? code) {
    final c = _code;
    if (c == null) return;
    setState(() => _code = null);
    c.complete(code);
  }

  Future<void> _go() async {
    setState(() {
      _waiting = true;
      _error = null;
    });
    try {
      final v = await AppScope.of(context).verifyWithDigiLocker(
        purpose: widget.purpose,
        openUrl: (u) async {
          if (!await launchUrl(u, mode: LaunchMode.externalApplication)) throw const VerificationFailed('Could not open DigiLocker.');
        },
        askCode: _askCode,
      );
      if (!mounted) return;
      setState(() => _done = v);
      widget.onVerified(v);
    } on VerificationFailed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _done;
    if (v != null) {
      return ShadCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Badge2('Verified · ${v.method.label}', tone: BadgeTone.trace),
          SizedBox(height: 12),
          Text(v.name, style: LT.title.copyWith(fontSize: 22)),
          SizedBox(height: 4),
          Text('Born ${fullDate(v.dateOfBirth)}${v.gender == null ? '' : ' · ${switch (v.gender) { 'F' => 'Female', 'M' => 'Male', _ => 'Other' }}'}', style: LT.small),
          SizedBox(height: 8),
          Text('As DigiLocker confirmed it. LifeTrack keeps no Aadhaar number and no document.', style: LT.small),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: SlabButton(
          _waiting ? 'Waiting for DigiLocker…' : widget.buttonLabel ?? 'Verify with DigiLocker',
          icon: LucideIcons.shieldCheck,
          onPressed: _waiting ? null : _go,
        ),
      ),
      if (_waiting && _code == null)
        Note('Finish signing in to DigiLocker in the browser. The last page shows a code — come back here and type it in.', icon: LucideIcons.externalLink),
      if (_code != null)
        Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_codeWrong ? 'That code did not match. Check the browser page and try again.' : 'Type the code the DigiLocker page showed you',
                style: LT.small.copyWith(color: _codeWrong ? LT.signal : null)),
            SizedBox(height: 8),
            TextField(
              controller: _codeField,
              autofocus: true,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: 'e.g. 7KQM-2XPA'),
              onSubmitted: (v) => _answer(v.trim().isEmpty ? null : v.trim()),
            ),
            SizedBox(height: 8),
            Text('Only type a code from a page YOU just signed in on. If someone sent you a link or asks you for a code, stop.', style: LT.small),
            SizedBox(height: 8),
            SlabButton('Continue', icon: LucideIcons.check, onPressed: () => _answer(_codeField.text.trim().isEmpty ? null : _codeField.text.trim())),
            SizedBox(height: 6),
            SlabButton('Cancel', variant: ButtonVariant.ghost, onPressed: () => _answer(null)),
          ]),
        ),
      if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
    ]);
  }
}
