// End-to-end UI flows against a real OpenSSH server on 127.0.0.1:2222
// (user mtest / Pass1234, key /tmp/mp/idk). Every test skips cleanly when the port is closed (CI).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/common.dart';
import 'package:mterm/screens/lock_screen.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:xterm/xterm.dart';

import 'support.dart';

const label = 'سرور محلی';
const phone = Size(412, 915);

Future<Host> addHost({String id = 'h', String name = label, String pw = sshPass}) async {
  final h = Host(id: id, label: name, host: sshHost, port: sshPort, user: sshUser);
  await Store.i.upsertHost(h, HostSecret(password: pw));
  return h;
}

/// Taps the host in the list and, if asked, answers the first-connect host key prompt.
Future<TermSession> openFromList(WidgetTester t, String name, {bool expectPrompt = true}) async {
  final before = Sessions.i.list.length;
  await t.tap(find.text(name).last);
  await t.pump();
  final s = Sessions.i.list[before];
  if (expectPrompt) {
    await waitFor(t, () => find.text('اعتماد و اتصال').evaluate().isNotEmpty, reason: 'host key prompt');
    expect(find.text('سرور جدید'), findsOneWidget);
    await t.tap(find.text('اعتماد و اتصال'));
  }
  var prompted = false;
  await waitFor(t, () {
    if (find.byType(AlertDialog).evaluate().isNotEmpty) prompted = true;
    return s.status != SessStatus.connecting;
  }, reason: 'connect');
  if (!expectPrompt) expect(prompted, isFalse, reason: 'host key must not be asked again');
  await t.pump(const Duration(milliseconds: 400)); // route transition + double-tap timer
  return s;
}

/// Types like the soft keyboard does (xterm's input connection keeps two placeholder spaces).
Future<void> type(WidgetTester t, String text) async {
  t.testTextInput.updateEditingValue(
      TextEditingValue(text: '  $text', selection: TextSelection.collapsed(offset: text.length + 2)));
  await t.pump();
}

Future<void> enter(WidgetTester t) async {
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pump();
}

Future<void> typeLine(WidgetTester t, String cmd) async {
  await type(t, cmd);
  await enter(t);
}

/// Waits until a line of terminal *output* (not the echoed command) matches [line].
Future<void> waitLine(WidgetTester t, TermSession s, String line, {int times = 1, int seconds = 10}) async {
  final re = RegExp('^${RegExp.escape(line)}\\s*\$', multiLine: true);
  await waitFor(t, () => re.allMatches(bufferOf(s)).length >= times, seconds: seconds,
      reason: 'output "$line" x$times\n---\n${bufferOf(s)}');
}

Future<void> barKey(WidgetTester t, String k) async {
  final bar = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right).last;
  if (find.text(k).evaluate().isEmpty) {
    await t.drag(bar, const Offset(3000, 0)); // back to the start
    await t.pump(const Duration(milliseconds: 500));
    await t.scrollUntilVisible(find.text(k), 80, scrollable: bar);
  }
  await t.ensureVisible(find.text(k));
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text(k));
  await t.pump();
}

final _vScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

/// Scrolls the top-most sheet/list until [f] shows, then taps it.
Future<void> sheetTap(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 120, scrollable: _vScroll.last);
  await t.ensureVisible(f.last);
  await t.pumpAndSettle();
  await t.tap(f.last);
  await t.pump();
}

Future<void> focusTerminal(WidgetTester t) async {
  await t.tap(find.byType(TerminalView));
  await t.pump(const Duration(milliseconds: 400));
  expect(t.testTextInput.hasAnyClients, isTrue, reason: 'terminal must open the soft keyboard');
}

