// UI of the server Tools screen (status, processes, services, ports,
// security), the multi-server broadcast, privacy mode and the proxy fields,
// driven by a fake SSH exec (no server needed, runs in CI).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/backup.dart';
import 'package:mterm/l10n.dart';
import 'package:mterm/main.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/broadcast_screen.dart';
import 'package:mterm/screens/terminal_screen.dart';
import 'package:mterm/screens/tools_screen.dart';
import 'package:mterm/server_tools.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:mterm/tool_conn.dart';

import 'server_tools_test.dart' show statusSample;
import 'support.dart';

Finder svc(String name) => find.descendant(of: find.byKey(const ValueKey('svc-list')), matching: find.text(name));
final _vScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

const psSample = '''
      1 root      0.0  1.2 12100 systemd
    812 www-data 12.5  3.0 30500 nginx
    950 mysql     4.1 25.4 250880 mysqld
''';
const servicesSample = '''@@systemd
cron.service      loaded active running Regular background program processing daemon
nginx.service     loaded failed failed  A high performance web server and a reverse proxy server
ssh.service       loaded active running OpenBSD Secure Shell server
@@docker
DOCKER=yes
3f2a1b9c8d7e\tmarzban-marzban-1\tgozargah/marzban:latest\trunning\tUp 3 days
@@end
''';
const ssSample = '''Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
tcp   LISTEN 0      4096       0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=900,fd=3))
tcp   LISTEN 0      511      127.0.0.1:8080      0.0.0.0:*    users:(("nginx",pid=812,fd=6))
udp   UNCONN 0      0    127.0.0.53%lo:53        0.0.0.0:*
''';
const auditSample = 'ROOTLOGIN=yes\nPASSAUTH=yes\nUFW=inactive\nFIREWALLD=none\nINPUTRULES=0\nINPUTDROP=0\n'
    'F2B=none\nF2BACTIVE=inactive\nPKG=apt\nSECUPD=3\nAUDIT_END\n';

Future<bool> _trust(String t, String f, String? o) async => true;

/// Answers the tool commands with fixed text and records what was run.
class FakeConn extends ToolConn {
  FakeConn(Host h, {this.out}) : super(h, hostKeyPrompt: _trust);
  final String Function(String cmd)? out;
  final ran = <String>[];
  bool closed = false;

  @override
  Future<ExecResult> run(String cmd, {Duration timeout = const Duration(seconds: 30)}) async {
    ran.add(cmd);
    if (out != null) return ExecResult(out!(cmd), 0);
    if (cmd == statusCommand) return ExecResult(statusSample, 0);
    if (cmd == psCommand) return const ExecResult(psSample, 0);
    if (cmd == servicesCommand) return const ExecResult(servicesSample, 0);
    if (cmd == portsCommand) return const ExecResult(ssSample, 0);
    if (cmd == auditCommand) return const ExecResult(auditSample, 0);
    if (cmd.contains('journalctl') || cmd.contains('docker logs')) {
      return ExecResult(List.generate(60, (i) => 'Nov 28 10:00:$i host app[1]: a very long log line number $i ' * 2).join('\n'), 0);
    }
    return const ExecResult('', 0);
  }

  @override
  void close() => closed = true;
}

final host = Host(id: 'a', label: 'Germany', host: '203.0.113.7', user: 'root');

Future<FakeConn> openToolsScreen(WidgetTester t, {int tab = 0}) async {
  final c = FakeConn(host);
  navKey.currentState!.push(MaterialPageRoute(
      builder: (_) => ServerToolsScreen(host: host, conn: c, initialTab: tab, pollEvery: const Duration(seconds: 3))));
  await t.pumpAndSettle();
  return c;
}

