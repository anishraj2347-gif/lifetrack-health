import 'package:flutter/material.dart';

import 'app_version.dart';
import 'patients.dart' show pagePadding;
import 'sample_data.dart';
import 'session.dart';
import 'theme.dart';

/// The doctor's own page, like Me in the patient app: who they are as the
/// registry approved them, their practice details, privacy, appearance and
/// this device.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.session, required this.onChanged});
  final DoctorSession session;
  final VoidCallback onChanged;
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  DoctorSession get s => widget.session;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _editPractice() async {
    final c = {for (final k in DoctorSession.practiceFields.keys) k: TextEditingController(text: s.profile[k] ?? '')};
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Practice details', style: DT.h1),
            SizedBox(height: 4),
            Text('Printed on your paper prescriptions. The qualification also fills in each new prescription.', style: DT.muted),
            SizedBox(height: 16),
            Field('Qualification', c['qualification']!, hint: 'MBBS, MD (Medicine)'),
            Field('Clinic or hospital', c['clinic']!, hint: 'Menon Family Clinic'),
            Field('Clinic address', c['address']!, hint: '12 MG Road, New Delhi', maxLines: 2),
            Field('Clinic phone', c['phone']!, hint: '011 2345 6789'),
            SizedBox(height: 4),
            Pill('Save', onTap: () => Navigator.of(sheet).pop(true)),
          ]),
        ),
      ),
    );
    if (saved != true) return;
    try {
      await s.savePractice({for (final e in c.entries) e.key: e.value.text});
      if (!mounted) return;
      setState(() {});
      _say('Practice details saved.');
    } on ArgumentError catch (e) {
      if (mounted) _say('${e.message}');
    }
  }

  Future<void> _startOver() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Start over on this device?'),
        content: Text('Deletes this device\'s keys, your patient register, prescriptions and notes from this phone. You will need to enrol and be approved again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: Text('Delete and start over', style: TextStyle(color: DT.signal))),
        ],
      ),
    );
    if (sure != true) return;
    await s.forget();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = s.profile;
    final expires = s.certificateExpires;
    final practice = [for (final k in DoctorSession.practiceFields.keys) if ((p[k] ?? '').isNotEmpty) (DoctorSession.practiceFields[k]!, p[k]!)];
    return ListView(
      padding: pagePadding(context),
      children: [
        Text('Profile', style: DT.h1),
        SizedBox(height: 12),
        Card0(
          dark: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: DT.accent,
                child: Text(_initials(p['name'] ?? ''), style: TextStyle(color: DT.onAccent, fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name'] ?? '', style: TextStyle(color: DT.onDark, fontSize: 20, fontWeight: FontWeight.w600)),
                  Text([if ((p['qualification'] ?? '').isNotEmpty) p['qualification']!, p['speciality'] ?? ''].where((x) => x.isNotEmpty).join(' · '),
                      style: TextStyle(color: DT.onDarkMuted, fontSize: 13)),
                ]),
              ),
            ]),
            SizedBox(height: 14),
            _darkRow('Registration', s.registrationNo),
            _darkRow('Council', p['council'] ?? ''),
            _darkRow('Status', s.state == EnrolmentState.approved ? 'Verified by the LifeTrack registry' : 'Not approved'),
            if (expires != null) _darkRow('Certificate', 'Renews itself · current one until ${fmtDate(expires)}'),
          ]),
        ),
        Card0(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Practice details', style: DT.h2)),
              TextButton.icon(onPressed: _editPractice, icon: Icon(Icons.edit_outlined, size: 18), label: Text('Edit')),
            ]),
            if (practice.isEmpty)
              Text('Add your qualification, clinic, address and phone. They are printed on paper prescriptions.', style: DT.muted)
            else
              for (final (label, value) in practice) _row(label, value),
            SizedBox(height: 6),
            Text('Name, speciality, council and registration number come from your approved licence check and cannot be edited here.', style: DT.muted),
          ]),
        ),
        Card0(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Privacy', style: DT.h2),
            SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Hide from screenshots', style: DT.label),
              subtitle: Text('Screenshots, screen recordings and the Recent apps preview come out blank while LT Clinic is open. Patients\' records are on these screens.', style: DT.muted),
              value: s.screenPrivacy,
              onChanged: (v) async {
                await s.setScreenPrivacy(v);
                if (mounted) setState(() {});
              },
            ),
            Divider(color: DT.surface),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('App lock', style: DT.label),
              subtitle: Text('Always on for doctors: your fingerprint, face or phone PIN when LT Clinic opens, and again after a minute away.', style: DT.muted),
              trailing: Tag('On'),
            ),
          ]),
        ),
        Card0(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Appearance', style: DT.h2),
            SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, label) in const [('system', 'Follow device'), ('light', 'Light'), ('dark', 'Dark')])
                ChoiceChip(
                  label: Text(label),
                  selected: s.themeChoice == v,
                  onSelected: (_) async {
                    await s.setThemeChoice(v);
                    appearance.value = themeModeOf(v);
                    if (mounted) setState(() {});
                  },
                  selectedColor: DT.button,
                  labelStyle: TextStyle(color: s.themeChoice == v ? DT.onButton : DT.ink, fontWeight: FontWeight.w500),
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                ),
            ]),
          ]),
        ),
        Card0(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('This device', style: DT.h2),
            SizedBox(height: 6),
            if (s.keyFingerprint != null) _row('Device key', s.keyFingerprint!),
            _row('Patients', '${s.patients.length} in your register'),
            _row('Prescriptions', '${s.prescriptions.length} signed'),
            _row('Notes', '${s.notes.length} private notes'),
            SizedBox(height: 6),
            Text('Kept encrypted on this device. Shared records close when the patient ends access or the time runs out; your notes and prescriptions stay.', style: DT.muted),
          ]),
        ),
        if (demoTools)
          Card0(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Demo', style: DT.h2),
              SizedBox(height: 4),
              Text('Adds made-up patients, prescriptions and notes, each marked "(sample)". Adding again replaces them.', style: DT.muted),
              SizedBox(height: 10),
              Pill('Add sample patients', onTap: () async {
                await s.addSamplePatients(DateTime.now());
                widget.onChanged();
                if (mounted) {
                  setState(() {});
                  _say('Sample patients added. Open Patients to see them.');
                }
              }),
            ]),
          ),
        Card0(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('About', style: DT.h2),
            SizedBox(height: 6),
            _row('App', 'LT Clinic $doctorAppVersion${demoTools ? ' · demo build' : ''}'),
            SizedBox(height: 10),
            Pill('Start over on this device', dark: false, onTap: _startOver),
          ]),
        ),
        SizedBox(height: 20),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.replaceFirst(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    return parts.take(2).map((x) => x[0].toUpperCase()).join();
  }

  Widget _row(String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: DT.muted)),
          Expanded(child: Text(value, style: DT.body)),
        ]),
      );

  Widget _darkRow(String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: DT.onDarkMuted, fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(color: DT.onDark, fontSize: 13.5))),
        ]),
      );
}
