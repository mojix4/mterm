// Real-server tests for the agentless server tools, broadcast, SFTP safety and
// the per-host SOCKS5 proxy, against the local OpenSSH test server on
// 127.0.0.1:2222 (mtest / Pass1234). Everything skips when it is not running (CI).
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/broadcast_screen.dart';
import 'package:mterm/screens/files_screen.dart';
import 'package:mterm/screens/tools_screen.dart';
import 'package:mterm/server_tools.dart';
import 'package:mterm/session.dart';
import 'package:mterm/sftp_ops.dart';
import 'package:mterm/ssh_connect.dart';
import 'package:mterm/store.dart';
import 'package:mterm/tool_conn.dart';

import 'server_tools_test.dart' show FakeSocks;
import 'support.dart';

Future<bool> trustAll(String type, String fp, String? old) async => true;

Future<Host> saved({String id = 'h', String label = '', String proxyHost = '', int proxyPort = 1080,
    String proxyUser = '', String proxyPass = ''}) async {
  final h = Host(
      id: id,
      label: label.isEmpty ? 'local-$id' : label,
      host: sshHost,
      port: sshPort,
      user: sshUser,
      proxyHost: proxyHost,
      proxyPort: proxyPort,
      proxyUser: proxyUser);
  await Store.i.upsertHost(h, HostSecret(password: sshPass, proxyPassword: proxyPass));
  return h;
}

Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
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

  test('dashboard block: cpu, memory, disks, network, load, uptime, os', () async {
    final h = await saved();
    final c = ToolConn(h, hostKeyPrompt: trustAll);
    addTearDown(c.close);
    final r1 = await c.run(statusCommand);
    expect(r1.ok, isTrue, reason: r1.output);
    final a = parseStatus(r1.output);
    expect(a.cpu, isNotNull);
    expect(a.cpus, greaterThan(0));
    expect(a.mem!.total, greaterThan(0));
    expect(a.disks, isNotEmpty);
    expect(a.net, isNotNull);
    expect(a.load, hasLength(3));
    expect(a.uptime, greaterThan(0));
    expect(a.os, isNotEmpty);
    expect(a.kernel, startsWith('Linux'));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final b = parseStatus((await c.run(statusCommand)).output);
    final cpu = b.cpu!.usageSince(a.cpu!);
    expect(cpu, inInclusiveRange(0, 100));
    expect(netRate(a, b), isNotNull);
  }, skip: skip);

  test('reuses an open terminal session, otherwise opens and closes its own', () async {
    final h = await saved();
    final s = Sessions.i.open(h);
    await s.connect(trustAll);
    expect(s.status, SessStatus.connected, reason: s.error);
    final shared = ToolConn(h, hostKeyPrompt: (a, b, c) async => fail('no second login expected'));
    expect(shared.sharesSession, isTrue);
    expect((await shared.run('echo shared')).output.trim(), 'shared');
    expect(await shared.client(), same(s.client));
    shared.close();
    expect(s.client, isNotNull, reason: 'closing the tool does not close the terminal');
    Sessions.i.close(s);

    final own = ToolConn(h, hostKeyPrompt: trustAll);
    expect(own.sharesSession, isFalse);
    final r = await own.run('echo own; exit 3');
    expect(r.output.trim(), 'own');
    expect(r.exitCode, 3);
    final cl = await own.client();
    own.close();
    await cl.done.timeout(const Duration(seconds: 5));
    expect(cl.isClosed, isTrue);
  }, skip: skip);

  test('ports, processes, kill and the security audit on a real server', () async {
    final h = await saved();
    final c = ToolConn(h, hostKeyPrompt: trustAll);
    addTearDown(c.close);
    final ports = parseSs((await c.run(portsCommand)).output);
    expect(ports.any((p) => p.proto == 'tcp' && p.port == sshPort && p.address == '127.0.0.1'), isTrue,
        reason: ports.map((p) => '${p.proto}:${p.address}:${p.port}').join(' '));

    final pid = int.parse((await c.run('nohup sleep 300 >/dev/null 2>&1 & echo \$!')).output.trim());
    var procs = parsePs((await c.run(psCommand)).output);
    expect(procs.any((p) => p.pid == pid && p.command == 'sleep'), isTrue);
    expect(procs.any((p) => p.pid == 1), isTrue);
    final k = await c.run(killCommand(pid));
    expect(k.ok, isTrue, reason: k.output);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    procs = parsePs((await c.run(psCommand)).output);
    expect(procs.any((p) => p.pid == pid), isFalse);

    final audit = parseAudit((await c.run(auditCommand, timeout: const Duration(seconds: 60))).output, sshPort: sshPort);
    expect(audit.map((e) => e.id), ['rootLogin', 'passwordAuth', 'firewall', 'fail2ban', 'updates']);

    final svc = parseServices((await c.run(servicesCommand)).output);
    expect(svc.hasDocker, Process.runSync('sh', ['-c', 'command -v docker']).exitCode == 0);
  }, skip: skip);

  testWidgets('tools screen shows live status from the real server', (t) async {
    final h = await saved();
    await t.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        home: ServerToolsScreen(host: h, keyPrompt: trustAll, pollEvery: const Duration(milliseconds: 700))));
    await waitFor(t, () => find.byKey(const ValueKey('dash-ram')).evaluate().isNotEmpty, reason: 'first poll');
    // the poll timer runs on the test's fake clock: advance it while real I/O happens
    final st = t.state<StatusTabState>(find.byType(StatusTab));
    for (var i = 0; i < 100 && st.cpu == null; i++) {
      await t.pump(const Duration(milliseconds: 350));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    }
    expect(st.cpu, isNotNull, reason: 'cpu after 2 polls');
    expect(st.polls, greaterThanOrEqualTo(2));
    expect(find.byKey(const ValueKey('dash-load')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await settleIo(t, 300);
    await t.pump(const Duration(seconds: 61)); // let a poll that was in flight time out
  }, skip: skip);

  testWidgets('broadcast runs one command on two servers', (t) async {
    await saved(id: 'b1', label: 'one');
    await saved(id: 'b2', label: 'two');
    await t.pumpWidget(MaterialApp(locale: const Locale('en'), home: BroadcastScreen(keyPrompt: trustAll)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('bc-all')));
    await t.enterText(find.byKey(const ValueKey('bc-command')), r'echo "hi $USER"; hostname >/dev/null');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('bc-run')));
    await t.pump();
    final st = t.state<BroadcastScreenState>(find.byType(BroadcastScreen));
    await waitFor(t, () => st.results.length == 2 && st.results.every((r) => !r.running), seconds: 30, reason: 'both done');
    for (final r in st.results) {
      expect(r.error, isNull);
      expect(r.exitCode, 0);
      expect(r.output.trim(), 'hi $sshUser');
    }
    await t.pumpWidget(const SizedBox());
    await settleIo(t, 300);
  }, skip: skip);

  test('SFTP: atomic save keeps permissions; critical paths are refused', () async {
    final h = await saved();
    final link = await openSavedHost(h, hostKeyPrompt: trustAll);
    addTearDown(link.close);
    final fs = await RemoteFs.open(link.client);
    final dir = joinRemote(await fs.home(), 'mterm_atomic');
    try {
      await fs.delete(dir, isDir: true);
    } catch (_) {}
    await fs.mkdir(dir);
    final f = joinRemote(dir, 'conf.txt');
    await fs.writeText(f, 'old content that is long\n');
    await link.client.run('chmod 640 $f');
    await fs.writeTextAtomic(f, 'new\n');
    expect(await fs.readText(f), 'new\n');
    final st = await fs.sftp.stat(f);
    expect(st.mode!.value & 0x1FF, 0x1A0, reason: 'mode 640 kept'); // 0640
    expect((await fs.list(dir)).map((e) => e.name), ['conf.txt'], reason: 'no temp file left');
    await fs.writeTextAtomic(joinRemote(dir, 'brand-new.txt'), 'x');
    expect(await fs.readText(joinRemote(dir, 'brand-new.txt')), 'x');
    // a failing save (read-only folder) leaves the original untouched and no temp file
    await link.client.run('chmod 555 $dir');
    await expectLater(fs.writeTextAtomic(f, 'never'), throwsA(isA<SftpStatusError>()));
    await link.client.run('chmod 755 $dir');
    expect(await fs.readText(f), 'new\n');
    expect((await fs.list(dir)).length, 2);

    for (final p in ['/', '/etc', '/etc/passwd', '/usr/', '/root']) {
      await expectLater(fs.delete(p, isDir: true), throwsA(isA<CriticalPathError>()), reason: p);
      await expectLater(fs.rename(p, '/tmp/x'), throwsA(isA<CriticalPathError>()), reason: p);
    }
    expect((await fs.list('/etc')).isNotEmpty, isTrue);
    await fs.delete(dir, isDir: true);
    fs.close();
  }, skip: skip);

  testWidgets('files screen blocks deleting /etc with a message', (t) async {
    final h = await saved();
    await t.pumpWidget(MaterialApp(locale: const Locale('en'), home: SftpBrowser(host: h, keyPrompt: trustAll)));
    await waitFor(t, () => t.state<SftpBrowserState>(find.byType(SftpBrowser)).path.isNotEmpty, reason: 'connected');
    final st = t.state<SftpBrowserState>(find.byType(SftpBrowser));
    st.cd('/');
    await waitFor(t, () => find.byKey(const ValueKey('sftp-etc')).evaluate().isNotEmpty, reason: 'root listing');
    await t.tap(find.descendant(of: find.byKey(const ValueKey('sftp-etc')), matching: find.byIcon(Icons.more_vert)));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text("For safety, /etc can't be deleted or renamed here."), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing, reason: 'no confirm dialog at all');
    await t.pumpWidget(const SizedBox());
    await settleIo(t, 300);
  }, skip: skip);

  test('SOCKS5 proxy: through the app\'s own SOCKS forward, and with username/password', () async {
    // a SOCKS5 proxy whose connections leave from the server (dynamic forward of a session)
    final dp = await freePort();
    final base = await saved(id: 'base');
    final s = Sessions.i.open(base);
    await s.connect(trustAll);
    expect(s.status, SessStatus.connected, reason: s.error);
    expect(await s.startForward(ForwardRule(id: 'D', type: 'dynamic', localPort: dp)), isTrue);

    final viaProxy = await saved(id: 'px', proxyHost: '127.0.0.1', proxyPort: dp);
    final link = await openSavedHost(viaProxy, hostKeyPrompt: trustAll);
    expect((await link.client.run('echo via-proxy')), isNotEmpty);
    link.close();
    // Tools / terminal use the same connection code
    final c = ToolConn(viaProxy, hostKeyPrompt: trustAll);
    expect((await c.run('echo tools-via-proxy')).output.trim(), 'tools-via-proxy');
    c.close();
    final term = Sessions.i.open(viaProxy);
    await term.connect(trustAll);
    expect(term.status, SessStatus.connected, reason: term.error);
    Sessions.i.close(term);
    Sessions.i.close(s);

    // username/password proxy
    final fake = await FakeSocks.start(user: 'puser', pass: 'ppass');
    addTearDown(fake.close);
    final auth = await saved(id: 'pa', proxyHost: '127.0.0.1', proxyPort: fake.port, proxyUser: 'puser', proxyPass: 'ppass');
    final l2 = await openSavedHost(auth, hostKeyPrompt: trustAll);
    expect(fake.lastTarget, '$sshHost:$sshPort');
    l2.close();
    final bad = await saved(id: 'pb', proxyHost: '127.0.0.1', proxyPort: fake.port, proxyUser: 'puser', proxyPass: 'nope');
    final err = Sessions.i.open(bad);
    await err.connect(trustAll);
    expect(err.status, SessStatus.failed);
    expect(err.errorKey, 'errProxy');
    Sessions.i.close(err);
  }, skip: skip);
}
