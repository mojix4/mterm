// Real Windows check: the app runs as a desktop exe, and keystrokes are sent
// by Windows itself (PowerShell SendKeys into the foreground window), not by
// the test framework. Verifies typing reaches the terminal session.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mterm/main.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/terminal_screen.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:xterm/xterm.dart';

Future<void> sendKeys(String keys) async {
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('$keys')",
  ]);
  // ignore: avoid_print
  print('SendKeys exit ${r.exitCode} ${r.stderr}');
}

Future<void> realWait(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows: OS keystrokes reach the terminal', (t) async {
    await Store.i.init();
    Store.i.settings.language = 'en';
    Store.i.settings.keepAlive = 0;
    await Store.i.saveSettings();
    await Store.i.upsertHost(Host(id: 'kb', label: 'srv', host: 'example.com', user: 'root'), HostSecret());
    await t.pumpWidget(const MTermApp());
    await t.pumpAndSettle();
    final s = Sessions.i.open(Store.i.hosts.firstWhere((h) => h.id == 'kb'))..debugSetStatus(SessStatus.connected);
    navKey.currentState!.push(MaterialPageRoute(builder: (_) => TerminalScreen(session: s)));
    await t.pumpAndSettle();
    expect(find.byType(TerminalView), findsWidgets);
    await t.tap(find.byType(TerminalView).first);
    await t.pumpAndSettle();
    await realWait(t, 1500);

    s.line = '';
    await t.runAsync(() => sendKeys('ls'));
    await realWait(t, 2500);
    // ignore: avoid_print
    print('typed line: "${s.line}"');
    expect(s.line, 'ls', reason: 'keys sent by Windows must reach the session');

    s.line = '';
    await t.runAsync(() => sendKeys('echo hi'));
    await realWait(t, 2500);
    expect(s.line, 'echo hi');
    Sessions.i.close(s);
  });
}
