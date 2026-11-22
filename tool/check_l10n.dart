// Verifies that every language has exactly the English keys (and placeholders),
// that the built-in command library is translated, and that every key used in
// lib/ exists. Run: dart run tool/check_l10n.dart
import 'dart:io';

import 'package:mterm/l10n/check.dart';
import 'package:mterm/l10n/en.dart';
import 'package:mterm/l10n/strings.dart';

void main() {
  final problems = l10nProblems();
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final k in unknownKeysIn(f.readAsStringSync())) {
      problems.add('${f.path}: uses unknown key "$k"');
    }
  }
  if (problems.isEmpty) {
    stdout.writeln('l10n OK: ${en.length} keys x ${languageCodes.length} languages');
    return;
  }
  problems.forEach(stderr.writeln);
  exit(1);
}
