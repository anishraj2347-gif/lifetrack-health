import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../family/family_link.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// P7, on the inviter's phone: a code the other adult scans with their own
/// LifeTrack. It carries a reply address and a public key — no records.
class FamilyInviteScreen extends StatefulWidget {
  const FamilyInviteScreen({super.key});
  @override
  State<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

class _FamilyInviteScreenState extends State<FamilyInviteScreen> {
  Future<FamilyInvite>? _invite;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invite ??= AppScope.of(context).createFamilyInvite();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GlassAppBar(),
        body: FutureBuilder<FamilyInvite>(
          future: _invite,
          builder: (context, snap) {
            if (snap.hasError) return ListView(children: [Note('Could not make an invite: ${snap.error}', icon: LucideIcons.triangleAlert)]);
            final invite = snap.data;
            if (invite == null) return Center(child: CircularProgressIndicator());
            final code = invite.encode();
            return ListView(children: [
              Masthead(
                eyebrow: 'Invite an adult',
                title: 'Ask them to scan this',
                description: 'On their own phone, in LifeTrack: Me → Join a family.',
              ),
              ShadCard(
                margin: EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Center(child: QrImageView(data: code, size: 240, backgroundColor: Colors.white)),
              ),
              ShadCard(
                child: Row(children: [
                  Expanded(child: Text(code, maxLines: 2, overflow: TextOverflow.ellipsis, style: LT.small.copyWith(fontFamily: 'monospace'))),
                  IconButton(
                    tooltip: 'Copy code',
                    icon: Icon(LucideIcons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite code copied.')));
                    },
                  ),
                ]),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: [Badge2('Works once', tone: BadgeTone.outline), Badge2('Until ${fullDate(invite.expiresAt.toLocal())}', tone: BadgeTone.outline)]),
              ),
              Note(
                'Linking never gives you their records. They choose whether to share their Emergency ID or current medicines with you, and can stop at any time. '
                'When they have joined, pull down on the Share tab, or tap "Check for prescriptions and updates".',
                icon: LucideIcons.shieldCheck,
                margin: EdgeInsets.fromLTRB(16, 16, 16, 28),
              ),
            ]);
          },
        ),
      );
}

/// P7, on the invited adult's own phone.
class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});
  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _paste = TextEditingController();
  FamilyInvite? _invite;
  String? _code;
  bool _emergency = false;
  bool _medicines = false;
  bool _busy = false;
  String? _error;

  void _read(String code) {
    if (_invite != null) return;
    try {
      final i = FamilyInvite.decode(code);
      setState(() {
        _invite = i;
        _code = code.trim();
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    final s = AppScope.of(context);
    try {
      await s.joinFamily(code: _code!, shareEmergency: _emergency, shareMedicines: _medicines);
      if (!mounted) return;
      AppScope.changed(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Linked with ${_invite!.fromName}.')));
      Navigator.of(context).pop();
    } on LinkRefused catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = plainError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: GlassAppBar(), body: _invite == null ? _scan() : _choose());

  Widget _scan() => ListView(children: [
        Masthead(eyebrow: 'Join a family', title: 'Scan their invite', description: 'The family member who invited you shows a code on their phone.'),
        Container(
          height: 300,
          margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(LT.radiusLg), color: LT.primary),
          child: ReaderWidget(
            onScan: (c) {
              final t = c.text;
              if (t != null && t.isNotEmpty) _read(t);
            },
            showGallery: false,
            showToggleCamera: false,
            tryHarder: true,
          ),
        ),
        if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
        LabeledField(label: 'Or paste the code', child: TextField(controller: _paste, onChanged: (_) => setState(() {}))),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: SlabButton('Continue', onPressed: _paste.text.trim().isEmpty ? null : () => _read(_paste.text)),
        ),
      ]);

  Widget _choose() {
    final from = _invite!.fromName;
    final me = AppScope.of(context).selfPatient!.name;
    return ListView(children: [
      Masthead(eyebrow: 'Join a family', title: 'Link with $from?', description: 'You keep your own records on this phone, as $me.'),
      Eyebrow('What $from can see'),
      _tick('My Emergency ID', 'Blood group, allergies, emergency contact', _emergency, (v) => setState(() => _emergency = v)),
      _tick('My current medicines', 'Names and doses of what I am taking now', _medicines, (v) => setState(() => _medicines = v)),
      Note(
        _emergency || _medicines
            ? 'Only this is sent, encrypted to $from\'s phone. Your reports, prescriptions and history stay here. You can change this or unlink at any time.'
            : 'Nothing will be shared — you will just be linked. You can choose later.',
        icon: LucideIcons.shieldCheck,
      ),
      if (_error != null) Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_error!, style: LT.small.copyWith(color: LT.signal))),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: SlabButton('Link with $from', icon: LucideIcons.link, onPressed: _busy ? null : _join),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 28),
        child: SlabButton('Not now', variant: ButtonVariant.outline, onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }
}

Widget _tick(String title, String sub, bool value, ValueChanged<bool> onChanged) => ShadCard(
      onTap: () => onChanged(!value),
      padding: EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: LT.label),
            SizedBox(height: 4),
            Text(sub, style: LT.small),
          ]),
        ),
      ]),
    );

