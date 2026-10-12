import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetrack/src/ui/theme.dart';

/// The accent ("selected / now") must never be mistaken for a health colour,
/// for any viewer. Machado 2009 (severity 1.0) on linear RGB, ΔE76 in CIELAB —
/// the method behind the numbers in theme.dart (it reproduces the recorded
/// lime–caution 38.9 under deuteranopia).
void main() {
  const minimum = 25.0;

  for (final dark in [false, true]) {
    test('${dark ? 'dark' : 'light'}: accent, signal, trace and caution stay apart under every colour vision', () {
      LT.dark = dark;
      addTearDown(() => LT.dark = false);
      final colours = {
        'accent': LT.accent,
        'signal': LT.signal,
        'signalFill': LT.signalFill,
        'trace': LT.trace,
        'caution': LT.caution,
      };
      final pairs = [('accent', 'signal'), ('accent', 'signalFill'), ('accent', 'trace'), ('accent', 'caution'), ('signal', 'trace'), ('signalFill', 'caution')];
      for (final (a, b) in pairs) {
        for (final MapEntry(key: vision, value: m) in _machado.entries) {
          final d = _deltaE(colours[a]!, colours[b]!, m);
          expect(d, greaterThanOrEqualTo(minimum), reason: '$a vs $b under $vision: ΔE ${d.toStringAsFixed(1)}');
        }
      }
    });
  }

  test('the method reproduces the recorded lime–caution figure', () {
    expect(_deltaE(const Color(0xFFEEF36A), const Color(0xFFFEF3C7), _machado['deutan']!), closeTo(38.9, 0.1));
  });
}

const _machado = {
  'normal': [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ],
  'protan': [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
  'deutan': [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
  ],
  'tritan': [
    [1.255528, -0.076749, -0.178779],
    [-0.078411, 0.930809, 0.147602],
    [0.004733, 0.691367, 0.303900],
  ],
};

double _lin(double c) => c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();

List<double> _lab(List<double> rgb) {
  final [r, g, b] = rgb;
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) => t > 0.008856 ? pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

List<double> _simulate(Color c, List<List<double>> m) {
  final v = [_lin(c.r), _lin(c.g), _lin(c.b)];
  return [for (final row in m) (row[0] * v[0] + row[1] * v[1] + row[2] * v[2]).clamp(0.0, 1.0)];
}

double _deltaE(Color a, Color b, List<List<double>> m) {
  final la = _lab(_simulate(a, m)), lb = _lab(_simulate(b, m));
  return sqrt(pow(la[0] - lb[0], 2) + pow(la[1] - lb[1], 2) + pow(la[2] - lb[2], 2));
}
