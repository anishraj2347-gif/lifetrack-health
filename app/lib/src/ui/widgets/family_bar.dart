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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            children: [
              for (final p in family)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
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
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.id == current ? LT.accent : LT.raised,
                              shape: BoxShape.circle,
                              border: p.id == current ? Border.all(color: LT.ink, width: 1.5) : null,
                            ),
                            child: Text(
                              initials(p.name),
                              style: const TextStyle(fontWeight: FontWeight.w600, color: LT.ink),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Initials collide within a family (Aarav and Anjali
                          // Sharma are both "AS"); the first name does not.
                          SizedBox(
                            width: 56,
                            child: Text(
                              p.id == s.selfPatientId ? 'You' : p.name.split(' ').first,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontWeight: p.id == current ? FontWeight.w600 : FontWeight.w400, color: LT.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Semantics(
                label: 'Family overview',
                button: true,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: RoundButton(
                      LucideIcons.users,
                      dark: false,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyOverviewScreen()));
                        if (context.mounted) AppScope.changed(context);
                      },
                    ),
                  ),
                ),
              ),
              Semantics(
                label: 'Add a family member',
                button: true,
                excludeSemantics: true,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RoundButton(
                    LucideIcons.plus,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddFamilyScreen()));
                      if (context.mounted) AppScope.changed(context);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (c != null && c.kind != CustodyKind.self)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(color: LT.primary, borderRadius: BorderRadius.circular(LT.radius)),
            child: Row(
              children: [
                const Icon(LucideIcons.users, size: 16, color: LT.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(authorityLine(c), style: const TextStyle(color: LT.onDark, fontSize: 12.5, height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String authorityLine(Custody c) => switch (c.kind) {
    CustodyKind.childOfParent => c.isVerified
        ? 'Your ${FamilyRole.describe(c.relation)}\'s records · you are the parent (birth certificate, DigiLocker)'
        : 'Your ${FamilyRole.describe(c.relation)}\'s records · you are the parent (declared, not yet verified)',
    CustodyKind.delegatedByAdult => 'Your ${FamilyRole.describe(c.relation)}\'s records · they asked you to manage (agreed in person)',
    CustodyKind.self => '',
  };
}
