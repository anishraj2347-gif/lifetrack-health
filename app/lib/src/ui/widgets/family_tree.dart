import 'dart:math';

import 'package:flutter/material.dart';

import '../../family/family_role.dart';
import '../../model/patient.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'person_avatar.dart';

/// Everyone on this phone drawn as a family tree around the head of family:
/// a row per generation, couples joined, lines down to their children. Roles
/// say who each person is *to the head* (CLAUDE.md #14a), so the tree is
/// built from them: the head's parents above the head and their brothers and
/// sisters, the spouse's parents above the spouse, the couple's children
/// below. Relatives the roles cannot place (an uncle, a cousin) sit in their
/// generation's row without a line. Tap a person to open their records.
class FamilyTree extends StatelessWidget {
  const FamilyTree({super.key, required this.head, required this.others, required this.roleOf});
  final Patient head;
  final List<Patient> others;
  final FamilyRole Function(Patient) roleOf;

  static const _slot = 92.0;
  static const _avatar = 54.0;
  static const _rowHeight = 122.0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final layout = _Layout.of(head, others, roleOf);
    final rows = layout.rows;
    final width = layout.width;
    final height = rows.length * _rowHeight - 18;

    double yOf(int gen) => rows.indexOf(gen) * _rowHeight;
    Offset centre(String id) => Offset(layout.x[id]! + _slot / 2, yOf(layout.gen[id]!) + _avatar / 2);

    final tree = SizedBox(
      width: width,
      height: height,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _Lines(layout: layout, centre: centre, colour: LT.inactive))),
        for (final p in [head, ...others])
          Positioned(
            left: layout.x[p.id],
            top: yOf(layout.gen[p.id]!),
            width: _slot,
            child: _Node(
              patient: p,
              label: p.id == head.id ? 'You · head' : roleOf(p).label,
              viewing: s.currentPatientId == p.id,
              onTap: () async {
                await s.switchTo(p.id);
                if (!context.mounted) return;
                AppScope.changed(context);
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
      ]),
    );
    return LayoutBuilder(
      builder: (context, box) => width <= box.maxWidth
          ? Center(child: tree)
          // Wider than the phone: scroll sideways, starting at the head.
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: ScrollController(initialScrollOffset: max(0, layout.x[head.id]! + _slot / 2 - box.maxWidth / 2)),
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: tree,
            ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.patient, required this.label, required this.viewing, required this.onTap});
  final Patient patient;
  final String label;
  final bool viewing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${patient.name}, $label${viewing ? ', open now' : ''}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PersonAvatar(patientId: patient.id, name: patient.name, size: FamilyTree._avatar, selected: viewing),
              SizedBox(height: 6),
              Text(patient.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: LT.body, fontSize: 13, fontWeight: FontWeight.w600, color: LT.ink)),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontFamily: LT.body, fontSize: 11, height: 1.25, color: LT.ink3)),
            ]),
          ),
        ),
      );
}

/// Where each person goes, and which groups are joined by lines.
class _Layout {
  _Layout(this.x, this.gen, this.rows, this.width, this.couples, this.families);
  final Map<String, double> x;
  final Map<String, int> gen;
  final List<int> rows;
  final double width;

  /// Pairs drawn with a line between them.
  final List<(String, String)> couples;

  /// Parents (one or two) and the children a line runs down to.
  final List<(List<String>, List<String>)> families;

