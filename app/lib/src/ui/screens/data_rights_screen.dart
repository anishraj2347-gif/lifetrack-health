import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../model/custody.dart';
import '../../app/app_services.dart';
import '../app_lock.dart';
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
  bool _erasing = false;
  bool _exporting = false;
  bool _protect = true;

  Future<void> _export() async {
    setState(() => _exporting = true);
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    File? file;
    try {
      String? password;
      if (_protect) {
        password = AppServices.newBackupPassword();
        if (!await _showPassword(password)) return;
      }
      final export = await s.exportCurrent(encrypted: password != null);
      file = File('${(await getTemporaryDirectory()).path}/${export.fileName}');
      await file.writeAsBytes(export.zip(password: password), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/zip')], subject: 'My LifeTrack records'));
    } on CustodyRefused catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not export. ${plainError(e)}')));
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

  /// The export's password, shown once before the file is made.
  Future<bool> _showPassword(String password) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Password for this file'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Write it down or keep it in a password manager. It is shown only now, and the file will not open without it.'),
            SizedBox(height: 14),
            SelectableText(password, style: LT.title.copyWith(fontSize: 18, letterSpacing: 1)),
            SizedBox(height: 14),
            Text('Opens with 7-Zip or WinRAR on a computer, Keka on a Mac, or ZArchiver on Android.', style: LT.small),
          ]),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: password)), child: Text('Copy')),
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('I have saved it')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: ListView(children: [
          Masthead(eyebrow: 'Your data', title: 'What is held, where'),
          SizedBox(height: 14),
          _section('On this phone', 'Your profile, records, notes, the permissions you have given and your access log — encrypted under a key in the phone\'s secure hardware. The Emergency ID card is kept outside the app lock so it can be shown from the lock screen in an emergency; it is encrypted on the phone like the rest.'),
          _section('With LifeTrack', 'No records are stored with LifeTrack. When you share with a doctor or a linked family member, it is encrypted on this phone to their device, passes through LifeTrack\'s relay, and is deleted there once collected or within 48 hours. If you turn on backup, LifeTrack also holds an encrypted copy of your records, encrypted on this phone with a key made from a password the app creates; whoever has that password or two of your recovery codes can open it. The app generates the password because a weak one could be guessed from what the service stores.'),
          _section('Why we process it', 'To keep your medical records for you, to compare values with published ranges when you turn Insights on, and to let a doctor see what you choose to share, for as long as you choose.'),
          _section('Your rights', 'You can see everything held (it is all in this app), correct any record, withdraw any permission from Share at any time, and erase everything below. Withdrawing consent does not affect access that already happened; it appears in your access log.'),
          _section('Complaints', 'Data Fiduciary: $kDataFiduciary\nGrievance Officer: $kGrievanceContact\nIf you are not satisfied with our response you may complain to the Data Protection Board of India.'),
          Eyebrow('Take a copy'),
          Note(
            'One file with everything held for this profile: a page you can read or print, the same records for another app, the original report photos and your access log.',
            icon: LucideIcons.download,
            margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
          ),
          ShadCard(
            padding: EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              IconTile(LucideIcons.fileLock),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Protect with a password', style: LT.label),
                  SizedBox(height: 4),
                  Text(
                    _protect
                        ? 'The file is encrypted (AES-256). The app makes a password and shows it once.'
                        : 'Off: the file is not encrypted — anyone who gets it can read it.',
                    style: LT.small.copyWith(color: _protect ? null : LT.signal),
                  ),
                ]),
              ),
              Switch(value: _protect, onChanged: (v) => setState(() => _protect = v)),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SlabButton('Export my records', variant: ButtonVariant.outline, icon: LucideIcons.fileDown, onPressed: _exporting ? null : _export),
          ),
          Eyebrow('Danger zone'),
          Note(icon: LucideIcons.trash2, 'Deletes this profile\'s records, notes, permissions and Emergency ID from this phone. Erasing your own profile also deletes your backup. It cannot be undone.', margin: EdgeInsets.fromLTRB(20, 0, 20, 12)),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 28),
            child: SlabButton(
              'Erase $_whose profile',
              variant: ButtonVariant.destructive,
              icon: LucideIcons.trash2,
              onPressed: _erasing ? null : _erase,
            ),
          ),
        ]),
      );

  String get _whose {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    return p.id == s.selfPatientId ? 'my' : "${p.name.split(' ').first}'s";
  }

  /// Names the person, then asks for the phone's own lock — not a typed
  /// English word, which is hard for many users and easy for anyone holding
  /// an unlocked phone.
  Future<void> _erase() async {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final self = p.id == s.selfPatientId;
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(self ? 'Erase your profile?' : "Erase ${p.name}'s profile?"),
        content: Text('${self ? 'Your' : "${p.name}'s"} records, notes, permissions and Emergency ID are deleted from this phone${self ? ', and your backup too' : ''}. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Erase', style: TextStyle(color: LT.signal))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final lock = AppLockGate.of(context);
    if (lock != null && !await lock.confirm(self ? 'Confirm it is you to erase your profile' : "Confirm it is you to erase ${p.name}'s profile")) return;
    if (!mounted) return;
    setState(() => _erasing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.eraseProfile();
    } on CustodyRefused catch (e) {
      setState(() => _erasing = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    AppScope.changed(context);
  }

  Widget _section(String title, String body) => ShadCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(body, style: LT.small.copyWith(fontSize: 14, color: LT.ink2)),
        ]),
      );
}
