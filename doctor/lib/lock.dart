import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'theme.dart';

/// Demo builds may open on a phone with no screen lock; real ones may not.
const _demo = bool.fromEnvironment('LT_DEMO_TOOLS');

/// Asks the phone's own lock — fingerprint, face, PIN or pattern.
abstract class DeviceLock {
  /// False when the phone has no screen lock set.
  Future<bool> available();
  Future<bool> unlock(String reason);
}

class LocalAuthLock implements DeviceLock {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> unlock(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on Object {
      return false;
    }
  }
}

/// Patients' shared records and this device's keys sit behind the phone's
/// lock: asked when the app opens and again after [relockAfter] away. A
/// phone with no screen lock is told to set one — the records are not shown
/// on a phone anyone can pick up. In the browser this is a pass-through.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child, this.lock, this.relockAfter = const Duration(minutes: 1), this.allowWithoutLock = _demo});
  final Widget child;
  final DeviceLock? lock;
  final Duration relockAfter;
  final bool allowWithoutLock;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late final DeviceLock _lock = widget.lock ?? LocalAuthLock();
  bool? _available;
  bool _locked = true;
  bool _asking = false;
  DateTime? _leftAt;

  bool get _skip => kIsWeb && widget.lock == null;

  @override
  void initState() {
    super.initState();
    if (_skip) return;
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  Future<void> _check() async {
    final a = await _lock.available();
    if (!mounted) return;
    setState(() => _available = a);
    if (a) _ask();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_asking) return;
    final now = DateTime.now();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= now;
    } else if (state == AppLifecycleState.resumed) {
      final away = _leftAt == null ? Duration.zero : now.difference(_leftAt!);
      _leftAt = null;
      if (_available != true) {
        _check(); // they may have just set a screen lock
      } else if (!_locked && away >= widget.relockAfter) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        setState(() => _locked = true);
        _ask();
      }
    }
  }

  Future<void> _ask() async {
    if (_asking) return;
    setState(() => _asking = true);
    final ok = await _lock.unlock('Unlock to see your patients');
    if (!mounted) return;
    setState(() {
      _asking = false;
      if (ok) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_skip) return widget.child;
    if (_available == null) return Scaffold();
    if (_available == false) {
      if (widget.allowWithoutLock) return widget.child;
      return _Screen(
        title: 'Set a screen lock first',
        body: 'Patients\' records open on this phone. Set a PIN, pattern, fingerprint or face lock in the phone\'s settings, then come back.',
        action: 'Check again',
        onTap: _check,
      );
    }
    if (!_locked) return widget.child;
    return _Screen(title: 'Locked', body: 'Use your fingerprint, face or phone PIN.', action: 'Unlock', onTap: _asking ? null : _ask);
  }
}

class _Screen extends StatelessWidget {
  const _Screen({required this.title, required this.body, required this.action, required this.onTap});
  final String title;
  final String body;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_outline, size: 40, color: DT.ink),
                  SizedBox(height: 16),
                  Text(title, style: DT.h1, textAlign: TextAlign.center),
                  SizedBox(height: 8),
                  Text(body, style: DT.muted, textAlign: TextAlign.center),
                  SizedBox(height: 24),
                  Pill(action, onTap: onTap),
                ]),
              ),
            ),
          ),
        ),
      );
}
