import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../model/vital_reading.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/parts.dart';

/// The home BP & sugar diary for the profile on screen. Plots what was
/// measured; draws no target bands and calls nothing high or low — that is
/// for the doctor (CLAUDE.md #8).
class VitalsScreen extends StatefulWidget {
  const VitalsScreen({super.key});
  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  VitalKind _kind = VitalKind.bloodPressure;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.currentPatient!;
    final all = [for (final v in s.vitalsOf(p.id)) if (v.kind == _kind) v];
    final since = s.clock().subtract(Duration(days: 30));
    final recent = [for (final v in all) if (!v.at.isBefore(since)) v].reversed.toList();
    return Scaffold(
      appBar: AppBar(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: LT.primary,
        foregroundColor: LT.onDark,
        onPressed: () => _add(context),
        icon: Icon(LucideIcons.plus),
        label: Text('Add a reading'),
      ),
      body: ListView(children: [
        Masthead(eyebrow: 'Home readings', title: p.name, description: 'Blood pressure and sugar you measure at home'),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 8, children: [
            Chip2('Blood pressure', selected: _kind == VitalKind.bloodPressure, onTap: () => setState(() => _kind = VitalKind.bloodPressure)),
            Chip2('Sugar', selected: _kind == VitalKind.glucose, onTap: () => setState(() => _kind = VitalKind.glucose)),
          ]),
        ),
        if (recent.length >= 2)
          ShadCard(
            margin: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Last 30 days · ${recent.length} readings', style: LT.small),
              SizedBox(height: 10),
              SizedBox(height: 180, child: CustomPaint(painter: _Chart(recent, _kind), size: Size.infinite)),
              if (_kind == VitalKind.bloodPressure) ...[
                SizedBox(height: 8),
                Row(children: [_Key(LT.ink, 'Top number'), SizedBox(width: 16), _Key(LT.ink3, 'Bottom number')]),
              ],
            ]),
          ),
        Note('Only on this phone. A doctor sees these only if you tick "Home BP & sugar readings" when you share; a backup has them only if you include personal data.', icon: LucideIcons.smartphone),
        SizedBox(height: 12),
        if (all.isEmpty) Note('No readings yet. Tap "Add a reading".', icon: LucideIcons.activity, margin: EdgeInsets.fromLTRB(16, 8, 16, 0)),
        for (final v in all)
          ShadCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.display, style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(dateTime(v.at), style: LT.small),
                ]),
              ),
              IconButton(
                tooltip: 'Delete reading',
                icon: Icon(LucideIcons.trash2, size: 18, color: LT.ink3),
                onPressed: () async {
                  await s.deleteVital(v);
                  if (context.mounted) setState(() {});
                },
              ),
            ]),
          ),
        SizedBox(height: 96),
      ]),
    );
  }

  Future<void> _add(BuildContext context) async {
    final s = AppScope.of(context);
    final a = TextEditingController(), b = TextEditingController(), c = TextEditingController();
    var ctx = GlucoseContext.fasting;
    var at = s.clock();
    String? error;
    final bp = _kind == VitalKind.bloodPressure;
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheet).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(bp ? 'Blood pressure' : 'Sugar', style: LT.title.copyWith(fontSize: 20)),
            SizedBox(height: 12),
            if (bp)
              Row(children: [
                Expanded(child: TextField(controller: a, keyboardType: TextInputType.number, inputFormatters: digits, decoration: InputDecoration(labelText: 'Top (mmHg)'))),
                SizedBox(width: 10),
                Expanded(child: TextField(controller: b, keyboardType: TextInputType.number, inputFormatters: digits, decoration: InputDecoration(labelText: 'Bottom (mmHg)'))),
                SizedBox(width: 10),
                Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, inputFormatters: digits, decoration: InputDecoration(labelText: 'Pulse'))),
              ])
            else ...[
              TextField(controller: a, keyboardType: TextInputType.numberWithOptions(decimal: true), inputFormatters: digits, decoration: InputDecoration(labelText: 'Sugar (mg/dL)')),
              SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final g in GlucoseContext.values) Chip2(g.label, selected: ctx == g, onTap: () => set(() => ctx = g)),
              ]),
            ],
            SizedBox(height: 10),
            FieldButton(
              text: dateTime(at),
              placeholder: false,
              onTap: () async {
                final d = await showDatePicker(context: sheet, initialDate: at, firstDate: DateTime(2000), lastDate: s.clock());
                if (d == null || !sheet.mounted) return;
                final t = await showTimePicker(context: sheet, initialTime: TimeOfDay.fromDateTime(at));
                set(() => at = DateTime(d.year, d.month, d.day, t?.hour ?? at.hour, t?.minute ?? at.minute));
              },
            ),
            if (error != null) Padding(padding: EdgeInsets.only(top: 8), child: Text(error!, style: LT.small.copyWith(color: LT.signal))),
            SizedBox(height: 16),
            SlabButton('Save reading', icon: LucideIcons.check, onPressed: () async {
              final sys = bp ? int.tryParse(a.text) : null, dia = bp ? int.tryParse(b.text) : null, pulse = bp ? int.tryParse(c.text) : null;
              final glu = bp ? null : double.tryParse(a.text);
              if (bp ? (sys == null || dia == null) : glu == null) {
                set(() => error = bp ? 'Enter the top and bottom numbers.' : 'Enter the sugar value.');
                return;
              }
              final problem = VitalReading.check(systolic: sys, diastolic: dia, pulse: pulse, glucose: glu);
              if (problem != null) {
                set(() => error = problem);
                return;
              }
              final r = Random.secure();
              await s.addVital(VitalReading(
                id: 'v-${List.generate(6, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
                patientId: s.currentPatientId!,
                at: at,
                kind: _kind,
                systolic: sys,
                diastolic: dia,
                pulse: pulse,
                glucose: glu,
                context: bp ? null : ctx,
              ));
              if (!sheet.mounted) return;
              celebrate(sheet, 'Reading saved');
              Navigator.of(sheet).pop();
            }),
          ]),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [Container(width: 14, height: 3, color: color), SizedBox(width: 6), Text(label, style: LT.small)]);
}

