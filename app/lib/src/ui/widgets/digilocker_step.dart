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
          const SizedBox(height: 12),
          Text(v.name, style: LT.title.copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Text('Born ${fullDate(v.dateOfBirth)}${v.gender == null ? '' : ' · ${switch (v.gender) { 'F' => 'Female', 'M' => 'Male', _ => 'Other' }}'}', style: LT.small),
          const SizedBox(height: 8),
          const Text('As DigiLocker confirmed it. LifeTrack keeps no Aadhaar number and no document.', style: LT.small),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: SlabButton(
          _waiting ? 'Waiting for DigiLocker…' : widget.buttonLabel ?? 'Verify with DigiLocker',
          icon: LucideIcons.shieldCheck,
          onPressed: _waiting ? null : _go,
        ),
      ),
      if (_waiting)
        const Note('Finish signing in to DigiLocker in the browser, then come back here. This page updates by itself.', icon: LucideIcons.externalLink),
      if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
    ]);
  }
}