Future<void> tab(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<void> english() async {
  Store.i.settings.language = 'en';
  await Store.i.saveSettings();
}

void main() {
  setUpAll(installMocks);
  setUp(freshStore);

  testWidgets('status tab shows live data, polls every 3 s and stops when closed', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await Store.i.upsertHost(host, HostSecret());
    await launch(t);
    final c = await openToolsScreen(t);
    expect(find.text('Ubuntu 22.04.4 LTS'), findsOneWidget);
    expect(find.text('Measuring…'), findsOneWidget);
    expect(find.text('58%'), findsOneWidget, reason: 'RAM used %');
    expect(find.text('/boot/efi'), findsOneWidget);
    expect(find.text('3d 4h'), findsOneWidget);
    expect(find.text('0.65  0.28  0.17'), findsOneWidget);
    final n = c.ran.where((x) => x == statusCommand).length;
    expect(n, 1);
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(c.ran.where((x) => x == statusCommand).length, 2);
    expect(find.text('0.0%'), findsOneWidget, reason: 'cpu from two samples');
    // other tabs don't poll
    await tab(t, 'tab-ports');
    final before = c.ran.where((x) => x == statusCommand).length;
    await t.pump(const Duration(seconds: 10));
    expect(c.ran.where((x) => x == statusCommand).length, before);
    // back to status: polling again; closing the screen stops it
    await tab(t, 'tab-status');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(c.closed, isTrue);
    final after = c.ran.length;
    await t.pump(const Duration(seconds: 10));
    expect(c.ran.length, after);
  });

  testWidgets('status polling pauses in the background', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await launch(t);
    final c = await openToolsScreen(t);
    final st = t.state<StatusTabState>(find.byType(StatusTab));
    expect(st.polling, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(st.polling, isFalse);
    final n = c.ran.length;
    await t.pump(const Duration(seconds: 9));
    expect(c.ran.length, n);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(st.polling, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('processes: sort, kill behind a confirm, PID 1 protected', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await launch(t);
    final c = await openToolsScreen(t, tab: 1);
    final names = find.descendant(of: find.byKey(const ValueKey('proc-list')), matching: find.byType(ListTile));
    String first() => (t.widget<ListTile>(names.first).key as ValueKey<String>).value;
    expect(first(), 'proc-812', reason: 'by CPU');
    await t.tap(find.text('RAM'));
    await t.pumpAndSettle();
    expect(first(), 'proc-950', reason: 'by memory');
    // PID 1
    await t.tap(find.byKey(const ValueKey('proc-1')));
    await t.pumpAndSettle();
    expect(find.text(S.forCode('en')['killProtected']), findsOneWidget);
    expect(find.byKey(const ValueKey('kill-term')), findsNothing);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    // SIGTERM, cancelled
    await t.tap(find.byKey(const ValueKey('proc-812')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kill-term')));
    await t.pumpAndSettle();
    expect(find.textContaining('SIGTERM to nginx (PID 812)'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.ran.any((x) => x.contains('kill')), isFalse);
    // SIGKILL, confirmed
    await t.tap(find.byKey(const ValueKey('proc-812')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kill-force')));
    await t.pumpAndSettle();
    await t.tap(find.text('Force kill').last);
    await t.pumpAndSettle();
    expect(c.ran.where((x) => x.contains('kill -s KILL 812')), hasLength(1));
    expect(c.ran.any((x) => x.contains('kill -s KILL 1 ') || x.contains('kill -s TERM 1 ')), isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('services: systemd + docker, restart confirm, logs viewer', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await launch(t);
    final c = await openToolsScreen(t, tab: 2);
    expect(find.text('nginx'), findsOneWidget);
    expect(find.text('cron'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('svc-running')));
    await t.pumpAndSettle();
    expect(find.text('nginx'), findsNothing, reason: 'failed unit hidden by Running filter');
    await t.tap(find.byKey(const ValueKey('svc-running')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('svc-filter')), 'ssh');
    await t.pumpAndSettle();
    expect(find.text('cron'), findsNothing);
    await t.tap(svc('ssh'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('svc-restart')));
    await t.pumpAndSettle();
    expect(find.text('Restart ssh.service? It is briefly unavailable.'), findsOneWidget);
    await t.tap(find.text('Restart').last);
    await t.pumpAndSettle();
    expect(c.ran.where((x) => x.contains('systemctl restart ssh.service')), hasLength(1));
    // docker
    await t.enterText(find.byKey(const ValueKey('svc-filter')), '');
    await t.tap(find.text('Docker'));
    await t.pumpAndSettle();
    expect(find.text('marzban-marzban-1'), findsOneWidget);
    await t.tap(find.text('marzban-marzban-1'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('svc-logs')));
    await t.pumpAndSettle();
    expect(c.ran.last, contains('docker logs --tail 200 3f2a1b9c8d7e'));
    final log = t.widget<SelectableText>(find.byKey(const ValueKey('log-text')));
    expect(log.data, contains('log line number 59'));
    expect(Directionality.of(t.element(find.byKey(const ValueKey('log-text')))), TextDirection.ltr);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('ports and security check', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await launch(t);
    final c = await openToolsScreen(t, tab: 3);
    expect(find.text('3 listening'), findsOneWidget);
    expect(find.text('0.0.0.0 · sshd (900)'), findsOneWidget);
    expect(find.text('127.0.0.53'), findsOneWidget);
    await tab(t, 'tab-security');
    expect(c.ran.contains(auditCommand), isFalse, reason: 'runs only on tap');
    await t.tap(find.byKey(const ValueKey('audit-run')));
    await t.pumpAndSettle();
    expect(c.ran.where((x) => x == auditCommand), hasLength(1));
    for (final id in ['rootLogin', 'passwordAuth', 'firewall', 'fail2ban', 'updates']) {
      final f = find.byKey(ValueKey('audit-$id'));
      if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: _vScroll.last);
      expect(f, findsOneWidget, reason: id);
    }
    final copy = find.byKey(const ValueKey('audit-copy-firewall'));
    await t.ensureVisible(copy);
    await t.tap(copy);
    await t.pumpAndSettle();
    expect(clipboard, contains('ufw allow 22/tcp'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Tools entry from the servers menu and the terminal menu', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await Store.i.upsertHost(host, HostSecret());
    await launch(t);
    await t.tap(find.byIcon(Icons.more_vert).first);
    await t.pumpAndSettle();
    expect(find.text('Tools'), findsOneWidget);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    final s = Sessions.i.open(host)..debugSetStatus(SessStatus.closed);
    navKey.currentState!.push(MaterialPageRoute(builder: (_) => TerminalScreen(session: s)));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert).last);
    await t.pumpAndSettle();
    expect(find.text('Tools'), findsOneWidget);
    Sessions.i.close(s);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('broadcast: run on two servers, warn before destructive commands', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    final b = Host(id: 'b', label: 'Iran', host: '198.51.100.2', user: 'ubuntu');
    await Store.i.upsertHost(host, HostSecret());
    await Store.i.upsertHost(b, HostSecret());
    final conns = <String, FakeConn>{};
    await launch(t);
    expect(find.byKey(const ValueKey('broadcast-open')), findsOneWidget);
    navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => BroadcastScreen(
            connFor: (h) => conns[h.id] = FakeConn(h, out: (cmd) => 'out of ${h.label}: $cmd'))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('bc-all')));
    await t.enterText(find.byKey(const ValueKey('bc-command')), 'uptime');
    await t.pumpAndSettle();
    expect(find.text('Run on 2 servers'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bc-run')));
    await t.pumpAndSettle();
    expect(conns.keys.toSet(), {'a', 'b'});
    await t.scrollUntilVisible(find.byKey(const ValueKey('bc-output-b')), 200, scrollable: _vScroll.last);
    expect(t.widget<SelectableText>(find.byKey(const ValueKey('bc-output-a'))).data, 'out of Germany: uptime');
    expect(t.widget<SelectableText>(find.byKey(const ValueKey('bc-output-b'))).data, 'out of Iran: uptime');
    await t.tap(find.byKey(const ValueKey('bc-copy-b')));
    await t.pumpAndSettle();
    expect(clipboard, 'out of Iran: uptime');
    // destructive: asks first, cancel runs nothing
    await t.scrollUntilVisible(find.byKey(const ValueKey('bc-command')), -200, scrollable: _vScroll.last);
    await t.enterText(find.byKey(const ValueKey('bc-command')), 'sudo reboot');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('bc-run')));
    await t.tap(find.byKey(const ValueKey('bc-run')));
    await t.pumpAndSettle();
    expect(find.text('Dangerous command'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(conns['a']!.ran, ['uptime']);
    await t.pumpWidget(const SizedBox());
    expect(conns['a']!.closed, isTrue);
  });

  testWidgets('privacy mode hides addresses in the list and is in Settings', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await Store.i.upsertHost(Host(id: 'p', label: '', host: '203.0.113.7', user: 'root'), HostSecret());
    await launch(t);
    expect(find.text('203.0.113.7'), findsOneWidget);
    expect(find.text('ssh root@203.0.113.7'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('privacy-toggle')));
    await t.pumpAndSettle();
    expect(Store.i.settings.privacy, isTrue);
    expect(find.textContaining('203.0.113.7'), findsNothing);
    expect(find.text('ssh •••@•••.•••.•••.•••'), findsOneWidget);
    await reloadStore();
    expect(Store.i.settings.privacy, isTrue, reason: 'saved');
    await t.tap(find.byType(NavigationDestination).at(3));
    await t.pumpAndSettle();
    final sw = find.byKey(const ValueKey('privacy-switch'));
    await t.scrollUntilVisible(sw, 200, scrollable: _vScroll.last);
    await t.drag(_vScroll.last, const Offset(0, -250));
    await t.pumpAndSettle();
    await t.tap(sw);
    await t.pumpAndSettle();
    expect(Store.i.settings.privacy, isFalse);
    await t.tap(find.byType(NavigationDestination).at(0));
    await t.pumpAndSettle();
    expect(find.text('ssh root@203.0.113.7'), findsOneWidget);
  });

  testWidgets('host form: SOCKS5 proxy saved with its password as a secret', (t) async {
    await setSize(t, const Size(390, 844));
    await english();
    await launch(t);
    await t.tap(find.byKey(const ValueKey('fab-add-host')));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Server address'), '203.0.113.7');
    await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'pw');
    final ph = find.byKey(const ValueKey('proxy-host-field'));
    await t.scrollUntilVisible(ph, 200, scrollable: _vScroll.last);
    await t.enterText(ph, '10.0.0.9');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('proxy-port-field')), '9050');
    await t.enterText(find.byKey(const ValueKey('proxy-user-field')), 'me');
    await t.enterText(find.byKey(const ValueKey('proxy-pass-field')), 'secret');
    await t.tap(find.text('Save').first);
    await t.pumpAndSettle();
    final h = Store.i.hosts.single;
    expect(h.proxyHost, '10.0.0.9');
    expect(h.proxyPort, 9050);
    expect(h.proxyUser, 'me');
    expect(secure['pxp_${h.id}'], 'secret');
    expect((await Store.i.secret(h.id)).proxyPassword, 'secret');
    await Store.i.deleteHost(h);
    expect(secure.containsKey('pxp_${h.id}'), isFalse);
  });

  test('encrypted backup carries the proxy settings and password', () async {
    await Store.i.upsertHost(
        Host(id: 'x', label: 'x', host: 'h', user: 'u', proxyHost: '10.0.0.9', proxyPort: 9050, proxyUser: 'me'),
        HostSecret(password: 'pw', proxyPassword: 'pxsecret'));
    final j = await collectBackup();
    expect((j['secrets'] as Map)['x']['pxp'], 'pxsecret');
    final file = await createBackup('backup-pass');
    await freshStore();
    expect(Store.i.hosts, isEmpty);
    await applyBackup(await readBackup(file, 'backup-pass'), replace: true);
    final h = Store.i.hosts.single;
    expect(h.proxyHost, '10.0.0.9');
    expect(h.proxyPort, 9050);
    expect(h.proxyUser, 'me');
    expect((await Store.i.secret('x')).proxyPassword, 'pxsecret');
  });

  group('tools and broadcast fit a 360x700 phone in every language', () {
    for (final lang in languageCodes) {
      testWidgets(lang, (t) async {
        await setSize(t, const Size(360, 700));
        Store.i.settings.language = lang;
        await Store.i.saveSettings();
        final l = S.forCode(lang);
        await Store.i.upsertHost(host, HostSecret());
        await Store.i.upsertHost(Host(id: 'b', label: 'b', host: 'b.example.com', user: 'u'), HostSecret());
        await launch(t);
        final c = await openToolsScreen(t);
        await t.pump(const Duration(seconds: 3));
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, -3000));
        await t.pumpAndSettle();
        await tab(t, 'tab-procs');
        await t.tap(find.byKey(const ValueKey('proc-812')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('kill-force')));
        await t.pumpAndSettle();
        await t.tap(find.text(l['cancel']).last);
        await t.pumpAndSettle();
        await tab(t, 'tab-services');
        await t.tap(find.text(l['svcRunningOnly']));
        await t.pumpAndSettle();
        await t.tap(svc('cron'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('svc-stop')));
        await t.pumpAndSettle();
        await t.tap(find.text(l['cancel']).last);
        await t.pumpAndSettle();
        await t.tap(svc('ssh'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('svc-logs')));
        await t.pumpAndSettle();
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        await tab(t, 'tab-ports');
        await tab(t, 'tab-security');
        await t.tap(find.byKey(const ValueKey('audit-run')));
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, -4000));
        await t.pumpAndSettle();
        expect(c.ran.contains(auditCommand), isTrue);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        // broadcast with the danger dialog
        navKey.currentState!.push(MaterialPageRoute(builder: (_) => BroadcastScreen(connFor: (h) => FakeConn(h))));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('bc-all')));
        await t.enterText(find.byKey(const ValueKey('bc-command')), 'rm -rf /tmp/x');
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('bc-run')));
        await t.tap(find.byKey(const ValueKey('bc-run')));
        await t.pumpAndSettle();
        await t.tap(find.text(l['bcRunAnyway']));
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, -3000));
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
      });
    }
  });
}
