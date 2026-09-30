import 'hi.dart';

/// The languages LifeTrack speaks. English is the source; every other
/// language is a table keyed by the English sentence, so a missing entry
/// falls back to English instead of showing a key.
enum AppLang {
  en('English'),
  hi('हिन्दी');

  const AppLang(this.label);
  final String label;
}

abstract final class L10n {
  /// Set by the app root before it builds; the root is keyed on it, so a
  /// change rebuilds every screen.
  static AppLang current = AppLang.en;

  static const tables = {AppLang.hi: hi};
}

/// Translates [en] into the current language. Placeholders are `{0}`,
/// `{1}`… filled from [args], so a translation may reorder them.
String t(String en, [List<Object?> args = const []]) {
  var s = L10n.tables[L10n.current]?[en] ?? en;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Singular or plural English source, then translated.
String tn(int n, String one, String many) => t(n == 1 ? one : many, [n]);
