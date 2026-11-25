// Shared helpers for MTerm widget / flow tests.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/main.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// True when the local OpenSSH test server (127.0.0.1:2222, mtest/Pass1234) is reachable.
final bool sshUp = (() {
  try {
    final s = RawSynchronousSocket.connectSync('127.0.0.1', 2222);
    s.closeSync();
    return true;
  } catch (_) {
    return false;
  }
})();

const sshHost = '127.0.0.1';
const sshPort = 2222;
const sshUser = 'mtest';
const sshPass = 'Pass1234';
const keyPath = '/tmp/mp/idk';

final Map<String, String> secure = {};
String? clipboard;
int wakelockCalls = 0;

/// Platform plugin mocks: secure storage, clipboard, wakelock, local_auth (no biometrics).
void installMocks() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
    final a = (call.arguments as Map?) ?? {};
    switch (call.method) {
      case 'write':
        secure[a['key'] as String] = a['value'] as String;
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
  });
  m.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        return clipboard == null ? null : {'text': clipboard};
      case 'Clipboard.hasStrings':
        return {'value': clipboard != null};
    }
    return null;
  });
  const codec = StandardMessageCodec();
  for (final n in ['toggle', 'isEnabled']) {
    m.setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.$n', (msg) async {
      if (n == 'toggle') wakelockCalls++;
      return codec.encodeMessage(<Object?>[n == 'isEnabled' ? false : null]);
    });
  }
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/local_auth'), (call) async {
    switch (call.method) {
      case 'isDeviceSupported':
      case 'deviceSupportsBiometrics':
      case 'authenticate':
        return false;
      case 'getAvailableBiometrics':
      case 'getEnrolledBiometrics':
        return <String>[];
    }
    return null;
  });
}

/// Wipes all persisted state and reloads the store, like a fresh install.
Future<void> freshStore() async {
  for (final s in List.of(Sessions.i.list)) {
    Sessions.i.close(s);
  }
  // The tests assert on Persian strings: start every test with the UI in fa
  // (the test device locale is en_US, which would otherwise pick English).
  SharedPreferences.setMockInitialValues({'settings': '{"language":"fa"}'});
  secure.clear();
  clipboard = null;
  wakelockCalls = 0;
  await reloadStore();
  // keep-alive timers would outlive fake-async tests
  Store.i.settings.keepAlive = 0;
  await Store.i.saveSettings();
}

/// Simulates an app relaunch: drops every in-memory value and reads back what was persisted.
Future<void> reloadStore() async {
  SharedPreferences.resetStatic();
  Store.i.settings.load(AppSettings().toJson());
  Store.i.hosts = [];
  Store.i.snippets = [];
  Store.i.knownHosts = {};
  await Store.i.init();
}

Future<void> setSize(WidgetTester t, Size logical, {double dpr = 3, double keyboard = 0}) async {
  t.view.physicalSize = logical * dpr;
  t.view.devicePixelRatio = dpr;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
  addTearDown(t.view.reset);
}

/// Starts the app from scratch (new LockGate etc).
Future<void> launch(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(const MTermApp());
  await t.pumpAndSettle();
}

/// Lets real I/O (sockets) run, pumping frames between, until [cond] holds.
Future<void> waitFor(WidgetTester t, bool Function() cond, {int seconds = 15, String? reason}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump();
    if (cond()) {
      await t.pump(); // state may have changed in the microtasks flushed by the last pump
      return;
    }
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  }
  await t.pump();
  if (!cond()) fail('timed out waiting: ${reason ?? ''}');
}

/// Real-time pause while letting socket callbacks run.
Future<void> settleIo(WidgetTester t, [int ms = 300]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump();
  }
}

String bufferOf(TermSession s) => s.terminal.buffer.getText();

/// Number of times [needle] appears in [hay].
int count(String hay, String needle) => needle.allMatches(hay).length;

/// Closes every session and drains socket callbacks so no timers/IO leak past the test.
Future<void> closeAll(WidgetTester t) async {
  for (final s in List.of(Sessions.i.list)) {
    Sessions.i.close(s);
  }
  await settleIo(t, 300);
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

/// A syntactically valid-looking key for form tests when the real one is absent (CI).
String testKey() => File(keyPath).existsSync()
    ? File(keyPath).readAsStringSync()
    : '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n';

Finder fieldLabeled(String label) => find.widgetWithText(TextFormField, label);

/// Scrolls the host form down to its bottom Save button and taps it (the form
/// is longer than a phone screen since groups, jump host and forwarding).
Future<void> tapSave(WidgetTester t) async {
  final btn = find.widgetWithText(FilledButton, 'ذخیره');
  if (btn.evaluate().isEmpty) {
    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await t.scrollUntilVisible(btn, 300, scrollable: list.last);
  }
  await t.ensureVisible(btn);
  await t.pumpAndSettle();
  await t.tap(btn);
}
