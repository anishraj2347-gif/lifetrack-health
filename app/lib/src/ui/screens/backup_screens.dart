import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_services.dart';
import '../../crypto/vault_codec.dart';
import '../../model/custody.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// Me → Backup: turn it on, see when it last ran, back up now, turn it off.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _notes = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on VaultError catch (e) {
      _error = e.patientMessage;
    } on CustodyRefused catch (e) {
      _error = e.message;
    } on Object {
      _error = 'Could not reach the backup service. Your records are unchanged on this phone.';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        AppScope.changed(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final on = s.backupAccount != null;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        Masthead(
          eyebrow: 'Backup',
          title: on ? 'Backup is on' : 'Back up your records',
          trailing: on ? const Badge2('On', tone: BadgeTone.trace) : const Badge2('Off', tone: BadgeTone.outline),
        ),
        const SizedBox(height: 14),
        if (!s.backupEnabled)
          const Note('The backup service is not set up in this build.', icon: LucideIcons.cloudOff)
        else if (!on)
          ..._off(s)
        else
          ..._on(s),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        const SizedBox(height: 28),
      ]),
    );
  }

  List<Widget> _off(AppServices s) => [
        const ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What is backed up', style: LT.label),
            SizedBox(height: 6),
            Text('Every profile on this phone: records, photos of reports and prescriptions, allergies, conditions, family illnesses and the Emergency ID. '
                'Not the access log or who you gave access to.', style: LT.small),
            SizedBox(height: 12),
            Text('How', style: LT.label),
            SizedBox(height: 6),
            Text('Encrypted on this phone before it leaves, with a key made from a password the app creates for you. '
                'LifeTrack stores the encrypted copy. Whoever has the password — or two of the three recovery codes — can open it.', style: LT.small),
          ]),
        ),
        ShadCard(
          onTap: () => setState(() => _notes = !_notes),
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(children: [
            Checkbox(value: _notes, onChanged: (v) => setState(() => _notes = v ?? false)),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Include personal notes', style: LT.label),
                SizedBox(height: 4),
                Text('Off by default. Notes otherwise stay on this phone only.', style: LT.small),
              ]),
            ),
          ]),
        ),
        const Note('Next you will see a password and recovery codes, once. Keep them somewhere safe that is not this phone.', icon: LucideIcons.keyRound),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SlabButton(_busy ? 'Encrypting…' : 'Turn on backup', icon: LucideIcons.cloudUpload, onPressed: _busy
              ? null
              : () => _run(() async {
                    final kit = await s.setUpBackup(includeNotes: _notes);
                    if (!mounted) return;
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecoveryKitScreen(kit: kit)));
                  })),
        ),
      ];

  List<Widget> _on(AppServices s) => [
        ShadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Account code', style: LT.small),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(s.backupAccount!, style: LT.title.copyWith(fontSize: 20, letterSpacing: 0.5))),
              IconButton(
                tooltip: 'Copy account code',
                icon: const Icon(LucideIcons.copy, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: s.backupAccount!)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              s.lastBackupError != null
                  ? 'Last attempt failed: ${s.lastBackupError}'
                  : s.lastBackupAt == null
                      ? 'Not backed up yet'
                      : 'Last backed up ${dateTime(s.lastBackupAt!)}',
              style: LT.small.copyWith(color: s.lastBackupError != null ? LT.signal : LT.ink3),
            ),
          ]),
        ),
        const Note('Changes are backed up as you make them. If the service cannot be reached, the next change or "Back up now" tries again.', icon: LucideIcons.refreshCw),
        ShadCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Include personal notes', style: LT.label),
                SizedBox(height: 4),
                Text('Otherwise notes stay on this phone only', style: LT.small),
              ]),
            ),
            Switch(value: s.backupIncludesNotes, onChanged: _busy ? null : (v) => _run(() => s.setBackupIncludesNotes(v))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SlabButton(_busy ? 'Backing up…' : 'Back up now', icon: LucideIcons.cloudUpload, onPressed: _busy ? null : () => _run(s.backUpNow)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SlabButton('Turn off and delete the backup', variant: ButtonVariant.ghost, icon: LucideIcons.trash2, onPressed: _busy
              ? null
              : () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Delete the backup?'),
                      content: const Text('The encrypted copy is deleted from the LifeTrack server. Records on this phone are not touched. '
                          'If this phone is lost after this, the records cannot be brought back.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Keep backup')),
                        TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (yes == true) await _run(s.turnOffBackup);
                }),
        ),
      ];
}

/// Shown once, right after backup is turned on. The app keeps neither the
/// password nor these two codes; the third code stays on this phone.
class RecoveryKitScreen extends StatefulWidget {
  const RecoveryKitScreen({super.key, required this.kit});
  final RecoveryKit kit;
  @override
  State<RecoveryKitScreen> createState() => _RecoveryKitScreenState();
}

class _RecoveryKitScreenState extends State<RecoveryKitScreen> {
  bool _saved = false;

