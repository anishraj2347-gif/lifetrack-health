import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// DPDP Act 2023 surface: notice (§5), access, correction and erasure (§11–12),
/// grievance redressal (§13).
///
/// The Data Fiduciary name and the Grievance Officer's contact are
/// placeholders that must be filled in by the legal entity before any pilot.
class DataRightsScreen extends StatefulWidget {
  const DataRightsScreen({super.key});
  @override
  State<DataRightsScreen> createState() => _DataRightsScreenState();
}

const kDataFiduciary = '[Data Fiduciary — legal entity to be named before pilot]';
const kGrievanceContact = '[Grievance Officer — name and email to be added before pilot]';

class _DataRightsScreenState extends State<DataRightsScreen> {
  final _confirm = TextEditingController();
  bool _erasing = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: LT.ground, elevation: 0, foregroundColor: LT.ink),
        body: ListView(children: [
          const Masthead(eyebrow: 'Your data', title: 'What is held, where'),
          _section('On this phone', 'Your profile, records, notes, the permissions you have given and your access log — encrypted under a key in the phone\'s secure hardware. The Emergency ID card is kept separately and unencrypted so it can be shown in an emergency.'),
          _section('With LifeTrack', 'Nothing, in this version. The app has no internet permission. When the backup service launches it will hold an encrypted copy of doctor-issued documents; a weak passphrase could be guessed from what that service stores, which is why we will ask for six unrelated words.'),
          _section('Why we process it', 'To keep your medical records for you, to compare values with published ranges when you turn Insights on, and to let a doctor see what you choose to share, for as long as you choose.'),
          _section('Your rights', 'You can see everything held (it is all in this app), correct any record, withdraw any permission from Share at any time, and erase everything below. Withdrawing consent does not affect access that already happened; it appears in your access log.'),
          _section('Complaints', 'Data Fiduciary: $kDataFiduciary\nGrievance Officer: $kGrievanceContact\nIf you are not satisfied with our response you may complain to the Data Protection Board of India.'),
          const Eyebrow('Erase everything'),
          const Note('Deletes this profile\'s records, notes, permissions and Emergency ID from this phone. It cannot be undone, and with no backup there is no way to get them back.', margin: EdgeInsets.fromLTRB(20, 0, 20, 12)),
          LabeledField(label: 'Type ERASE to confirm', child: TextField(controller: _confirm, onChanged: (_) => setState(() {}))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SlabButton(
              'Erase my profile',
              color: LT.signal,
              onPressed: _confirm.text.trim() == 'ERASE' && !_erasing
                  ? () async {
                      setState(() => _erasing = true);
                      final s = AppScope.of(context);
                      await s.eraseProfile(account: s.currentPatientId!);
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      AppScope.changed(context);
                    }
                  : null,
            ),
          ),
        ]),
      );

  Widget _section(String title, String body) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LT.rule))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: LT.eyebrow),
          const SizedBox(height: 6),
          Text(body, style: LT.small.copyWith(fontSize: 14, color: LT.ink)),
        ]),
      );
}
