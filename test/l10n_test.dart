// Localization tables: same keys in every language, built-ins translated,
// commands kept verbatim and every key used in the code defined.
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/builtin_commands.dart';
import 'package:mterm/l10n.dart';
import 'package:mterm/l10n/check.dart';

void main() {
  test('every language has the same keys and placeholders as English', () {
    expect(l10nProblems(), isEmpty);
  });

  test('every key used in lib/ exists', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      bad.addAll(unknownKeysIn(f.readAsStringSync()).map((k) => '${f.path}: $k'));
    }
    expect(bad, isEmpty);
  });

  test('language resolution falls back to English', () {
    expect(resolveLanguage('system', const [Locale('ja'), Locale('de')]), 'de');
    expect(resolveLanguage('system', const [Locale('ja')]), 'en');
    expect(resolveLanguage('system', const []), 'en');
    expect(resolveLanguage('zh', const [Locale('fa')]), 'zh');
    expect(S.forCode('fa').isRtl, isTrue);
    expect(S.forCode('ar').isRtl, isTrue);
    expect(S.forCode('ru').isRtl, isFalse);
    expect(S.forCode('xx').code, 'en');
    expect(S.forCode('fa').num(1500), '۱۵۰۰');
    expect(S.forCode('fa').f('nLines', {'n': 5}), '5 خط');
  });

  test('built-in commands are exactly the published ones', () {
    final cmds = {for (final c in builtinCommands) c.id: c.cmd};
    expect(cmds['xui'], r'bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)');
    expect(cmds['marzbanMysql'],
        r'sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install --database mysql');
    expect(
        cmds['kariz'], r'bash <(curl -fsSL https://raw.githubusercontent.com/Erfan-XRay/Kariz/main/scripts/kariz.sh)');
    expect(cmds['backpack'], r'bash <(curl -fsSL https://raw.githubusercontent.com/AminMGMT/BackPack/main/install.sh)');
    expect(builtinCommands, hasLength(16));
    // installers (panels, tunnels) and reboot ask first
    for (final c in builtinCommands) {
      expect(c.confirm, c.category != 'server' || c.id == 'reboot', reason: c.id);
    }
  });
}
