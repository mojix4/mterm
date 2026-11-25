// Real-server tests for SFTP, port forwarding, startup command, key install,
// jump host and session logs, against the local OpenSSH test server on
// 127.0.0.1:2222 (mtest / Pass1234). Everything skips when it is not running (CI).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/keys.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/files_screen.dart';
import 'package:mterm/session.dart';
import 'package:mterm/session_log.dart';
import 'package:mterm/sftp_ops.dart';
import 'package:mterm/ssh_connect.dart';
import 'package:mterm/store.dart';

import 'support.dart';

Future<bool> trustAll(String type, String fp, String? old) async => true;

Future<Host> saved({String id = 'h', String? jump, String startup = '', List<ForwardRule>? fwd}) async {
  final h = Host(
      id: id,
      label: 'local-$id',
      host: sshHost,
      port: sshPort,
      user: sshUser,
      jumpHostId: jump,
      startupCmd: startup,
      forwards: fwd);
  await Store.i.upsertHost(h, HostSecret(password: sshPass));
  return h;
}

Future<TermSession> connected(Host h) async {
  final s = Sessions.i.open(h);
  await s.connect(trustAll);
  expect(s.status, SessStatus.connected, reason: s.error);
  return s;
}

Future<void> until(bool Function() cond, {int seconds = 10, String? reason}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out: ${reason ?? ''}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

/// Reads the first line the SSH server sends ("SSH-2.0-…") through [sock].
Future<String> banner(Socket sock, {List<int> skip = const []}) async {
  final buf = <int>[];
  final done = Completer<String>();
  sock.listen((d) {
    buf.addAll(d);
    final text = latin1.decode(buf);
    if (text.contains('\n') && !done.isCompleted) done.complete(text);
  }, onDone: () {
    if (!done.isCompleted) done.complete(latin1.decode(buf));
  });
  return done.future.timeout(const Duration(seconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installMocks);
  setUp(freshStore);
  tearDown(() {
    for (final s in List.of(Sessions.i.list)) {
      Sessions.i.close(s);
    }
  });
  final skip = !sshUp;

  test('sftp: list, upload, download, edit text, mkdir, rename, delete', () async {
    final h = await saved();
    final link = await openSavedHost(h, hostKeyPrompt: trustAll);
    addTearDown(link.close);
    final fs = await RemoteFs.open(link.client);
    final home = await fs.home();
    expect(home, startsWith('/'));
    final dir = joinRemote(home, 'mterm_sftp_test');
    try {
      await fs.delete(dir, isDir: true);
    } catch (_) {}
    await fs.mkdir(dir);
    expect((await fs.list(home)).any((e) => e.name == 'mterm_sftp_test' && e.isDir), isTrue);

    // upload a local file (streamed) and read it back
    final tmp = await Directory.systemTemp.createTemp('mterm_up');
    addTearDown(() => tmp.delete(recursive: true));
    final local = File('${tmp.path}/up.bin');
    final data = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    await local.writeAsBytes(data);
    await fs.uploadFile(local, joinRemote(dir, 'up.bin'));
    expect(await fs.readBytes(joinRemote(dir, 'up.bin')), data);
    final down = File('${tmp.path}/down.bin');
    await fs.downloadToFile(joinRemote(dir, 'up.bin'), down);
    expect(down.readAsBytesSync(), data);

    // text editor path
    await fs.writeText(joinRemote(dir, 'a.txt'), 'سلام\nline2\n');
    expect(await fs.readText(joinRemote(dir, 'a.txt')), 'سلام\nline2\n');
    await fs.writeText(joinRemote(dir, 'a.txt'), 'short');
    expect(await fs.readText(joinRemote(dir, 'a.txt')), 'short', reason: 'save truncates');
    await expectLater(fs.readText(joinRemote(dir, 'up.bin')), throwsA(isA<NotTextError>()));

    // rename + nested delete
    await fs.rename(joinRemote(dir, 'a.txt'), joinRemote(dir, 'b.txt'));
    await fs.mkdir(joinRemote(dir, 'sub'));
    await fs.writeText(joinRemote(dir, 'sub/c.txt'), 'x');
    final names = (await fs.list(dir)).map((e) => e.name).toList();
    expect(names, ['sub', 'b.txt', 'up.bin'], reason: 'folders first, then files by name');
    await fs.delete(dir, isDir: true);
    expect((await fs.list(home)).any((e) => e.name == 'mterm_sftp_test'), isFalse);
    fs.close();
  }, skip: skip);

  testWidgets('files screen: browse home, open folder, go up', (t) async {
    final h = await saved();
    await t.runAsync(() async {
      final link = await openSavedHost(h, hostKeyPrompt: trustAll);
      final fs = await RemoteFs.open(link.client);
      final d = joinRemote(await fs.home(), 'mterm_ui_dir');
      try {
        await fs.delete(d, isDir: true);
      } catch (_) {}
      await fs.mkdir(d);
      await fs.writeText(joinRemote(d, 'inside.txt'), 'hi');
      fs.close();
      link.close();
    });
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      home: SftpBrowser(host: h, keyPrompt: trustAll),
    ));
    await waitFor(t, () => find.byKey(const ValueKey('sftp-mterm_ui_dir')).evaluate().isNotEmpty, reason: 'listing');
    await t.tap(find.byKey(const ValueKey('sftp-mterm_ui_dir')));
    await waitFor(t, () => find.text('inside.txt').evaluate().isNotEmpty, reason: 'folder contents');
    await t.tap(find.byKey(const ValueKey('sftp-up')));
    await waitFor(t, () => find.byKey(const ValueKey('sftp-mterm_ui_dir')).evaluate().isNotEmpty, reason: 'back up');
    await t.pumpWidget(const SizedBox());
    await settleIo(t, 200);
    // clean up on a connection of the real zone (the widget's one lives in the test's fake zone)
    await t.runAsync(() async {
      final link = await openSavedHost(h, hostKeyPrompt: trustAll);
      final fs = await RemoteFs.open(link.client);
      await fs.delete(joinRemote(await fs.home(), 'mterm_ui_dir'), isDir: true);
      fs.close();
      link.close();
    });
  }, skip: skip);

  test('port forwarding: local rule and SOCKS5 reach the server through the session', () async {
    final lp = await freePort(), dp = await freePort();
    final h = await saved(fwd: [
      ForwardRule(id: 'L', localPort: lp, remoteHost: '127.0.0.1', remotePort: sshPort),
      ForwardRule(id: 'D', type: 'dynamic', localPort: dp),
    ]);
    final s = await connected(h);
    await until(() => s.forwards.activeCount == 2, reason: 'rules start on connect ${s.forwards.errors}');
    expect(s.forwards.boundPort(h.forwards[0]), lp);

    // local: 127.0.0.1:lp -> server's 127.0.0.1:2222 (an SSH banner comes back)
    final a = await Socket.connect(InternetAddress.loopbackIPv4, lp);
    expect(await banner(a), startsWith('SSH-2.0-'));
    a.destroy();

    // SOCKS5 no-auth CONNECT to domain "localhost":2222
    final b = await Socket.connect(InternetAddress.loopbackIPv4, dp);
    final replies = StreamIterator(b);
    final buf = <int>[];
    Future<List<int>> read(int n) async {
      while (buf.length < n) {
        if (!await replies.moveNext().timeout(const Duration(seconds: 10))) break;
        buf.addAll(replies.current);
      }
      final out = buf.sublist(0, n);
      buf.removeRange(0, n);
      return out;
    }

    b.add([5, 1, 0]);
    expect(await read(2), [5, 0]);
    final host = ascii.encode('localhost');
    b.add([5, 1, 0, 3, host.length, ...host, sshPort >> 8, sshPort & 0xff]);
    final rep = await read(10);
    expect(rep.sublist(0, 2), [5, 0], reason: 'CONNECT succeeded');
    while (!latin1.decode(buf).contains('\n')) {
      if (!await replies.moveNext().timeout(const Duration(seconds: 10))) break;
      buf.addAll(replies.current);
    }
    expect(latin1.decode(buf), startsWith('SSH-2.0-'));
    b.destroy();

    // toggle off: the port is free again
    await s.forwards.stop(h.forwards[0]);
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, lp), throwsA(isA<SocketException>()));
    expect(await s.startForward(h.forwards[0]), isTrue);
    // closing the session stops everything
    Sessions.i.close(s);
    await until(() => s.forwards.activeCount == 0);
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, dp), throwsA(isA<SocketException>()));
  }, skip: skip);

  test('a busy local port shows an error instead of crashing', () async {
    final busy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(busy.close);
    final h = await saved(fwd: [ForwardRule(id: 'L', localPort: busy.port, remoteHost: '127.0.0.1', remotePort: 22)]);
    final s = await connected(h);
    await until(() => s.forwards.errors.isNotEmpty, reason: 'bind error');
    expect(s.forwards.activeCount, 0);
  }, skip: skip);

  test('startup command runs once after login', () async {
    final h = await saved(startup: r'echo startup_$((40+2))');
    final s = await connected(h);
    await until(() => RegExp(r'^startup_42\s*$', multiLine: true).hasMatch(bufferOf(s)),
        reason: 'startup output\n${bufferOf(s)}');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(RegExp(r'^startup_42\s*$', multiLine: true).allMatches(bufferOf(s)), hasLength(1));
  }, skip: skip);

  test('install public key, then log in with it (no duplicates)', () async {
    final h = await saved();
    final s = await connected(h);
    final g = generateEd25519(comment: 'mterm-test-${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(() async {
      // remove the test key again
      final c = await openSavedHost(h, hostKeyPrompt: trustAll);
      final core = g.publicLine.split(' ')[1];
      await c.client.run("sed -i '\\#$core#d' ~/.ssh/authorized_keys");
      c.close();
    });
    expect(await s.installPublicKey(g.publicLine), isTrue);
    expect(await s.installPublicKey(g.publicLine), isFalse);
    final count = await s.exec('grep -c "${g.publicLine.split(' ')[1]}" ~/.ssh/authorized_keys');
    expect(count?.trim(), '1');
    final perms = await s.exec('stat -c %a ~/.ssh ~/.ssh/authorized_keys');
    expect(perms?.trim().split('\n'), ['700', '600']);

    final kh = Host(id: 'k', label: 'key', host: sshHost, port: sshPort, user: sshUser, auth: 'key');
    await Store.i.upsertHost(kh, HostSecret(privateKey: g.privatePem));
    final ks = await connected(kh);
    expect(ks.status, SessStatus.connected);
  }, skip: skip);

  test('jump host: terminal and SFTP go through another saved server', () async {
    final jump = await saved(id: 'jump');
    // the target is only "reachable" from the jump host: 127.0.0.1 as the jump sees it
    final target = await saved(id: 'target', jump: jump.id);
    final s = await connected(target);
    s.run(r'echo via_$((6*7))');
    await until(() => RegExp(r'^via_42\s*$', multiLine: true).hasMatch(bufferOf(s)), reason: bufferOf(s));
    final link = await openSavedHost(target, hostKeyPrompt: trustAll);
    expect(link.via, isNotNull);
    final fs = await RemoteFs.open(link.client);
    expect(await fs.home(), startsWith('/'));
    fs.close();
    link.close();

    // missing jump host -> readable error, no hang
    final broken = await saved(id: 'broken', jump: 'deleted-id');
    final b = Sessions.i.open(broken);
    await b.connect(trustAll);
    expect(b.status, SessStatus.failed);
    expect(b.errorKey, 'errJumpMissing');

    // jump host with a wrong password -> reported as a jump host error
    await Store.i.upsertHost(jump, HostSecret(password: 'wrong'));
    final c = Sessions.i.open(target);
    await c.connect(trustAll);
    expect(c.status, SessStatus.failed);
    expect(c.errorKey, 'errJump');
  }, skip: skip);

  test('session log records plain output when enabled', () async {
    final tmp = await Directory.systemTemp.createTemp('mterm_slog');
    addTearDown(() => tmp.delete(recursive: true));
    appDocsDir = () async => tmp;
    Store.i.settings.logSessions = true;
    final h = await saved();
    final s = await connected(h);
    s.run(r"printf '\033[31mred_%s\033[0m\n' $((1+1))");
    await until(() => bufferOf(s).contains('red_2'));
    final file = s.log!.file;
    Sessions.i.close(s);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final text = file.readAsStringSync();
    expect(text, contains('red_2'));
    expect(text, isNot(contains('\x1b')));
    expect((await listLogs()).single.path, file.path);
  }, skip: skip);
}