/// Lines through the readings, oldest left. Axis labels only — no bands,
/// no colours that mean good or bad.
class _Chart extends CustomPainter {
  _Chart(this.points, this.kind);
  final List<VitalReading> points;
  final VitalKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final series = kind == VitalKind.bloodPressure
        ? [
            (LT.ink, [for (final p in points) p.systolic!.toDouble()]),
            (LT.ink3, [for (final p in points) p.diastolic!.toDouble()]),
          ]
        : [
            (LT.ink, [for (final p in points) p.glucose!]),
          ];
    final all = [for (final (_, s) in series) ...s];
    final lo = all.reduce(min) - 5, hi = all.reduce(max) + 5;
    const left = 36.0;
    final w = size.width - left, h = size.height - 18;
    final t0 = points.first.at.millisecondsSinceEpoch.toDouble(), t1 = max(points.last.at.millisecondsSinceEpoch.toDouble(), t0 + 1);
    double x(VitalReading p) => left + (p.at.millisecondsSinceEpoch - t0) / (t1 - t0) * w;
    double y(double v) => h - (v - lo) / (hi - lo) * h;

    final grid = Paint()..color = LT.rule;
    final label = TextPainter(textDirection: TextDirection.ltr);
    for (final v in [lo + 5, (lo + hi) / 2, hi - 5]) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width, y(v)), grid);
      label
        ..text = TextSpan(text: v.round().toString(), style: TextStyle(fontFamily: LT.body, fontSize: 10, color: LT.ink3))
        ..layout();
      label.paint(canvas, Offset(0, y(v) - 6));
    }
    for (final (color, values) in series) {
      final line = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final o = Offset(x(points[i]), y(values[i]));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        canvas.drawCircle(o, 3, Paint()..color = color);
      }
      canvas.drawPath(path, line);
    }
    label
      ..text = TextSpan(text: '${points.first.at.day}/${points.first.at.month}', style: TextStyle(fontFamily: LT.body, fontSize: 10, color: LT.ink3))
      ..layout();
    label.paint(canvas, Offset(left, h + 4));
    label
      ..text = TextSpan(text: '${points.last.at.day}/${points.last.at.month}', style: TextStyle(fontFamily: LT.body, fontSize: 10, color: LT.ink3))
      ..layout();
    label.paint(canvas, Offset(size.width - label.width, h + 4));
  }

  @override
  bool shouldRepaint(_Chart old) => old.points != points || old.kind != kind;
}

/// Entry on Records: latest reading of each kind.
class VitalsCard extends StatelessWidget {
  const VitalsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final id = s.currentPatientId;
    if (id == null) return SizedBox.shrink();
    final all = s.vitalsOf(id);
    final bp = all.where((v) => v.kind == VitalKind.bloodPressure).firstOrNull;
    final glu = all.where((v) => v.kind == VitalKind.glucose).firstOrNull;
    return ShadCard(
      margin: EdgeInsets.fromLTRB(16, 8, 16, 12),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VitalsScreen()));
        if (context.mounted) AppScope.changed(context);
      },
      child: Row(children: [
        IconTile(LucideIcons.heartPulse),
        SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Home BP & sugar', style: LT.label),
            SizedBox(height: 4),
            Text(
              all.isEmpty ? 'Keep a diary of what you measure at home' : [if (bp != null) 'BP ${bp.systolic}/${bp.diastolic}', if (glu != null) 'Sugar ${glu.display.split(' mg').first}'].join(' · '),
              style: LT.small,
            ),
          ]),
        ),
        Icon(LucideIcons.chevronRight, color: LT.inactive),
      ]),
    );
  }
}

/// Two small tiles side by side on Records: tests you already have, and the
/// home readings diary. Keeps the records themselves near the top.
class QuickTiles extends StatelessWidget {
  const QuickTiles({super.key, required this.testsCount, required this.onTests});
  final int testsCount;
  final VoidCallback? onTests;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final id = s.currentPatientId;
    final vitals = id == null ? <VitalReading>[] : s.vitalsOf(id);
    final bp = vitals.where((v) => v.kind == VitalKind.bloodPressure).firstOrNull;
    Widget tile(IconData icon, String title, String sub, VoidCallback? onTap) => Expanded(
          child: ShadCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.all(14),
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: LT.ink),
              SizedBox(height: 8),
              Text(title, style: LT.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              SizedBox(height: 2),
              Text(sub, style: LT.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(children: [
        if (onTests != null) ...[
          tile(LucideIcons.flaskConical, 'Tests you have', '$testsCount · show your doctor', onTests),
          SizedBox(width: 10),
        ],
        tile(LucideIcons.heartPulse, 'Home BP & sugar', bp != null ? 'Last ${bp.systolic}/${bp.diastolic}' : vitals.isEmpty ? 'Start a diary' : '${vitals.length} readings', () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VitalsScreen()));
          if (context.mounted) AppScope.changed(context);
        }),
      ]),
    );
  }
}
