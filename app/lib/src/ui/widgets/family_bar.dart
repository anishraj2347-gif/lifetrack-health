import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../family/family_role.dart';
import '../../model/custody.dart';
import '../app_scope.dart';
import '../screens/add_family_screen.dart';
import '../screens/family_overview_screen.dart';
import '../theme.dart';
import 'parts.dart';

/// Everyone whose records are on this phone, as avatars. Tap to switch; the
/// one you are viewing is lime. When it is not you, a banner says whose
/// records these are and on what authority.
class FamilyBar extends StatelessWidget {
  const FamilyBar({super.key});

  static String initials(String n) => n.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final family = s.familyOnPhone();
    final current = s.currentPatientId;
    final c = current == null ? null : s.custodyOf(current);
    // Tall enough for the circle and one line of name at the phone's text size.
    final barHeight = 14 + 48 + 4 + MediaQuery.textScalerOf(context).scale(12) * 1.5 + 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: barHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
            children: [
              for (final p in family)
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Semantics(
                    button: true,
                    selected: p.id == current,
                    label: p.id == s.selfPatientId ? 'You, ${p.name}' : p.name,
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () async {
                        await s.switchTo(p.id);
                        if (context.mounted) AppScope.changed(context);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.id == current ? LT.accent : LT.raised,
                              shape: BoxShape.circle,
                              border: p.id == current ? Border.all(color: LT.ink, width: 1.5) : null,
                            ),
                            child: Text(
                              initials(p.name),
                              style: TextStyle(fontWeight: FontWeight.w600, color: p.id == current ? LT.onAccent : LT.ink),
                            ),
                          ),
                          SizedBox(height: 4),
                          // Initials collide within a family (Aarav and Anjali
                          // Sharma are both "AS"); the first name does not.
                          SizedBox(
                            width: 56,
                            child: Text(
                              p.id == s.selfPatientId ? 'You' : p.name.split(' ').first,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, height: 1.3, fontWeight: p.id == current ? FontWeight.w600 : FontWeight.w400, color: LT.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              _action(
                context,
                label: 'Family',
                semantics: 'Family overview',
                icon: LucideIcons.users,
                filled: false,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FamilyOverviewScreen()));
                  if (context.mounted) AppScope.changed(context);
                },
              ),
              // Outlined, not black: the black button on this screen is
              // "Add record", and the two must not be confused.
              _action(
                context,
                label: 'Add person',
                semantics: 'Add a family member',
                icon: LucideIcons.userPlus,
                filled: false,
                outlined: true,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddFamilyScreen()));
                  if (context.mounted) AppScope.changed(context);
                },
              ),
            ],
          ),
        ),
        if (c != null && c.kind != CustodyKind.self)
          Container(
            margin: EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(color: LT.primary, borderRadius: BorderRadius.circular(LT.radius)),
            child: Row(
              children: [
                Icon(LucideIcons.users, size: 16, color: LT.onDark),
                SizedBox(width: 10),
                Expanded(
                  child: Text(authorityLine(c), style: TextStyle(color: LT.onDark, fontSize: 12, height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Widget _action(BuildContext context,
          {required String label, required String semantics, required IconData icon, required VoidCallback onTap, bool filled = true, bool outlined = false}) =>
      Padding(
        padding: EdgeInsets.only(right: 8),
        child: Semantics(
          label: semantics,
          button: true,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: outlined ? Colors.transparent : LT.raised,
                  shape: BoxShape.circle,
                  border: outlined ? Border.all(color: LT.ink3, width: 1.5) : null,
                ),
                child: Icon(icon, size: 19, color: LT.ink),
              ),
              SizedBox(height: 4),
              SizedBox(
                width: 76,
                child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.3, color: LT.ink2)),
              ),
            ]),
          ),
        ),
      );

  static String authorityLine(Custody c) => switch (c.kind) {
    CustodyKind.childOfParent => c.isVerified
        ? 'Your ${FamilyRole.describe(c.relation)}\'s records · you are the parent (birth certificate, DigiLocker)'
        : 'Your ${FamilyRole.describe(c.relation)}\'s records · you are the parent (declared, not yet verified)',
    CustodyKind.delegatedByAdult => 'Your ${FamilyRole.describe(c.relation)}\'s records · they asked you to manage (agreed in person)',
    CustodyKind.self => '',
  };
}

/// The name of the person whose records are open, for copy like "Share
/// Aarav's records" — or null when only one person is on this phone, where
/// "my" already says it.
String? viewingName(BuildContext context) {
  final s = AppScope.of(context);
  if (s.familyOnPhone().length < 2) return null;
  final p = s.currentPatient;
  if (p == null) return null;
  return p.id == s.selfPatientId ? 'You' : p.name;
}

/// "Aarav's" / "your": the possessive for [viewingName].
String whoseRecords(BuildContext context) {
  final n = viewingName(context);
  return n == null || n == 'You' ? 'your' : "${n.split(' ').first}'s";
}