void main() {
  setUpAll(installMocks);
  setUp(freshStore);
  final skip = !sshUp; // no local sshd on 127.0.0.1:2222 (CI)

  testWidgets('terminal: connect, type, key bar, snippets, exit + reconnect', (t) async {
    await setSize(t, phone);
    await addHost();
    await Store.i.upsertSnippet(Snippet(id: 'sx', name: 'پنج', cmd: r'echo snip_$((2+3))'));
    await launch(t);
    final s = await openFromList(t, label);
    expect(s.status, SessStatus.connected, reason: s.error);
    expect(Store.i.knownFingerprint(sshHost, sshPort), isNotNull);
    expect(find.byType(TerminalView), findsOneWidget);
    await focusTerminal(t);

    // typing through the soft keyboard
    await typeLine(t, 'echo hello_mterm');
    await waitLine(t, s, 'hello_mterm');
    expect(s.typed.first, 'echo hello_mterm');

    // suggestion bar offers history; tapping it fills the line, enter runs it
    await type(t, 'ech');
    expect(s.line, 'ech');
    final chip = find.descendant(of: find.byType(InkWell), matching: find.text('echo hello_mterm'));
    expect(chip, findsOneWidget);
    await t.tap(chip);
    await t.pump();
    await enter(t);
    await waitLine(t, s, 'hello_mterm', times: 2);

    // backspace (soft keyboard delete) edits the line
    await type(t, 'echo abX');
    t.testTextInput.updateEditingValue(const TextEditingValue(text: ' ', selection: TextSelection.collapsed(offset: 1)));
    await t.pump();
    await type(t, 'c');
    await enter(t);
    await waitLine(t, s, 'abc');

    // ^C from the key bar interrupts a running command
    await typeLine(t, 'sleep 30; echo NOT_INTERRUPTED');
    await settleIo(t, 400);
    await barKey(t, '^C');
    await typeLine(t, 'echo after_c');
    await waitLine(t, s, 'after_c', seconds: 5);
    expect(bufferOf(s), isNot(contains('\nNOT_INTERRUPTED')));

    // ctrl toggle + typed letter
    await typeLine(t, 'sleep 30; echo NOT_INTERRUPTED');
    await settleIo(t, 400);
    await barKey(t, 'ctrl');
    expect(s.ctrl, isTrue);
    await type(t, 'c');
    expect(s.ctrl, isFalse);
    await typeLine(t, 'echo after_ctrl_c');
    await waitLine(t, s, 'after_ctrl_c', seconds: 5);

    // tab completion
    await typeLine(t, 'touch /tmp/mterm_tabtest_file');
    await type(t, 'ls /tmp/mterm_tabt');
    await barKey(t, 'tab');
    await enter(t);
    await waitLine(t, s, '/tmp/mterm_tabtest_file');

    // ↑ recalls the previous command
    await barKey(t, '↑');
    await enter(t);
    await waitLine(t, s, '/tmp/mterm_tabtest_file', times: 2);

    // arrow / esc bytes, seen raw through cat -v
    await typeLine(t, 'cat -v');
    await settleIo(t, 300);
    for (final k in ['↑', '↓', '→', '←', 'esc']) {
      await barKey(t, k);
    }
    await type(t, 'Z');
    await enter(t);
    await waitFor(t, () => RegExp(r'\^\[(\[|O)A\^\[(\[|O)B\^\[(\[|O)C\^\[(\[|O)D\^\[Z').allMatches(bufferOf(s)).length >= 2,
        reason: 'raw arrow bytes\n${bufferOf(s)}');
    await barKey(t, 'ctrl');
    await type(t, 'd'); // EOF ends cat
    await typeLine(t, 'echo cat_done');
    await waitLine(t, s, 'cat_done');

    // snippet from the ⚡ sheet
    await t.tap(find.byTooltip('دستورها'));
    await t.pumpAndSettle();
    await sheetTap(t, find.text('پنج'));
    await t.pumpAndSettle();
    await waitLine(t, s, 'snip_5');
    // history entry from the same sheet
    await t.tap(find.byTooltip('دستورها'));
    await t.pumpAndSettle();
    await sheetTap(t, find.text('echo cat_done'));
    await t.pumpAndSettle();
    await waitLine(t, s, 'cat_done', times: 2);

    // exit -> banner -> reconnect (no second host-key prompt)
    await typeLine(t, 'exit');
    await waitFor(t, () => s.status == SessStatus.closed, reason: 'closed after exit');
    expect(find.text('اتصال قطع شد'), findsOneWidget);
    expect(bufferOf(s), contains('[connection closed]'));
    await t.tap(find.widgetWithText(FilledButton, 'اتصال دوباره'));
    await t.pump();
    await waitFor(t, () => s.status == SessStatus.connected, reason: 'reconnect');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('اتصال قطع شد'), findsNothing);
    await focusTerminal(t);
    await typeLine(t, 'echo back_again');
    await waitLine(t, s, 'back_again');

    // reconnect from the menu while still connected: old connection's close must not kill the new one
    final seen = <SessStatus>[];
    void rec() => seen.add(s.status);
    s.addListener(rec);
    final closedNotes = count(bufferOf(s), '[connection closed]');
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('اتصال دوباره'));
    await t.pumpAndSettle();
    await waitFor(t, () => s.status == SessStatus.connected, reason: 'menu reconnect');
    await settleIo(t, 1500);
    s.removeListener(rec);
    expect(s.status, SessStatus.connected, reason: 'stale close callback marked the new connection closed');
    expect(seen, isNot(contains(SessStatus.closed)), reason: 'statuses during reconnect: $seen');
    expect(count(bufferOf(s), '[connection closed]'), closedNotes);
    expect(find.text('اتصال قطع شد'), findsNothing);
    await focusTerminal(t);
    await typeLine(t, 'echo after_menu_reconnect');
    await waitLine(t, s, 'after_menu_reconnect');

    // close session from the menu
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('بستن نشست'));
    await t.pumpAndSettle();
    expect(Sessions.i.list, isEmpty);
    expect(find.byType(TerminalView), findsNothing);
    await closeAll(t);
  }, skip: skip);

  testWidgets('wrong password shows a readable error, no crash', (t) async {
    await setSize(t, phone);
    await addHost(pw: 'definitely-wrong');
    await launch(t);
    final s = await openFromList(t, label);
    expect(s.status, SessStatus.failed);
    expect(s.error, 'نام کاربری، رمز یا کلید اشتباه است');
    // the terminal grid cannot shape RTL text, so app messages inside it must not be Persian
    expect(RegExp('[\u0600-\u06FF]').hasMatch(bufferOf(s)), isFalse, reason: bufferOf(s));
    expect(bufferOf(s), contains('Connection failed'));
    expect(find.widgetWithText(Row, 'نام کاربری، رمز یا کلید اشتباه است'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'اتصال دوباره'), findsOneWidget);
    // back in the list the open session shows the error too
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('نشست‌های باز'), findsOneWidget);
    expect(find.text('نام کاربری، رمز یا کلید اشتباه است'), findsOneWidget);
    await closeAll(t);
  }, skip: skip);

  testWidgets('host key: trusted once, changed key warns', (t) async {
    await setSize(t, phone);
    await addHost();
    await launch(t);
    var s = await openFromList(t, label);
    expect(s.status, SessStatus.connected);
    final fp = Store.i.knownFingerprint(sshHost, sshPort);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    // second connect: no prompt
    s = await openFromList(t, label, expectPrompt: false);
    expect(s.status, SessStatus.connected);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await closeAll(t);

    // the server "changes" its key
    await Store.i.trust(sshHost, sshPort, 'aa:bb:cc');
    await t.tap(find.text(label).last);
    await t.pump();
    s = Sessions.i.list.last;
    await waitFor(t, () => find.text('کلید سرور عوض شده!').evaluate().isNotEmpty, reason: 'changed-key warning');
    expect(find.textContaining(fp!), findsOneWidget);
    await t.tap(find.text('رد کردن'));
    await waitFor(t, () => s.status == SessStatus.failed);
    expect(s.error, 'کلید سرور تأیید نشد');
    expect(find.text('کلید سرور تأیید نشد'), findsWidgets);
    expect(Store.i.knownFingerprint(sshHost, sshPort), 'aa:bb:cc');

    // reconnect and accept the new key on purpose
    await t.tap(find.widgetWithText(FilledButton, 'اتصال دوباره'));
    await waitFor(t, () => find.text('به هر حال وصل شو').evaluate().isNotEmpty);
    await t.tap(find.text('به هر حال وصل شو'));
    await waitFor(t, () => s.status == SessStatus.connected);
    expect(Store.i.knownFingerprint(sshHost, sshPort), fp);
    await closeAll(t);
  }, skip: skip);

  testWidgets('two sessions to the same server are independent', (t) async {
    await setSize(t, phone);
    await addHost();
    await launch(t);
    final a = await openFromList(t, label);
    await focusTerminal(t);
    await typeLine(t, 'export MARK=one; echo A_\$MARK');
    await waitLine(t, a, 'A_one');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('نشست‌های باز'), findsOneWidget);

    final b = await openFromList(t, label, expectPrompt: false);
    expect(identical(a, b), isFalse);
    await focusTerminal(t);
    await typeLine(t, r'echo B_${MARK:-unset}');
    await waitLine(t, b, 'B_unset');
    expect(bufferOf(a), isNot(contains('B_unset')));
    expect(bufferOf(b), isNot(contains('A_one')));
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('وصل'), findsNWidgets(2));

    // back to the first one from "open sessions"
    await t.tap(find.text(label).first);
    await t.pumpAndSettle();
    await focusTerminal(t);
    await typeLine(t, r'echo A_again_$MARK');
    await waitLine(t, a, 'A_again_one');
    expect(bufferOf(b), isNot(contains('A_again')));
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    // closing one leaves the other alive
    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    expect(Sessions.i.list, hasLength(1));
    final left = Sessions.i.list.single;
    await settleIo(t, 500);
    expect(left.status, SessStatus.connected);
    left.run('echo still_here');
    await waitLine(t, left, 'still_here');
    await closeAll(t);
  }, skip: skip);

  testWidgets('host added with a pasted SSH key connects', (t) async {
    await setSize(t, phone);
    await launch(t);
    await t.tap(find.byType(FloatingActionButton).first);
    await t.pumpAndSettle();
    await t.enterText(fieldLabeled('نام (اختیاری)'), 'کلیدی');
    await t.enterText(fieldLabeled('آدرس سرور'), sshHost);
    await t.enterText(fieldLabeled('پورت'), '$sshPort');
    await t.enterText(fieldLabeled('نام کاربری'), sshUser);
    await t.tap(find.text('کلید SSH'));
    await t.pumpAndSettle();
    clipboard = File(keyPath).readAsStringSync();
    await t.ensureVisible(find.text('چسباندن کلید'));
    await t.tap(find.text('چسباندن کلید'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'ذخیره'));
    await t.pumpAndSettle();
    final s = await openFromList(t, 'کلیدی');
    expect(s.status, SessStatus.connected, reason: s.error);
    s.run('whoami');
    await waitLine(t, s, sshUser);
    await closeAll(t);
  }, skip: !(sshUp && File(keyPath).existsSync()));

  testWidgets('run a snippet from the Snippets tab on a live session', (t) async {
    await setSize(t, phone);
    await addHost();
    await addHost(id: 'h2', name: 'دومی');
    await Store.i.upsertSnippet(Snippet(id: 'sy', name: 'جمع', cmd: r'echo sum_$((40+2))'));
    await launch(t);
    final a = await openFromList(t, label);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('دستورها').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('جمع'));
    await t.tap(find.text('جمع'));
    await t.pumpAndSettle();
    expect(find.byType(TerminalView), findsOneWidget);
    await waitLine(t, a, 'sum_42');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    // with two live sessions it asks which one
    await t.tap(find.text('سرورها').last);
    await t.pumpAndSettle();
    final b = await openFromList(t, 'دومی', expectPrompt: false);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('دستورها').last);
    await t.pumpAndSettle();
    await t.tap(find.text('جمع'));
    await t.pumpAndSettle();
    expect(find.text('اجرا روی کدام سرور؟'), findsOneWidget);
    await t.tap(find.text('دومی').last);
    await t.pumpAndSettle();
    await waitLine(t, b, 'sum_42');
    expect(RegExp(r'^sum_42', multiLine: true).allMatches(bufferOf(a)).length, 1);
    await closeAll(t);
  }, skip: skip);

  test('closing a session while it is still connecting does not leave it connected', () async {
    final h = await addHost();
    final s = TermSession(h);
    final asked = Completer<void>();
    final answer = Completer<bool>();
    final done = s.connect((a, b, c) {
      asked.complete();
      return answer.future;
    });
    await asked.future;
    s.close(); // user closes the tab while the host-key prompt is up
    answer.complete(true);
    await done;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(s.status, SessStatus.closed);
    expect(bufferOf(s), isNot(contains(r'$')), reason: 'a shell was opened for a closed session');
  }, skip: skip);

  group('screenshots', () {
    Future<void> shot(WidgetTester t, String name) async {
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    }

    testWidgets('terminal with real output', tags: ['golden'], (t) async {
      await loadFonts();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await setSize(t, const Size(360, 780));
      await addHost();
      await launch(t);
      await t.tap(find.text(label).last);
      await waitFor(t, () => find.text('اعتماد و اتصال').evaluate().isNotEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('اعتماد و اتصال'));
      final s = Sessions.i.list.single;
      await waitFor(t, () => s.status == SessStatus.connected);
      await focusTerminal(t);
      await typeLine(t, r"export LANG=C.UTF-8 PS1='mtest:~$ '; clear");
      await settleIo(t, 600);
      await typeLine(t, 'echo hello_mterm');
      await waitLine(t, s, 'hello_mterm');
      await typeLine(t, r"printf '\e[32mok\e[0m \e[1;34mblue\e[0m \e[33mwarn\e[0m\n'; echo 'سلام دنیا'; seq 1 3");
      await waitLine(t, s, '3');
      await type(t, 'ech');
      await settleIo(t, 300);
      await shot(t, '5_terminal');

      await enter(t);
      await typeLine(t, 'exit');
      await waitFor(t, () => s.status == SessStatus.closed);
      await shot(t, '6_disconnected');
      await closeAll(t);
    }, skip: skip);

    testWidgets('host key prompt and lock screen', tags: ['golden'], (t) async {
      await loadFonts();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await setSize(t, const Size(360, 780));
      await launch(t);
      // fixed fingerprint so the picture is stable
      final fut = hostKeyPrompt(
          'ssh-ed25519', List.generate(32, (i) => i.toRadixString(16).padLeft(2, '0')).join(':'), '00:11');
      await t.pumpAndSettle();
      await shot(t, '7_host_key_changed');
      await t.tap(find.text('رد کردن'));
      await t.pumpAndSettle();
      expect(await fut, isFalse);

      Store.i.settings
        ..lockEnabled = true
        ..pinHash = Store.hashPin('1234');
      await launch(t);
      expect(find.byType(PinPad), findsOneWidget);
      await t.tap(find.text('1'));
      await t.tap(find.text('2'));
      await shot(t, '8_lock');
      await setSize(t, const Size(780, 360));
      await t.pumpAndSettle();
      await shot(t, '9_lock_landscape');
      await t.pumpWidget(const SizedBox());
    });
  });
}

