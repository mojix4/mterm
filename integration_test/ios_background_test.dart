// Real iOS check (simulator): connect over SSH, send the app to the background
// for 60 s (the CI script opens Settings over it), bring it back, and check the
// SSH session is still alive and runs a command.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mterm/main.dart';
import 'package:mterm/models.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:path_provider/path_provider.dart';

const keyB64 = String.fromEnvironment('SSH_KEY_B64');
const sshUser = String.fromEnvironment('SSH_USER');

Future<void> realWait(WidgetTester t, bool Function() cond, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end) && !cond()) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
  }
}

class _Life with WidgetsBindingObserver {
  final seen = <AppLifecycleState>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => seen.add(s);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS: SSH session survives 60 s in the background', (t) async {
    await Store.i.init();
    Store.i.settings.language = 'en';
    await Store.i.saveSettings(); // keep-alive stays at the app default
    await Store.i.upsertHost(
        Host(id: 'bg', label: 'local', host: '127.0.0.1', port: 2222, user: sshUser, auth: 'key'),
        HostSecret(privateKey: utf8.decode(base64.decode(keyB64))));
    await t.pumpWidget(const MTermApp());
    await t.pumpAndSettle();
    final life = _Life();
    WidgetsBinding.instance.addObserver(life);

    final s = Sessions.i.open(Store.i.hosts.firstWhere((h) => h.id == 'bg'));
    await t.runAsync(() => s.connect((a, b, c) async => true));
    await realWait(t, () => s.status == SessStatus.connected || s.status == SessStatus.failed);
    expect(s.status, SessStatus.connected);
    s.run(r'echo before_$((1+1))');
    await realWait(t, () => s.terminal.buffer.getText().contains('before_2'));
    expect(s.terminal.buffer.getText(), contains('before_2'));

    // ask the CI script to background us
    final docs = await t.runAsync(getApplicationDocumentsDirectory);
    await t.runAsync(() => File('${docs!.path}/bg_now').writeAsString('1'));
    // ignore: avoid_print
    print('marker written in ${docs!.path}');
    // wait until we were backgrounded and came back
    await realWait(t, () => life.seen.contains(AppLifecycleState.paused), seconds: 60);
    // ignore: avoid_print
    print('went to background: ${life.seen}');
    expect(life.seen, contains(AppLifecycleState.paused), reason: 'the app was never sent to the background');
    await realWait(t, () => life.seen.isNotEmpty && life.seen.last == AppLifecycleState.resumed, seconds: 120);
    // ignore: avoid_print
    print('lifecycle: ${life.seen}, status after: ${s.status} ${s.error}');
    expect(life.seen.last, AppLifecycleState.resumed);
    await realWait(t, () => false, seconds: 3);

    expect(s.status, SessStatus.connected, reason: 'session dropped while in the background');
    s.run(r'echo after_$((2+3))');
    await realWait(t, () => s.terminal.buffer.getText().contains('after_5'));
    // ignore: avoid_print
    print('after: ${s.terminal.buffer.getText().contains('after_5')}');
    expect(s.terminal.buffer.getText(), contains('after_5'));
    Sessions.i.close(s);
  });
}
