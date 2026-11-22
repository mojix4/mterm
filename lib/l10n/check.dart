// Consistency checks for the string tables, shared by test/l10n_test.dart and
// tool/check_l10n.dart. Pure Dart.
import '../builtin_commands.dart';
import 'strings.dart';

final _placeholder = RegExp(r'\{(\w+)\}');

/// Returns a list of human-readable problems; empty means all good.
List<String> l10nProblems() {
  final out = <String>[];
  final en = allStrings['en']!;
  for (final code in languageCodes) {
    final m = allStrings[code];
    if (m == null) {
      out.add('$code: no string table');
      continue;
    }
    for (final k in en.keys) {
      if (!m.containsKey(k)) out.add('$code: missing key "$k"');
    }
    for (final k in m.keys) {
      if (!en.containsKey(k)) out.add('$code: extra key "$k" (not in en)');
    }
    for (final e in m.entries) {
      if (e.value.trim().isEmpty) out.add('$code: empty value for "${e.key}"');
      final want = _placeholder.allMatches(en[e.key] ?? '').map((x) => x[1]).toSet();
      final got = _placeholder.allMatches(e.value).map((x) => x[1]).toSet();
      if (want.length != got.length || !want.containsAll(got)) {
        out.add('$code: "${e.key}" placeholders $got, en has $want');
      }
    }
    if (!languageNames.containsKey(code)) out.add('$code: no native language name');
    // built-in command library
    final cats = builtinCategoryNames[code];
    for (final c in builtinCategories) {
      if (cats?[c] == null) out.add('$code: missing builtin category "$c"');
    }
    final texts = builtinText[code];
    for (final c in builtinCommands) {
      final t = texts?[c.id];
      if (t == null || t.length != 2 || t.any((x) => x.trim().isEmpty)) {
        out.add('$code: missing builtin title/description for "${c.id}"');
      }
    }
    if (texts != null) {
      for (final id in texts.keys) {
        if (!builtinCommands.any((c) => c.id == id)) out.add('$code: builtin text for unknown id "$id"');
      }
    }
  }
  return out;
}

/// Keys looked up in [source] (via S's index operator or f()) that are not in en.
List<String> unknownKeysIn(String source) {
  final en = allStrings['en']!;
  final used = <String>{
    for (final m in RegExp(r"""\b[sl]\['([A-Za-z0-9_]+)'\]""").allMatches(source)) m[1]!,
    for (final m in RegExp(r"""\.f\('([A-Za-z0-9_]+)'""").allMatches(source)) m[1]!,
  };
  return [
    for (final k in used)
      if (!en.containsKey(k)) k
  ];
}
