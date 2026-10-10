import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_lock.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';
import '../widgets/summary_view.dart';
import 'originals_viewer.dart';

/// P8, the pilot: the patient hands the phone to the doctor. Built from the
/// patient's own data on the phone; nothing is sent anywhere, no doctor app
/// or server is needed.
///
/// While the doctor holds the phone, this screen is all they can reach:
/// back does not lead into the rest of the app until the patient unlocks
/// with the phone's own lock.
class ShowOnPhoneScreen extends StatelessWidget {
  const ShowOnPhoneScreen({super.key});

  static Future<void> _giveBack(BuildContext context) async {
    final lock = AppLockGate.of(context);
    final ok = lock == null || await lock.confirm('Unlock to take your phone back');
    if (ok && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final bundle = s.ownSummary();
    final updated = bundle['profileUpdatedAt'] as String?;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _giveBack(context);
      },
      child: Scaffold(
      backgroundColor: LT.raised,
      appBar: AppBar(
        backgroundColor: LT.raised,
        automaticallyImplyLeading: false,
        title: Text('For the doctor', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          TextButton.icon(onPressed: () => _giveBack(context), icon: Icon(LucideIcons.lockKeyhole, size: 16), label: Text('Give back')),
        ],
      ),
      body: ListView(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.name} · ${p.sex.name == 'female' ? 'F' : p.sex.name == 'male' ? 'M' : '—'} · ${p.ageAt(s.clock())}', style: LT.title.copyWith(fontSize: 22)),
            Text(
              'Shown on the patient\'s phone · nothing is sent${updated == null ? '' : ' · updated by patient ${updated.substring(0, 10)}'}',
              style: LT.small,
            ),
          ]),
        ),
        SummaryView(
          bundle: bundle,
          onOpenOriginal: (id) async {
            final r = s.records().firstWhere((x) => x.id == id);
            final pages = await s.originals(r);
            if (!context.mounted || pages.isEmpty) return;
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OriginalsViewer(title: r.title, pages: pages)));
          },
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: SlabButton('Done — give the phone back', icon: LucideIcons.lockKeyhole, variant: ButtonVariant.outline, onPressed: () => _giveBack(context)),
        ),
      ]),
      ),
    );
  }
}