/// The Me screen's list of adults linked from their own phones.
class LinkedAdultsSection extends StatelessWidget {
  const LinkedAdultsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.links == null) return SizedBox.shrink();
    return FutureBuilder<List<FamilyLink>>(
      future: s.links!.links(),
      builder: (context, snap) {
        final links = snap.data ?? <FamilyLink>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow('Linked, on their own phones'),
          if (links.isEmpty)
            Note('Nobody yet. Invite an adult from "Add a family member", or join someone else\'s family below.', icon: LucideIcons.link, margin: EdgeInsets.fromLTRB(16, 0, 16, 10)),
          for (final l in links)
            ShadCard(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LinkedAdultScreen(link: l)));
                if (context.mounted) AppScope.changed(context);
              },
              child: Row(children: [
                IconTile(LucideIcons.link),
                SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text(theirLine(l), style: LT.small),
                  ]),
                ),
                Icon(LucideIcons.chevronRight, color: LT.inactive),
              ]),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: SlabButton('Join a family', variant: ButtonVariant.outline, icon: LucideIcons.scanLine, onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JoinFamilyScreen()));
              if (context.mounted) AppScope.changed(context);
            }),
          ),
        ]);
      },
    );
  }

  static String theirLine(FamilyLink l) {
    final what = [if (l.theirEmergency != null) 'Emergency ID', if (l.theirMedicines != null) 'medicines'];
    return what.isEmpty ? 'Shares nothing with you' : 'Shares ${what.join(' and ')} with you';
  }
}

/// What a linked adult shares with you, and what you share with them.
class LinkedAdultScreen extends StatefulWidget {
  const LinkedAdultScreen({super.key, required this.link});
  final FamilyLink link;
  @override
  State<LinkedAdultScreen> createState() => _LinkedAdultScreenState();
}

class _LinkedAdultScreenState extends State<LinkedAdultScreen> {
  late FamilyLink _l = widget.link;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(plainError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final em = _l.theirEmergency;
    final meds = _l.theirMedicines;
    String f(String k) => (em?[k] as String?) ?? '';
    return Scaffold(
      appBar: GlassAppBar(),
      extendBodyBehindAppBar: true,
      body: ListView(children: [
        Masthead(
          eyebrow: 'Linked family',
          title: _l.name,
          description: _l.theirUpdateAt == null ? 'Nothing received from their phone yet.' : 'As last sent from their phone, ${dateTime(_l.theirUpdateAt!)}.',
        ),
        if (_l.safetyCode case final code?)
          Note("Safety code $code — the same code shows on ${_l.name.split(' ').first}'s phone. If it does not, unlink: someone else took the invite.",
              icon: LucideIcons.shieldCheck, margin: EdgeInsets.fromLTRB(16, 0, 16, 10))
        else
          Note('This link was made by an older version of LifeTrack and can no longer send or receive. Unlink, then link again.',
              icon: LucideIcons.triangleAlert, margin: EdgeInsets.fromLTRB(16, 0, 16, 10)),
        Eyebrow('What they share with you'),
        if (em == null && meds == null) Note('Nothing. That is their choice.', icon: LucideIcons.eyeOff, margin: EdgeInsets.fromLTRB(16, 0, 16, 10)),
        if (em != null)
          ShadCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Emergency ID', style: LT.small),
              SizedBox(height: 6),
              for (final (k, label) in const [('blood', 'Blood group'), ('allergies', 'Allergies'), ('conditions', 'Conditions'), ('meds', 'Medicines'), ('contactName', 'Emergency contact')])
                if (f(k).isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text('$label: ${f(k)}${k == 'contactName' && f('contactPhone').isNotEmpty ? ' · ${f('contactPhone')}' : ''}', style: LT.label),
                  ),
            ]),
          ),
        if (meds != null)
          ShadCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current medicines', style: LT.small),
              SizedBox(height: 6),
              if (meds.isEmpty) Text('None right now.', style: LT.label),
              for (final m in meds.cast<Map>()) Text('${m['title']}${m['dose'] == null ? '' : ' · ${m['dose']}'}', style: LT.label),
            ]),
          ),
        Eyebrow('What you share with ${_l.name.split(' ').first}'),
        _tick('My Emergency ID', 'Blood group, allergies, emergency contact', _l.iShareEmergency,
            (v) => _busy ? null : _run(() async => _l = await s.changeFamilySharing(_l, emergency: v, medicines: _l.iShareMedicines))),
        _tick('My current medicines', 'Names and doses of what I am taking now', _l.iShareMedicines,
            (v) => _busy ? null : _run(() async => _l = await s.changeFamilySharing(_l, emergency: _l.iShareEmergency, medicines: v))),
        Note('Your reports, prescriptions and history are never shared by linking.', icon: LucideIcons.shieldCheck),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: SlabButton('Unlink', variant: ButtonVariant.outline, icon: LucideIcons.unlink, onPressed: _busy
              ? null
              : () => _run(() async {
                    await s.unlinkFamily(_l);
                    if (context.mounted) Navigator.of(context).pop();
                  })),
        ),
      ]),
    );
  }
}
