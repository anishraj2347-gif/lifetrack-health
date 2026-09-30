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
    widget.unlocker.available().then((a) {
      if (!mounted) return;
      setState(() => _available = a);
      if (a && _enabled) _ask();
    });
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
      if (_available == true && _enabled && !_locked && away >= widget.relockAfter) {
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
    if (_available == null) return const Scaffold();
    if (!_available! || !_enabled || !_locked) {
      return _Scope(control: AppLockControl._(this), child: widget.child);
    }
    return _LockScreen(asking: _asking, onUnlock: _ask);
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.asking, required this.onUnlock});
  final bool asking;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(children: [
              const Spacer(),
              const IconTile(LucideIcons.lock, color: LT.ink, background: LT.accent),
              const SizedBox(height: 20),
              const Text('LifeTrack is locked', style: TextStyle(fontFamily: LT.body, fontSize: 24, fontWeight: FontWeight.w600, color: LT.ink)),
              const SizedBox(height: 8),
              const Text('Use your fingerprint, face or phone PIN.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: LT.ink3)),
              const Spacer(),
              SlabButton('Unlock', icon: LucideIcons.lockOpen, onPressed: asking ? null : onUnlock),
              const SizedBox(height: 12),
              SlabButton('Emergency ID', icon: LucideIcons.heartPulse, variant: ButtonVariant.outline, onPressed: () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmergencyScreen(fromLockScreen: true)));
              }),
              const SizedBox(height: 8),
              const Text('Anyone holding the phone can open the Emergency ID. Each time is written to your access log.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: LT.ink3)),
            ]),
          ),
        ),
      );
}

/// What the Me screen may do with the lock.
class AppLockControl {
  AppLockControl._(this._gate);
  final _AppLockGateState _gate;

  bool get available => _gate._available ?? false;

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