/// On tabs without the [FamilyBar]: a slim line naming whose records the
/// screen acts on, so a caregiver who switched on Records cannot share the
/// wrong person's records from Share. Tap to switch. Hidden when only one
/// person is on this phone.
class ViewingPill extends StatelessWidget {
  const ViewingPill({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final name = viewingName(context);
    if (name == null) return SizedBox.shrink();
    final c = s.custodyOf(s.currentPatientId!);
    final role = c == null || c.kind == CustodyKind.self ? null : FamilyRole.describe(c.relation);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        button: true,
        label: 'Viewing ${name == 'You' ? 'your own' : "$name's"} records. Tap to switch person.',
        excludeSemantics: true,
        child: Material(
          color: LT.raised,
          shape: StadiumBorder(),
          child: InkWell(
            customBorder: StadiumBorder(),
            onTap: () => _switcher(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: LT.surface, shape: BoxShape.circle),
                    child: Text(FamilyBar.initials(s.currentPatient!.name), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: LT.ink)),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(style: TextStyle(fontFamily: LT.body, fontSize: 14, color: LT.ink2), children: [
                        TextSpan(text: 'Viewing '),
                        TextSpan(text: name == 'You' ? 'your own records' : name, style: TextStyle(fontWeight: FontWeight.w600, color: LT.ink)),
                        if (role != null) TextSpan(text: ' · $role'),
                      ]),
                    ),
                  ),
                  Text('Switch', style: TextStyle(fontFamily: LT.body, fontSize: 14, fontWeight: FontWeight.w600, color: LT.ink)),
                  Icon(LucideIcons.chevronDown, size: 18, color: LT.ink),
                  SizedBox(width: 6),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _switcher(BuildContext context) => showPersonSheet(context);

}

/// Whose records are open, and the family around them: switch person, see
/// the family overview, or add someone. Opened from the top bar.
Future<void> showPersonSheet(BuildContext context) async {
  final s = AppScope.of(context);
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
        child: ListView(shrinkWrap: true, padding: EdgeInsets.fromLTRB(0, 0, 0, 12), children: [
          Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Whose records?', style: LT.title.copyWith(fontSize: 20))),
          for (final p in s.familyOnPhone())
            ListTile(
              minTileHeight: 60,
              contentPadding: EdgeInsets.symmetric(horizontal: 20),
              leading: CircleAvatar(
                backgroundColor: p.id == s.currentPatientId ? LT.accent : LT.raised,
                child: Text(FamilyBar.initials(p.name), style: TextStyle(fontWeight: FontWeight.w600, color: p.id == s.currentPatientId ? LT.onAccent : LT.ink)),
              ),
              title: Text(p.id == s.selfPatientId ? '${p.name} (you)' : p.name, style: LT.label),
              subtitle: p.id == s.selfPatientId ? null : Builder(builder: (_) {
                final c = s.custodyOf(p.id);
                return c == null ? SizedBox.shrink() : Text(FamilyRole.describe(c.relation), style: LT.meta);
              }),
              trailing: p.id == s.currentPatientId ? Icon(LucideIcons.check, color: LT.ink) : null,
              selected: p.id == s.currentPatientId,
              onTap: () => Navigator.of(sheet).pop(p.id),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(child: SlabButton('Family', variant: ButtonVariant.outline, icon: LucideIcons.users, onPressed: () => Navigator.of(sheet).pop('#family'))),
              SizedBox(width: 8),
              Expanded(child: SlabButton('Add person', variant: ButtonVariant.outline, icon: LucideIcons.userPlus, onPressed: () => Navigator.of(sheet).pop('#add'))),
            ]),
          ),
        ]),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  if (picked == '#family' || picked == '#add') {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => picked == '#family' ? FamilyOverviewScreen() : AddFamilyScreen()));
    if (context.mounted) AppScope.changed(context);
    return;
  }
  if (picked == s.currentPatientId) return;
  await s.switchTo(picked);
  if (context.mounted) AppScope.changed(context);
}

/// The top bar's person button: avatar (lime — the one selected) and first
/// name, on every tab, so it is always plain whose records are open.
class PersonButton extends StatelessWidget {
  const PersonButton({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient;
    if (p == null) return SizedBox.shrink();
    final self = p.id == s.selfPatientId;
    final many = s.familyOnPhone().length > 1;
    final name = self ? 'You' : p.name.split(' ').first;
    return Semantics(
      button: true,
      label: self ? 'Viewing your own records. Switch person or add family.' : "Viewing ${p.name}'s records. Switch person.",
      excludeSemantics: true,
      child: Material(
        color: LT.raised.withValues(alpha: 0.7),
        shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: LT.dark ? 0.08 : 0.9))),
        child: InkWell(
          customBorder: StadiumBorder(),
          onTap: () => showPersonSheet(context),
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, 4, many ? 10 : 4, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: LT.accent, shape: BoxShape.circle),
                child: Text(FamilyBar.initials(p.name), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: LT.onAccent)),
              ),
              if (many) ...[
                SizedBox(width: 8),
                Flexible(
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: LT.body, fontSize: 14, fontWeight: FontWeight.w600, color: LT.ink)),
                ),
                SizedBox(width: 2),
                Icon(LucideIcons.chevronDown, size: 16, color: LT.ink),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Under the title on Reminders and Records when the records are not your
/// own: whose they are and on what authority ("declared" unless verified).
class AuthorityBanner extends StatelessWidget {
  const AuthorityBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final id = s.currentPatientId;
    final c = id == null ? null : s.custodyOf(id);
    if (c == null || c.kind == CustodyKind.self) return SizedBox.shrink();
    return Container(
      margin: EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: LT.primary, borderRadius: BorderRadius.circular(LT.radius)),
      child: Row(children: [
        Icon(LucideIcons.users, size: 16, color: LT.onDark),
        SizedBox(width: 10),
        Expanded(child: Text(FamilyBar.authorityLine(c), style: TextStyle(color: LT.onDark, fontSize: 14, height: 1.4))),
      ]),
    );
  }
}