  static _Layout of(Patient head, List<Patient> others, FamilyRole Function(Patient) roleOf) {
    const slot = FamilyTree._slot;
    List<String> withRole(Set<FamilyRole> rs) => [for (final p in others) if (rs.contains(roleOf(p))) p.id];
    final grandparents = withRole({FamilyRole.grandfather, FamilyRole.grandmother});
    final parents = withRole({FamilyRole.father, FamilyRole.mother});
    final inLawParents = withRole({FamilyRole.fatherInLaw, FamilyRole.motherInLaw});
    final siblings = withRole({FamilyRole.brother, FamilyRole.sister});
    final spouse = withRole({FamilyRole.wife, FamilyRole.husband, FamilyRole.spouse}).take(1).toList();
    final spouseSiblings = withRole({FamilyRole.brotherInLaw, FamilyRole.sisterInLaw});
    final children = withRole({FamilyRole.son, FamilyRole.daughter});
    final childrenInLaw = withRole({FamilyRole.sonInLaw, FamilyRole.daughterInLaw});
    final grandchildren = withRole({FamilyRole.grandson, FamilyRole.granddaughter});
    final placed = {...grandparents, ...parents, ...inLawParents, ...siblings, ...spouse, ...spouseSiblings, ...children, ...childrenInLaw, ...grandchildren};
    final loose = [for (final p in others) if (!placed.contains(p.id)) p];

    final x = <String, double>{};
    final gen = <String, int>{head.id: 0};
    for (final p in others) {
      gen[p.id] = roleOf(p).generation;
    }

    // Generation 0 left to right: brothers and sisters, the head, the
    // spouse, the spouse's brothers and sisters, then anyone unplaced.
    final row0 = [...siblings, head.id, ...spouse, ...spouseSiblings, ...[for (final p in loose) if (roleOf(p).generation == 0) p.id]];
    for (final (i, id) in row0.indexed) {
      x[id] = i * slot;
    }
    double mid(List<String> ids) => ids.map((i) => x[i]!).reduce((a, b) => a + b) / ids.length;

    // A group centred over a point, pushed right past anything already in its row.
    void centre(List<String> ids, double c, int g) {
      if (ids.isEmpty) return;
      var left = c - (ids.length - 1) * slot / 2;
      final taken = [for (final e in x.entries) if (gen[e.key] == g && !ids.contains(e.key)) e.value];
      if (taken.isNotEmpty) left = max(left, taken.reduce(max) + slot);
      for (final (i, id) in ids.indexed) {
        x[id] = left + i * slot;
      }
    }

    final headSide = [...siblings, head.id];
    centre(parents, mid(headSide), -1);
    if (spouse.isNotEmpty) centre(inLawParents, mid([...spouse, ...spouseSiblings]), -1);
    centre(grandparents, parents.isNotEmpty ? mid(parents) : mid(headSide), -2);
    final couple = [head.id, ...spouse];
    centre(children, mid(couple), 1);
    centre(childrenInLaw, children.isNotEmpty ? mid(children) + slot : mid(couple), 1);
    centre(grandchildren, children.isNotEmpty ? mid(children) : mid(couple), 2);
    for (final p in loose.where((p) => roleOf(p).generation != 0)) {
      final g = roleOf(p).generation;
      final inRow = [for (final e in x.entries) if (gen[e.key] == g) e.value];
      x[p.id] = inRow.isEmpty ? mid(headSide) : inRow.reduce(max) + slot;
    }

    final minX = x.values.reduce(min);
    x.updateAll((_, v) => v - minX);
    final rows = {for (final g in gen.values) g}.toList()..sort();

    List<(String, String)> pairs(List<String> ids) => ids.length >= 2 ? [(ids[0], ids[1])] : const [];
    return _Layout(
      x,
      gen,
      rows,
      x.values.reduce(max) + slot,
      [...pairs(grandparents), ...pairs(parents), ...pairs(inLawParents), ...pairs(couple)],
      [
        if (grandparents.isNotEmpty && (parents.isNotEmpty || headSide.isNotEmpty)) (grandparents, parents.isNotEmpty ? parents.take(1).toList() : headSide),
        if (parents.isNotEmpty) (parents, headSide),
        if (inLawParents.isNotEmpty && spouse.isNotEmpty) (inLawParents, [...spouse, ...spouseSiblings]),
        if (children.isNotEmpty) (couple, children),
        if (grandchildren.isNotEmpty && children.isNotEmpty) (children, grandchildren),
      ],
    );
  }
}

class _Lines extends CustomPainter {
  _Lines({required this.layout, required this.centre, required this.colour});
  final _Layout layout;
  final Offset Function(String id) centre;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = colour
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const r = FamilyTree._avatar / 2;
    for (final (a, b) in layout.couples) {
      final (pa, pb) = (centre(a), centre(b));
      final (l, rt) = pa.dx < pb.dx ? (pa, pb) : (pb, pa);
      canvas.drawLine(Offset(l.dx + r + 3, l.dy), Offset(rt.dx - r - 3, rt.dy), pen);
    }
    for (final (parents, kids) in layout.families) {
      final ps = [for (final p in parents) centre(p)];
      // From the middle of the couple's line, or below a single parent.
      // A single parent's line starts below their name and role, not through them.
      final from = ps.length >= 2 ? Offset((ps[0].dx + ps[1].dx) / 2, ps[0].dy) : Offset(ps[0].dx, ps[0].dy + r + 44);
      final cs = [for (final k in kids) centre(k)];
      final top = cs.first.dy - r - 4;
      final bar = top - 14;
      canvas.drawLine(from, Offset(from.dx, bar), pen);
      final xs = [from.dx, ...cs.map((c) => c.dx)];
      canvas.drawLine(Offset(xs.reduce(min), bar), Offset(xs.reduce(max), bar), pen);
      for (final c in cs) {
        canvas.drawLine(Offset(c.dx, bar), Offset(c.dx, top), pen);
      }
    }
  }

  @override
  bool shouldRepaint(_Lines old) => old.layout != layout || old.colour != colour;
}
