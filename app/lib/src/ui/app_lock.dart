import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../security/unlocker.dart';
import 'app_scope.dart';
import 'screens/emergency_screen.dart';
import 'theme.dart';
import 'widgets/parts.dart';

/// Covers the app with the phone's own lock when it opens, and again when it
/// comes back after [relockAfter] in the background. The Emergency ID stays
/// one tap away, because that is what it is for.
///
/// A phone with no screen lock is asked to set one: the records do not open
/// on a phone anyone can pick up. Demo builds (LT_DEMO_TOOLS) still open.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.unlocker, required this.child, this.relockAfter = const Duration(minutes: 1)});
  final Unlocker unlocker;
  final Widget child;
  final Duration relockAfter;

  /// The gate above this context, for the Me screen's switch.
  static AppLockControl? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Scope>()?.control;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool? _available;
  bool _locked = true;
  bool _asking = false;
  DateTime? _leftAt;

  bool get _enabled => AppScope.of(context).appLockEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  Future<void> _check() async {
    final a = await widget.unlocker.available();
    if (!mounted) return;
    setState(() => _available = a);
    if (a && _enabled && _locked) _ask();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The system unlock prompt itself pauses the app; don't count that.
    if (_asking) return;
    final now = AppScope.of(context).clock();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= now;
    } else if (state == AppLifecycleState.resumed) {
      final away = _leftAt == null ? Duration.zero : now.difference(_leftAt!);
      _leftAt = null;
      if (_available == false) {
        _check(); // they may have just set a screen lock in Settings
      } else if (_available == true && _enabled && !_locked && away >= widget.relockAfter) {
        // Screens pushed over the home would otherwise stay on top of the lock.
        Navigator.of(context).popUntil((r) => r.isFirst);
        setState(() => _locked = true);
        _ask();
      }
    }
  }

  Future<void> _ask() async {
    if (_asking) return;
    setState(() => _asking = true);
    final ok = await widget.unlocker.unlock('Unlock LifeTrack to see your health records');
    if (!mounted) return;
    setState(() {
      _asking = false;
      if (ok) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_available == null) return Scaffold();
    if (!_available! && _enabled && !AppScope.of(context).demoTools) {
      return _LockScreen(asking: false, onUnlock: _check, noScreenLock: true);
    }
    if (!_available! || !_enabled || !_locked) {
      return _Scope(control: AppLockControl._(this), child: widget.child);
    }
    return _LockScreen(asking: _asking, onUnlock: _ask);
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.asking, required this.onUnlock, this.noScreenLock = false});
  final bool asking;
  final VoidCallback onUnlock;

  /// The phone has no screen lock: say so, and check again on tap.
  final bool noScreenLock;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: LT.night,
        body: PhotoHero(Photos.reading, children: [
          Center(child: IconTile(LucideIcons.lock, color: LT.onButton, background: LT.button)),
          SizedBox(height: 16),
          Text(noScreenLock ? 'Set a screen lock first' : 'LifeTrack is locked',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: LT.display, fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: Colors.white)),
          SizedBox(height: 8),
          Text(
              noScreenLock
                  ? "This phone has no PIN, pattern, fingerprint or face lock, so anyone holding it could read your records. Set one in the phone's settings, then come back."
                  : 'Use your fingerprint, face or phone PIN.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: LT.onNightMuted)),
          SizedBox(height: 28),
          SlabButton(noScreenLock ? 'Check again' : 'Unlock', icon: LucideIcons.lockOpen, onPressed: asking ? null : onUnlock, onNight: true),
          SizedBox(height: 12),
          SlabButton('Emergency ID', icon: LucideIcons.heartPulse, variant: ButtonVariant.outline, onNight: true, onPressed: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmergencyScreen(fromLockScreen: true)));
          }),
          SizedBox(height: 10),
          Text('Anyone who opens LifeTrack on this phone can see the Emergency ID without unlocking the app. Each time is written to your access log.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.45, color: LT.onNightMuted)),
        ]),
      );
}

class AppLockControl {
  AppLockControl._(this._gate);
  final _AppLockGateState _gate;

  bool get available => _gate._available ?? false;

  /// Asks for the phone's own lock (fingerprint, face or PIN) before a
  /// sensitive step. True straight away when the phone has no lock to ask.
  Future<bool> confirm(String reason) async => !available || await _gate.widget.unlocker.unlock(reason);

  /// Turning the lock off needs the phone's lock first, so whoever picks up
  /// an unlocked phone cannot switch it off.
  Future<bool> setEnabled(bool on) async {
    final s = AppScope.of(_gate.context);
    if (!on && !await _gate.widget.unlocker.unlock('Confirm it is you to turn off the app lock')) return false;
    await s.setAppLock(on);
    _gate._locked = false;
    return true;
  }
}

class _Scope extends InheritedWidget {
  const _Scope({required this.control, required super.child});
  final AppLockControl control;
  @override
  bool updateShouldNotify(_Scope old) => old.control._gate != control._gate;
}
