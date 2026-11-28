// Real iOS check (simulator on macOS CI): the app runs on the iOS runtime with
// real plugins (Keychain, prefs), opens a real SSH connection to a local sshd,
// runs a command, and the on-screen keyboard path delivers typed text.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mterm/main.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/terminal_screen.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:xterm/xterm.dart';

const keyB64 = String.fromEnvironment('SSH_KEY_B64');
const sshUser = String.fromEnvironment('SSH_USER');

Future<void> realWait(WidgetTester t, bool Function() cond, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end) && !cond()) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS: real SSH connect, run a command, type with the keyboard', (t) async {
    await Store.i.init();
    Store.i.settings.language = 'en';
    Store.i.settings.keepAlive = 0;
    await Store.i.saveSettings();
    final key = utf8.decode(base64.decode(keyB64));
    await Store.i.upsertHost(
        Host(id: 'ios', label: 'local', host: '127.0.0.1', port: 2222, user: sshUser, auth: 'key'),
        HostSecret(privateKey: key));
    // secret really stored in the iOS Keychain and read back
    final h = Store.i.hosts.firstWhere((e) => e.id == 'ios');
    await t.pumpWidget(const MTermApp());
    await t.pumpAndSettle();

    final s = Sessions.i.open(h);
    await t.runAsync(() => s.connect((a, b, c) async => true));
    await realWait(t, () => s.status == SessStatus.connected || s.status == SessStatus.failed);
    // ignore: avoid_print
    print('status: ${s.status} error: ${s.error}');
    expect(s.status, SessStatus.connected);

    s.run(r'echo mterm_ios_$((6*7))');
    await realWait(t, () => s.terminal.buffer.getText().contains('mterm_ios_42'));
    expect(s.terminal.buffer.getText(), contains('mterm_ios_42'));

    // keyboard: the terminal screen with the on-screen keyboard input channel
    navKey.currentState!.push(MaterialPageRoute(builder: (_) => TerminalScreen(session: s)));
    await t.pumpAndSettle();
    t.testTextInput.register();
    await t.tap(find.byType(TerminalView).first);
    await t.pumpAndSettle();
    // like the iOS keyboard: one update per key, on top of the 2-space
    // placeholder the terminal keeps for backspace detection
    Future<void> key(String c) async {
      t.testTextInput.enterText('  $c');
      await t.pump();
    }
    for (final c in 'echo typed_X'.split('')) {
      await key(c);
    }
    t.testTextInput.enterText(' '); // backspace removes the X
    await t.pump();
    for (final c in r'$((5+5))'.split('')) {
      await key(c);
    }
    s.text('\r');
    await realWait(t, () => s.terminal.buffer.getText().contains('typed_10'));
    // ignore: avoid_print
    print('buffer tail: ${s.terminal.buffer.getText().split('\n').where((l) => l.trim().isNotEmpty).toList().reversed.take(4).toList()}');
    expect(s.terminal.buffer.getText(), contains('typed_10'));
    Sessions.i.close(s);
  });
}
