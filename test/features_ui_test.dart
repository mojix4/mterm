// UI flows for the Termius-style features that need no SSH server (run in CI):
// groups/tags/search, host form extras (jump host, startup command, forwarding
// rules, key generation), Files tab, Settings (backup, logs, clear history),
// terminal search, forwarding sheet, split view and desktop paste shortcut.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/keys.dart';
import 'package:mterm/l10n.dart';
import 'package:mterm/main.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/terminal_screen.dart';
import 'package:mterm/session.dart';
import 'package:mterm/session_log.dart';
import 'package:mterm/store.dart';
import 'package:xterm/xterm.dart';

import 'support.dart';

const phone = Size(390, 844);
final _vScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

Future<void> english() async {
  Store.i.settings.language = 'en';
  await Store.i.saveSettings();
}

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: _vScroll.last);
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
}

Future<void> openTerminal(WidgetTester t, TermSession s) async {
  navKey.currentState!.push(MaterialPageRoute(builder: (_) => TerminalScreen(session: s)));
  await t.pumpAndSettle();
}

Future<void> menu(WidgetTester t, String item) async {
  await t.tap(find.byIcon(Icons.more_vert).last);
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(installMocks);
  setUp(freshStore);

  testWidgets('hosts list: groups as sections, search by tag and group', (t) async {
    await setSize(t, phone);
    await english();
    await Store.i.upsertHost(Host(id: 'a', label: 'Alpha', host: '10.0.0.1', user: 'root', group: 'Work', tags: ['germany']),
        HostSecret());
    await Store.i.upsertHost(Host(id: 'b', label: 'Beta', host: '10.0.0.2', user: 'root'), HostSecret());
    await Store.i.upsertHost(Host(id: 'c', label: 'Gamma', host: '10.0.0.3', user: 'root', group: 'Arvan'), HostSecret());
    await launch(t);
    expect(find.byKey(const ValueKey('group-Work')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-Arvan')), findsOneWidget);
    expect(find.text('Other servers'), findsOneWidget);
    expect(find.text('germany'), findsOneWidget, reason: 'tag chip');
    // sections are sorted: Arvan above Work above ungrouped
    final y = (String k) => t.getTopLeft(find.byKey(ValueKey(k))).dy;
    expect(y('group-Arvan'), lessThan(y('group-Work')));

    await t.enterText(find.byType(TextField).first, 'germ');
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'arvan');
    await t.pumpAndSettle();
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'nothing-here');
    await t.pumpAndSettle();
    expect(find.text('No matching servers'), findsOneWidget);
  });

  testWidgets('host form: group, tags, startup command, jump host, forwarding rule, generated key', (t) async {
    await setSize(t, phone);
    await english();
    await Store.i.upsertHost(Host(id: 'j', label: 'Bastion', host: '10.9.9.9', user: 'root'), HostSecret());
    await launch(t);
    await t.tap(find.byKey(const ValueKey('fab-add-host')));
    await t.pumpAndSettle();
    await t.enterText(fieldLabeled('Server address'), '10.0.0.7');
    await t.tap(find.byIcon(Icons.key)); // SSH key auth
    await t.pumpAndSettle();
    await reveal(t, find.byKey(const ValueKey('generate-key')));
    await t.tap(find.byKey(const ValueKey('generate-key')));
    await t.pumpAndSettle();
    final pub = (t.widget(find.byKey(const ValueKey('public-key-text'))) as SelectableText).data!;
    expect(pub, startsWith('ssh-ed25519 '));
    await t.tap(find.text('Copy'));
    await t.pumpAndSettle();
    expect(clipboard, pub);

    await reveal(t, find.byKey(const ValueKey('group-field')));
    await t.enterText(find.byKey(const ValueKey('group-field')), 'Work');
    await t.enterText(find.byKey(const ValueKey('tags-field')), 'de, vpn');
    await reveal(t, find.byKey(const ValueKey('startup-field')));
    await t.enterText(find.byKey(const ValueKey('startup-field')), 'cd /srv');
    await reveal(t, find.byKey(const ValueKey('jump-field')));
    await t.tap(find.byKey(const ValueKey('jump-field')));
    await t.pumpAndSettle();
    await t.tap(find.text('Bastion').last);
    await t.pumpAndSettle();

    await reveal(t, find.byKey(const ValueKey('add-forward')));
    await t.tap(find.byKey(const ValueKey('add-forward')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('fwd-save'))); // empty: validation
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('fwd-save')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('fwd-local')), '8080');
    await t.enterText(find.byKey(const ValueKey('fwd-rport')), '80');
    await t.tap(find.byKey(const ValueKey('fwd-save')));
    await t.pumpAndSettle();
    expect(find.text('L 8080 → 127.0.0.1:80'), findsOneWidget);
    await tapSaveEn(t);

    await reloadStore();
    final h = Store.i.hosts.firstWhere((h) => h.host == '10.0.0.7');
    expect([h.group, h.tags, h.startupCmd, h.jumpHostId, h.auth], ['Work', ['de', 'vpn'], 'cd /srv', 'j', 'key']);
    expect(h.forwards.single.summary, 'L 8080 → 127.0.0.1:80');
    final key = (await Store.i.secret(h.id)).privateKey;
    expect(publicKeyFromPrivate(key, comment: pub.split(' ').last), pub);
  });

  testWidgets('Files tab lists saved servers (fa)', (t) async {
    await setSize(t, phone);
    await launch(t);
    await t.tap(find.text('فایل‌ها').last);
    await t.pumpAndSettle();
    expect(find.textContaining('اول یک سرور اضافه کنید'), findsOneWidget);
    await Store.i.upsertHost(Host(id: 'a', label: 'سرور آلمان', host: '1.2.3.4', user: 'root'), HostSecret());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('files-host-a')), findsOneWidget);
    expect(find.text('sftp root@1.2.3.4'), findsOneWidget);
  });

  testWidgets('settings: clear history, session log toggle, backup entries', (t) async {
    await setSize(t, phone);
    await english();
    Store.i.addHistory('ls -la');
    Store.i.addHistory('df -h');
    await launch(t);
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    await reveal(t, find.byKey(const ValueKey('log-sessions')));
    await t.tap(find.byKey(const ValueKey('log-sessions')));
    await t.pumpAndSettle();
    expect(Store.i.settings.logSessions, isTrue);
    await reloadStore();
    expect(Store.i.settings.logSessions, isTrue, reason: 'saved');

    await reveal(t, find.byKey(const ValueKey('export-backup')));
    expect(find.text('Export encrypted backup'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-backup')), findsOneWidget);
    await reveal(t, find.byKey(const ValueKey('clear-history')));
    expect(find.text('2 commands'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('clear-history')));
    await t.pumpAndSettle();
    await t.tap(find.text('Clear').last);
    await t.pumpAndSettle();
    expect(Store.i.history, isEmpty);
    await reloadStore();
    expect(Store.i.history, isEmpty);

    // export: password must be repeated correctly
    await reveal(t, find.byKey(const ValueKey('export-backup')));
    await t.tap(find.byKey(const ValueKey('export-backup')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('backup-pw')), 'abc');
    await t.tap(find.byKey(const ValueKey('backup-pw-ok')));
    await t.pumpAndSettle();
    expect(find.text('At least 6 characters'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('backup-pw')), 'abcdef');
    await t.enterText(find.byKey(const ValueKey('backup-pw2')), 'abcdeg');
    await t.tap(find.byKey(const ValueKey('backup-pw-ok')));
    await t.pumpAndSettle();
    expect(find.text("Passwords don't match"), findsOneWidget);
    await t.tap(find.text('Cancel').last);
    await t.pumpAndSettle();
  });

  testWidgets('session logs screen lists saved logs and deletes one', (t) async {
    await setSize(t, phone);
    await english();
    final tmp = Directory.systemTemp.createTempSync('mterm_logs_ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    appDocsDir = () async => tmp;
    Directory('${tmp.path}/logs').createSync();
    File('${tmp.path}/logs/srv_20260101-101010.txt').writeAsStringSync('hello log\n');
    await launch(t);
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    await reveal(t, find.byKey(const ValueKey('view-logs')));
    await t.tap(find.byKey(const ValueKey('view-logs')));
    await waitFor(t, () => find.byKey(const ValueKey('log-srv_20260101-101010.txt')).evaluate().isNotEmpty);
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert).last);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last); // confirm
    await waitFor(t, () => find.textContaining('No logs yet').evaluate().isNotEmpty);
    expect(File('${tmp.path}/logs/srv_20260101-101010.txt').existsSync(), isFalse);
  });

  testWidgets('terminal: search in output finds, counts and steps through matches', (t) async {
    await setSize(t, phone);
    await english();
    await Store.i.upsertHost(Host(id: 'a', label: 'srv', host: 'example.com', user: 'root'), HostSecret());
    await launch(t);
    final s = Sessions.i.open(Store.i.hosts.first)..debugSetStatus(SessStatus.connected);
    s.terminal.write('first Needle here\r\nnothing\r\nsecond needle\r\n');
    await openTerminal(t, s);
    await menu(t, 'Search in output');
    expect(find.byKey(const ValueKey('term-search')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('term-search')), 'needle');
    await t.pumpAndSettle();
    String count() => (t.widget(find.byKey(const ValueKey('term-search-count'))) as Text).data!;
    expect(count(), '2/2', reason: 'starts at the newest match');
    final ctl = (t.widget(find.byType(TerminalView).first) as TerminalView).controller!;
    expect(ctl.highlights, hasLength(2));
    await t.tap(find.byKey(const ValueKey('term-search-prev')));
    await t.pumpAndSettle();
    expect(count(), '1/2');
    await t.tap(find.byKey(const ValueKey('term-search-next')));
    await t.pumpAndSettle();
    expect(count(), '2/2');
    await t.tap(find.byKey(const ValueKey('term-search-next')));
    await t.pumpAndSettle();
    expect(count(), '1/2', reason: 'wraps around');
    await t.enterText(find.byKey(const ValueKey('term-search')), 'zzz');
    await t.pumpAndSettle();
    expect(count(), '0/0');
    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('term-search')), findsNothing);
    expect(ctl.highlights, isEmpty);
    Sessions.i.close(s);
  });

  testWidgets('terminal: forwarding sheet lists rules, adds one (saved to the server)', (t) async {
    await setSize(t, phone);
    await english();
    await Store.i.upsertHost(
        Host(id: 'a', label: 'srv', host: 'example.com', user: 'root', forwards: [
          ForwardRule(id: 'r', type: 'dynamic', localPort: 1080),
        ]),
        HostSecret(password: 'keep'));
    await launch(t);
    final s = Sessions.i.open(Store.i.hosts.first)..debugSetStatus(SessStatus.closed);
    await openTerminal(t, s);
    await menu(t, 'Port forwarding');
    expect(find.text('D 1080 (SOCKS5)'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sheet-add-forward')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('fwd-local')), '9000');
    await t.enterText(find.byKey(const ValueKey('fwd-rhost')), 'db.internal');
    await t.enterText(find.byKey(const ValueKey('fwd-rport')), '5432');
    await t.tap(find.byKey(const ValueKey('fwd-save')));
    await t.pumpAndSettle();
    expect(find.text('L 9000 → db.internal:5432'), findsOneWidget);
    await reloadStore();
    expect(Store.i.hosts.single.forwards.map((f) => f.summary), ['D 1080 (SOCKS5)', 'L 9000 → db.internal:5432']);
    expect((await Store.i.secret('a')).password, 'keep', reason: 'adding a rule keeps the password');
    Sessions.i.close(s);
  });

  testWidgets('split view only on wide screens; shows two terminals side by side', (t) async {
    await english();
    await Store.i.upsertHost(Host(id: 'a', label: 'one', host: 'a.example', user: 'root'), HostSecret());
    await Store.i.upsertHost(Host(id: 'b', label: 'two', host: 'b.example', user: 'root'), HostSecret());
    final s1 = Sessions.i.open(Store.i.hosts[0])..debugSetStatus(SessStatus.closed);
    final s2 = Sessions.i.open(Store.i.hosts[1])..debugSetStatus(SessStatus.closed);

    await setSize(t, phone);
    await launch(t);
    await openTerminal(t, s1);
    expect(find.byKey(const ValueKey('split-toggle')), findsNothing, reason: 'phones stay unchanged');
    Navigator.of(t.element(find.byType(TerminalScreen))).pop();
    await t.pumpAndSettle();

    await setSize(t, const Size(1280, 800), dpr: 1);
    await t.pumpAndSettle();
    await openTerminal(t, s1);
    await t.tap(find.byKey(const ValueKey('split-toggle')));
    await t.pumpAndSettle();
    await t.tap(find.text('two').first);
    await t.pumpAndSettle();
    expect(find.byType(TerminalView), findsNWidgets(2));
    expect(find.byType(SplitPane), findsOneWidget);
    final left = t.getCenter(find.byType(TerminalView).first).dx;
    final right = t.getCenter(find.byType(TerminalView).last).dx;
    expect(left, lessThan(right));
    await t.tap(find.byKey(const ValueKey('split-close')));
    await t.pumpAndSettle();
    expect(find.byType(TerminalView), findsOneWidget);
    expect(Sessions.i.list, contains(s2), reason: 'closing the split keeps the session open');
    Sessions.i.close(s1);
    Sessions.i.close(s2);
  });

  testWidgets('desktop: Ctrl+Shift+V pastes into the terminal (Windows only)', (t) async {
    expect(terminalShortcuts().keys.whereType<SingleActivator>().any((a) => a.shift && a.trigger == LogicalKeyboardKey.keyV),
        isFalse,
        reason: 'mobile keeps the default shortcuts');
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await setSize(t, const Size(1280, 800), dpr: 1);
    await english();
    await Store.i.upsertHost(Host(id: 'a', label: 'srv', host: 'example.com', user: 'root'), HostSecret());
    await launch(t);
    final s = Sessions.i.open(Store.i.hosts.first)..debugSetStatus(SessStatus.connected);
    await openTerminal(t, s);
    await t.tap(find.byType(TerminalView));
    await t.pumpAndSettle();
    clipboard = 'echo pasted';
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyV);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(s.line, 'echo pasted');
    // Ctrl+V pastes too
    s.line = '';
    clipboard = 'two';
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyV);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(s.line, 'two');
    Sessions.i.close(s);
    await t.pumpWidget(const SizedBox());
  });

  group('new screens fit a small phone in every language', () {
    for (final lang in languageCodes) {
      testWidgets(lang, (t) async {
        await setSize(t, const Size(360, 700));
        Store.i.settings.language = lang;
        await Store.i.saveSettings();
        await Store.i.upsertHost(
            Host(id: 'a', label: 'srv', host: 'example.com', user: 'root', group: 'G', tags: ['x'], forwards: [
              ForwardRule(id: 'r', localPort: 8080, remoteHost: 'localhost', remotePort: 80),
            ]),
            HostSecret());
        await launch(t);
        // host form, scrolled to the end, key mode, rule dialog
        await t.tap(find.byKey(const ValueKey('fab-add-host')));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.key));
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, -4000));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('add-forward')));
        await t.pumpAndSettle();
        await t.tap(find.text(S.forCode(lang)['fwdDynamic']).last);
        await t.pumpAndSettle();
        await t.tap(find.text(S.forCode(lang)['cancel']).last);
        await t.pumpAndSettle();
        await t.tap(find.byType(BackButton).last);
        await t.pumpAndSettle();
        // files tab
        await t.tap(find.byType(NavigationDestination).at(1));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('files-host-a')), findsOneWidget);
        // settings scrolled to the end
        await t.tap(find.byType(NavigationDestination).at(3));
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, -4000));
        await t.pumpAndSettle();
        // terminal with search bar and forwarding sheet
        final s = Sessions.i.open(Store.i.hosts.first)..debugSetStatus(SessStatus.closed);
        await openTerminal(t, s);
        await menu(t, S.forCode(lang)['searchOutput']);
        await t.enterText(find.byKey(const ValueKey('term-search')), 'x');
        await t.pumpAndSettle();
        await menu(t, S.forCode(lang)['portForwarding']);
        expect(find.text('L 8080 → localhost:80'), findsOneWidget);
        Sessions.i.close(s);
      });
    }
  });
}

Future<void> tapSaveEn(WidgetTester t) async {
  final btn = find.widgetWithText(FilledButton, 'Save');
  await reveal(t, btn);
  await t.tap(btn);
  await t.pumpAndSettle();
}
