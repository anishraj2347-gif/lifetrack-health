import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../model/custody.dart';
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
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    File? file;
    try {
      final export = await s.exportCurrent();
      file = File('${(await getTemporaryDirectory()).path}/${export.fileName}');
      await file.writeAsBytes(export.zip(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/zip')], subject: 'My LifeTrack records'));
    } on CustodyRefused catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not export: $e')));
    } finally {
      // share_plus has copied it into this app's private cache (cleared on the
      // next share), so this copy is not needed.
      try {
        await file?.delete();
      } on Object {
        // Already gone.
      }
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: ListView(children: [
          const Masthead(eyebrow: 'Your data', title: 'What is held, where'),
          const SizedBox(height: 14),
          _section('On this phone', 'Your profile, records, notes, the permissions you have given and your access log — encrypted under a key in the phone\'s secure hardware. The Emergency ID card is kept separately and unencrypted so it can be shown in an emergency.'),
          _section('With LifeTrack', 'No records are stored with LifeTrack. When you share with a doctor or a linked family member, it is encrypted on this phone to their device, passes through LifeTrack\'s relay, and is deleted there once collected or within 48 hours. When the backup service launches it will hold an encrypted copy of doctor-issued documents; a weak passphrase could be guessed from what that service stores, which is why we will ask for six unrelated words.'),
          _section('Why we process it', 'To keep your medical records for you, to compare values with published ranges when you turn Insights on, and to let a doctor see what you choose to share, for as long as you choose.'),
          _section('Your rights', 'You can see everything held (it is all in this app), correct any record, withdraw any permission from Share at any time, and erase everything below. Withdrawing consent does not affect access that already happened; it appears in your access log.'),
          _section('Complaints', 'Data Fiduciary: $kDataFiduciary\nGrievance Officer: $kGrievanceContact\nIf you are not satisfied with our response you may complain to the Data Protection Board of India.'),
          const Eyebrow('Take a copy'),
          const Note(
            'One file with everything held for this profile: a page you can read or print, the same records for another app, the original report photos and your access log. '
            'The file is not encrypted — anyone you send it to can read it.',
            icon: LucideIcons.download,
            margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SlabButton('Export my records', variant: ButtonVariant.outline, icon: LucideIcons.fileDown, onPressed: _exporting ? null : _export),
          ),
          const Eyebrow('Danger zone'),
          const Note(icon: LucideIcons.trash2, 'Deletes this profile\'s records, notes, permissions and Emergency ID from this phone. It cannot be undone, and with no backup there is no way to get them back.', margin: EdgeInsets.fromLTRB(20, 0, 20, 12)),
          LabeledField(label: 'Type ERASE to confirm', child: TextField(controller: _confirm, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'ERASE'))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            child: SlabButton(
              'Erase my profile',
              variant: ButtonVariant.destructive,
              icon: LucideIcons.trash2,
              onPressed: _confirm.text.trim() == 'ERASE' && !_erasing
                  ? () async {
                      setState(() => _erasing = true);
                      final s = AppScope.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await s.eraseProfile(account: s.currentPatientId!);
                      } on CustodyRefused catch (e) {
                        setState(() => _erasing = false);
                        messenger.showSnackBar(SnackBar(content: Text(e.message)));
                        return;
                      }
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      AppScope.changed(context);
                    }
                  : null,
            ),
          ),
        ]),
      );

  Widget _section(String title, String body) => ShadCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(body, style: LT.small.copyWith(fontSize: 14, color: LT.ink2)),
        ]),
      );
}