  String get _sheet => 'LifeTrack backup — keep this safe, not on your phone.\n\n'
      'Account code: ${widget.kit.account}\n'
      'Password: ${widget.kit.password}\n'
      'Recovery code: ${widget.kit.printCode}\n\n'
      'To restore on a new phone: install LifeTrack, choose "Restore from backup", enter the account code and the password.';

  String get _contactMessage => 'Please keep this LifeTrack recovery code for me. I may ask for it if I lose my phone.\n\n'
      'Account code: ${widget.kit.account}\n'
      'Recovery code: ${widget.kit.contactCode}';

  @override
  Widget build(BuildContext context) {
    final k = widget.kit;
    return PopScope(
      canPop: _saved,
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: ListView(children: [
          const Masthead(eyebrow: 'Backup is on', title: 'Your recovery kit', description: 'Shown once. The app does not keep the password.'),
          const SizedBox(height: 14),
          ShadCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Account code', style: LT.small),
              const SizedBox(height: 4),
              SelectableText(k.account, style: LT.title.copyWith(fontSize: 20, letterSpacing: 0.5)),
              const SizedBox(height: 14),
              const Text('Password', style: LT.small),
              const SizedBox(height: 4),
              SelectableText(k.password, style: LT.title.copyWith(fontSize: 20, letterSpacing: 1)),
            ]),
          ),
          const Note('With the account code and password, a new phone gets everything back.', icon: LucideIcons.keyRound),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: SlabButton('Save or print the recovery sheet', icon: LucideIcons.fileDown, onPressed: () => SharePlus.instance.share(ShareParams(text: _sheet, subject: 'LifeTrack recovery sheet'))),
          ),
          const Eyebrow('If the password is lost'),
          const ShadCard(
            child: Text('There are three recovery codes; any two open the backup without the password. One stays on this phone, one is on the recovery sheet, '
                'and one is for someone you trust.', style: LT.small),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: SlabButton('Send a code to someone you trust', variant: ButtonVariant.outline, icon: LucideIcons.userCheck,
                onPressed: () => SharePlus.instance.share(ShareParams(text: _contactMessage, subject: 'LifeTrack recovery code'))),
          ),
          ShadCard(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            onTap: () => setState(() => _saved = !_saved),
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(children: [
              Checkbox(value: _saved, onChanged: (v) => setState(() => _saved = v ?? false)),
              const Expanded(child: Text('I have saved the account code and password somewhere other than this phone.', style: LT.label)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
            child: SlabButton('Done', icon: LucideIcons.check, onPressed: _saved ? () => Navigator.of(context).pop() : null),
          ),
        ]),
      ),
    );
  }
}

/// First screen on a new phone, from onboarding: bring a backup back.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key, required this.onRestored});
  final VoidCallback onRestored;
  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _code1 = TextEditingController();
  final _code2 = TextEditingController();
  bool _withCodes = false;
  bool _busy = false;
  String? _error;

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = AppScope.of(context);
    try {
      final n = await s.restoreFromBackup(
        account: _account.text,
        password: _withCodes ? null : _password.text,
        codes: _withCodes ? [_code1.text, _code2.text] : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n records restored.')));
      Navigator.of(context).pop();
      widget.onRestored();
    } on VaultError catch (e) {
      setState(() => _error = e is VaultAuthenticationFailed ? 'The account code and ${_withCodes ? 'codes' : 'password'} do not match a backup.' : e.patientMessage);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on ArgumentError {
      setState(() => _error = 'Those two codes are not from the same backup, or one is the same code twice.');
    } on CustodyRefused catch (e) {
      setState(() => _error = e.message);
    } on Object {
      setState(() => _error = 'Could not reach the backup service.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _account.text.trim().isNotEmpty && (_withCodes ? _code1.text.trim().isNotEmpty && _code2.text.trim().isNotEmpty : _password.text.trim().isNotEmpty);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        const Masthead(eyebrow: 'Restore', title: 'Bring back your records', description: 'Use the recovery sheet you saved when you turned on backup.'),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Account code',
          child: TextField(controller: _account, textCapitalization: TextCapitalization.characters, autocorrect: false, decoration: const InputDecoration(hintText: 'e.g. LT-7KQM2-XPA9D'), onChanged: (_) => setState(() {})),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Wrap(spacing: 8, children: [
            Chip2('Password', selected: !_withCodes, onTap: () => setState(() => _withCodes = false)),
            Chip2('Two recovery codes', selected: _withCodes, onTap: () => setState(() => _withCodes = true)),
          ]),
        ),
        if (!_withCodes)
          LabeledField(
            label: 'Password',
            child: TextField(controller: _password, textCapitalization: TextCapitalization.characters, autocorrect: false, onChanged: (_) => setState(() {})),
          )
        else ...[
          LabeledField(label: 'First recovery code', child: TextField(controller: _code1, autocorrect: false, onChanged: (_) => setState(() {}))),
          LabeledField(label: 'Second recovery code', child: TextField(controller: _code2, autocorrect: false, onChanged: (_) => setState(() {}))),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: SlabButton(_busy ? 'Decrypting…' : 'Restore', icon: LucideIcons.cloudDownload, onPressed: ready && !_busy ? _restore : null),
        ),
      ]),
    );
  }
}
