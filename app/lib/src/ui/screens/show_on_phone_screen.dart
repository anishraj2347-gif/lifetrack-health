import 'package:flutter/material.dart';
import '../l10n/l10n.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/summary_view.dart';
import 'originals_viewer.dart';

/// P8, the pilot: the patient hands the phone to the doctor. Built from the
/// patient's own data on the phone; nothing is sent anywhere, no doctor app
/// or server is needed.
class ShowOnPhoneScreen extends StatelessWidget {
  const ShowOnPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final bundle = s.ownSummary();
    final updated = bundle['profileUpdatedAt'] as String?;
    return Scaffold(
      backgroundColor: LT.raised,
      appBar: AppBar(backgroundColor: LT.raised, title: Text(t('For the doctor'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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
        const SizedBox(height: 28),
      ]),
    );
  }
}
