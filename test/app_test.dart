import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/main.dart';
import 'package:mterm/models.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integration tests against a real OpenSSH server on 127.0.0.1:2222
/// (user mtest / Pass1234, key in /tmp/mp/idk). Skipped when it is not running.
final sshUp = (() {
  try {
    final s = RawSynchronousSocket.connectSync('127.0.0.1', 2222);
    s.closeSync();
    return true;
  } catch (_) {
    return false;
  }
})();

final Map<String, String> secure = {};

Future<void> setup() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Error texts are asserted in Persian.
  SharedPreferences.setMockInitialValues({'settings': '{"language":"fa"}'});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final a = (call.arguments as Map?) ?? {};
      switch (call.method) {
        case 'write':
          secure[a['key']] = a['value'];
          return null;
        case 'read':
          return secure[a['key']];
        case 'delete':
          secure.remove(a['key']);
          return null;
        case 'readAll':
          return secure;
        case 'containsKey':
          return secure.containsKey(a['key']);
      }
      return null;
    },
  );
  await Store.i.init();
}

Future<String> runAndRead(TermSession s, String cmd, String expect) async {
  s.run(cmd);
  for (var i = 0; i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    final t = s.terminal.buffer.getText();
    if (t.contains(expect)) return t;
  }
  return s.terminal.buffer.getText();
}

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await load('Vazirmatn', ['assets/fonts/Vazirmatn-Regular.ttf', 'assets/fonts/Vazirmatn-Bold.ttf']);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-Regular.ttf', 'assets/fonts/JetBrainsMono-Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/workspace/flutter-sdk';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

void main() {
  setUpAll(setup);

  group('SSH engine', () {
    test('password login, run a command, see output', () async {
      final h = Host(id: 'h1', label: 'Test', host: '127.0.0.1', port: 2222, user: 'mtest');
      await Store.i.upsertHost(h, HostSecret(password: 'Pass1234'));
      final s = TermSession(h);
      String? seenFp;
      await s.connect((type, fp, old) async {
        seenFp = fp;
        return true;
      });
      expect(s.status, SessStatus.connected, reason: s.error);
      expect(seenFp, isNotNull);
      final out = await runAndRead(s, r'echo MTERM_$((6*7))', 'MTERM_42');
      expect(out, contains('MTERM_42'));
      // second connect must not ask again (trusted host key)
      var asked = false;
      final s2 = TermSession(h);
      await s2.connect((a, b, c) async => asked = true);
      expect(asked, isFalse);
      expect(s2.status, SessStatus.connected);
      s.close();
      s2.close();
    }, skip: !sshUp);

    test('ctrl from key bar + typed letter becomes a control code', () async {
      final h = Host(id: 'h1', label: 'Test', host: '127.0.0.1', port: 2222, user: 'mtest');
      final s = TermSession(h);
      await s.connect((a, b, c) async => true);
      // type "echo X" then ctrl+u (clears line) then real command
      s.text('echo SHOULD_NOT_RUN');
      s.toggleCtrl();
      s.terminal.textInput('u');
      expect(s.ctrl, isFalse);
      final out = await runAndRead(s, 'echo CTRL_OK', 'CTRL_OK\n');
      expect(out.contains('SHOULD_NOT_RUN\n'), isFalse);
      s.close();
    }, skip: !sshUp);

    test('private key login', () async {
      final h = Host(id: 'h2', label: 'Key', host: '127.0.0.1', port: 2222, user: 'mtest', auth: 'key');
      await Store.i.upsertHost(h, HostSecret(privateKey: File('/tmp/mp/idk').readAsStringSync()));
      final s = TermSession(h);
      await s.connect((a, b, c) async => true);
      expect(s.status, SessStatus.connected, reason: s.error);
      final out = await runAndRead(s, 'whoami', 'mtest');
      expect(out, contains('mtest'));
      s.close();
    }, skip: !sshUp || !File('/tmp/mp/idk').existsSync());

    test('wrong password gives a clear error', () async {
      final h = Host(id: 'h3', label: 'Bad', host: '127.0.0.1', port: 2222, user: 'mtest');
      await Store.i.upsertHost(h, HostSecret(password: 'nope'));
      final s = TermSession(h);
      await s.connect((a, b, c) async => true);
      expect(s.status, SessStatus.failed);
      expect(s.error, contains('اشتباه'));
    }, skip: !sshUp);

    test('closed port gives a clear error', () async {
      final h = Host(id: 'h4', label: 'Off', host: '127.0.0.1', port: 2299, user: 'x');
      await Store.i.upsertHost(h, HostSecret(password: 'x'));
      final s = TermSession(h);
      await s.connect((a, b, c) async => true);
      expect(s.status, SessStatus.failed);
      expect(s.error, isNotEmpty);
    });

    test('changed host key is reported as changed', () async {
      await Store.i.trust('127.0.0.1', 2222, 'aa:bb');
      final h = Host(id: 'h1', label: 'Test', host: '127.0.0.1', port: 2222, user: 'mtest');
      String? old;
      final s = TermSession(h);
      await s.connect((a, b, o) async {
        old = o;
        return false;
      });
      expect(old, 'aa:bb');
      expect(s.status, SessStatus.failed);
    }, skip: !sshUp);
  });

  group('screens', () {
    Future<void> shot(WidgetTester t, String name) async {
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    }

    testWidgets('main screens render', tags: ['golden'], (t) async {
      await loadFonts();
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 3;
      Store.i.hosts.clear();
      await Store.i.upsertHost(
          Host(id: 'a', label: 'سرور آلمان', host: '91.107.1.20', user: 'root', color: 0), HostSecret(password: 'x'));
      await Store.i.upsertHost(
          Host(id: 'b', label: 'سرور فنلاند', host: 'fi.example.com', port: 2200, user: 'admin', color: 1, auth: 'key'),
          HostSecret());
      await t.pumpWidget(const MTermApp());
      await shot(t, '1_hosts');
      expect(find.text('سرور آلمان'), findsOneWidget);
      await t.tap(find.text('دستورها').last);
      await shot(t, '2_snippets');
      await t.tap(find.text('تنظیمات').last);
      await shot(t, '3_settings');
      await t.tap(find.text('سرورها').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('fab-add-host')));
      await shot(t, '4_add_host');
      addTearDown(t.view.reset);
    });
  });
}
