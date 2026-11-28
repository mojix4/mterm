// Parsers of the agentless server tools, fed with fixed sample output from a
// typical Ubuntu VPS, plus the SOCKS5 client against a tiny in-test proxy,
// SFTP critical-path rules and privacy masking. No SSH server needed (CI).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/models.dart';
import 'package:mterm/privacy.dart';
import 'package:mterm/server_tools.dart';
import 'package:mterm/sftp_ops.dart';
import 'package:mterm/socks5.dart';

const statusSample = '''
@@stat
cpu  18233 120 2996 654723 35482 0 149 63 0 0
@@cpus
1
@@mem
MemTotal:         985900 kB
MemFree:          101200 kB
MemAvailable:     412300 kB
Buffers:           20100 kB
Cached:           300000 kB
SwapTotal:       1048572 kB
SwapFree:         786432 kB
@@df
Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/vda1         25215872 10512400  14687088      42% /
/dev/vda15          106858     6186    100673       6% /boot/efi
tmpfs               98588        0     98588       0% /run/user/0
/dev/loop0           65536    65536         0     100% /snap/core20/1974
@@net
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:  662000      12    0    0    0     0          0         0   662000      12    0    0    0     0       0          0
  eth0: 1000000   84950    0    0    0     0          0         0  500000   58530    0    0    0     0       0          0
  eth1:   20000     100    0    0    0     0          0         0   10000     100    0    0    0     0       0          0
@@load
0.65 0.28 0.17 1/106 6162
@@up
273600.55 6563.48
@@os
PRETTY_NAME="Ubuntu 22.04.4 LTS"
NAME="Ubuntu"
VERSION="22.04.4 LTS (Jammy Jellyfish)"
@@kernel
Linux 5.15.0-105-generic x86_64
@@end
''';

void main() {
  group('dashboard', () {
    test('sections and full status sample', () {
      final st = parseStatus(statusSample);
      expect(st.cpus, 1);
      expect(st.cpu!.total, 18233 + 120 + 2996 + 654723 + 35482 + 0 + 149 + 63);
      expect(st.cpu!.idle, 654723 + 35482);
      expect(st.mem!.total, 985900);
      expect(st.mem!.used, 985900 - 412300);
      expect(st.mem!.swapUsed, 1048572 - 786432);
      expect(st.mem!.usedPct, closeTo(58.2, 0.1));
      expect(st.disks.map((d) => d.mount), ['/', '/boot/efi'], reason: 'tmpfs, /run and snap loops dropped');
      expect(st.disks.first.usedPct, closeTo(41.7, 0.1));
      expect(st.net!.rx, 1020000, reason: 'lo excluded, other interfaces summed');
      expect(st.net!.tx, 510000);
      expect(st.load, [0.65, 0.28, 0.17]);
      expect(st.uptime, 273600.55);
      expect(formatUptime(st.uptime!), '3d 4h');
      expect(st.os, 'Ubuntu 22.04.4 LTS');
      expect(st.kernel, 'Linux 5.15.0-105-generic x86_64');
    });

    test('cpu usage and network rate between two samples', () {
      const a = CpuTimes(900, 1000), b = CpuTimes(1050, 1200);
      expect(b.usageSince(a), closeTo(25, 0.001)); // 200 ticks, 150 idle
      expect(a.usageSince(a), 0);
      final s1 = parseStatus(statusSample);
      final s2 = parseStatus(statusSample
          .replaceFirst('eth0: 1000000', 'eth0: 1300000')
          .replaceFirst(' 500000   58530', ' 530000   58530')
          .replaceFirst('273600.55', '273603.55'));
      final r = netRate(s1, s2)!;
      expect(r.$1, closeTo(100000, 0.1));
      expect(r.$2, closeTo(10000, 0.1));
      expect(netRate(s2, s1), isNull, reason: 'clock went backwards');
    });

    test('meminfo without MemAvailable (old kernels) and garbage', () {
      final m = parseMeminfo('MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 250 kB\n')!;
      expect(m.available, 400);
      expect(m.swapPct, 0);
      expect(parseMeminfo('nothing here'), isNull);
      expect(parseProcStat('intr 1 2 3'), isNull);
      expect(parseLoadavg('x'), isNull);
      expect(parseNetDev(''), isNull);
      expect(parseStatus('').disks, isEmpty);
    });

    test('df with spaces in mount point and duplicates', () {
      final d = parseDf('Filesystem 1024-blocks Used Available Capacity Mounted on\n'
          '/dev/sdb1 1000 250 750 25% /mnt/my disk\n'
          '/dev/sdb1 1000 250 750 25% /mnt/my disk\n'
          'udev 4000 0 4000 0% /dev\n');
      expect(d, hasLength(1));
      expect(d.single.mount, '/mnt/my disk');
      expect(d.single.usedPct, 25);
    });

    test('formatting', () {
      expect(formatKb(512), '512 KB');
      expect(formatKb(1536), '1.5 MB');
      expect(formatBytes(800), '800 B');
      expect(formatUptime(125), '2m');
      expect(formatUptime(7300), '2h 1m');
      expect(parseOsRelease('NAME="Alpine Linux"\nVERSION=3.19'), 'Alpine Linux 3.19');
    });
  });

  group('processes', () {
    const ps = '''
      1 root      0.0  1.2 12100 systemd
    812 www-data 12.5  3.0 30500 nginx
    950 mysql     4.1 25.4 250880 mysqld
   1200 root     30.2  0.4  4100 python3 worker.py
  junk line
''';
    test('ps parsing and sorting', () {
      final l = parsePs(ps);
      expect(l, hasLength(4));
      expect(l[3].command, 'python3 worker.py');
      expect(l[1].user, 'www-data');
      expect(sortProcs(l, ProcSort.cpu).map((p) => p.pid), [1200, 812, 950, 1]);
      expect(sortProcs(l, ProcSort.mem).map((p) => p.pid), [950, 812, 1, 1200]);
    });
    test('PID 1 is protected', () {
      expect(isProtectedPid(1), isTrue);
      expect(isProtectedPid(0), isTrue);
      expect(isProtectedPid(812), isFalse);
      expect(() => killCommand(1), throwsArgumentError);
      expect(killCommand(812), contains('kill -s TERM 812'));
      expect(killCommand(812, force: true), contains('kill -s KILL 812'));
    });
  });

  group('services', () {
    const systemctl = '''
cron.service                 loaded    active   running Regular background program processing daemon
● nginx.service              loaded    failed   failed  A high performance web server
ssh.service                  loaded    active   running OpenBSD Secure Shell server
apt-daily.service            loaded    inactive dead    Daily apt download activities
snapd.seeded.service         not-found inactive dead    snapd.seeded.service
x-ui.service                 loaded    active   running x-ui Service
''';
    const docker = '3f2a1b9c8d7e\tmarzban-marzban-1\tgozargah/marzban:latest\trunning\tUp 3 days\n'
        'a1b2c3d4e5f6\tdb\tmysql:8\texited\tExited (137) 2 hours ago\n';

    test('systemctl list-units', () {
      final u = parseSystemctl(systemctl);
      expect(u.map((e) => e.name), ['cron.service', 'nginx.service', 'ssh.service', 'apt-daily.service', 'x-ui.service']);
      expect(u[1].failed, isTrue);
      expect(u[0].running, isTrue);
      expect(u[3].running, isFalse);
      expect(u[0].description, 'Regular background program processing daemon');
    });

    test('docker ps and the combined block', () {
      final c = parseDockerPs(docker);
      expect(c, hasLength(2));
      expect(c.first.name, 'marzban-marzban-1');
      expect(c.first.running, isTrue);
      expect(c.last.status, 'Exited (137) 2 hours ago');
      final snap = parseServices('@@systemd\n$systemctl@@docker\nDOCKER=yes\n$docker@@end\n');
      expect(snap.units, hasLength(5));
      expect(snap.hasDocker, isTrue);
      expect(snap.containers, hasLength(2));
      final none = parseServices('@@systemd\n@@docker\nDOCKER=no\n@@end\n');
      expect(none.hasDocker, isFalse);
      final denied = parseServices('@@systemd\n@@docker\nDOCKER=yes\n'
          'permission denied while trying to connect to the Docker daemon socket\n@@end\n');
      expect(denied.dockerError, contains('permission denied'));
    });

    test('action commands only accept safe names', () {
      expect(serviceActionCommand('nginx.service', 'restart'), contains('systemctl restart nginx.service'));
      expect(dockerActionCommand('3f2a1b9c8d7e', 'stop'), contains('docker stop 3f2a1b9c8d7e'));
      expect(serviceLogsCommand('ssh.service'), contains('journalctl -u ssh.service -n 200 --no-pager'));
      expect(dockerLogsCommand('db'), contains('docker logs --tail 200 db'));
      expect(() => serviceActionCommand('x; rm -rf /', 'stop'), throwsArgumentError);
      expect(() => serviceActionCommand('nginx', 'mask'), throwsArgumentError);
      expect(() => dockerLogsCommand(r'$(reboot)'), throwsArgumentError);
    });
  });

  test('ss -tulnp', () {
    const ss = '''
Netid State  Recv-Q Send-Q      Local Address:Port  Peer Address:PortProcess
udp   UNCONN 0      0           127.0.0.53%lo:53         0.0.0.0:*    users:(("systemd-resolve",pid=601,fd=13))
tcp   LISTEN 0      4096              0.0.0.0:22         0.0.0.0:*    users:(("sshd",pid=900,fd=3))
tcp   LISTEN 0      4096                 [::]:22            [::]:*    users:(("sshd",pid=900,fd=4))
tcp   LISTEN 0      511             127.0.0.1:8080       0.0.0.0:*
tcp   LISTEN 0      4096                    *:2053             *:*    users:(("x-ui",pid=1500,fd=9),("x-ui",pid=1500,fd=10))
''';
    final p = parseSs(ss);
    expect(p.map((e) => '${e.proto}:${e.port}'), ['tcp:22', 'tcp:22', 'udp:53', 'tcp:2053', 'tcp:8080']);
    expect(p[0].process, 'sshd');
    expect(p[0].pid, 900);
    expect(p[0].public, isTrue);
    expect(p[1].address, '::');
    expect(p[2].address, '127.0.0.53');
    expect(p[2].public, isFalse);
    expect(p[3].process, 'x-ui');
    expect(p[4].process, '');
    expect(p[4].pid, isNull);
  });

  group('security audit', () {
    test('hardened server', () {
      final a = parseAudit('ROOTLOGIN=prohibit-password\nPASSAUTH=no\nUFW=active\nFIREWALLD=none\n'
          'INPUTRULES=12\nINPUTDROP=1\nF2B=installed\nF2BACTIVE=active\nPKG=apt\nSECUPD=0\nAUDIT_END\n');
      expect(a.map((e) => e.id), ['rootLogin', 'passwordAuth', 'firewall', 'fail2ban', 'updates']);
      expect(a.every((e) => e.level == AuditLevel.ok), isTrue, reason: a.map((e) => '${e.id}=${e.value}').join(','));
      expect(a.every((e) => e.fix.isEmpty), isTrue);
    });

    test('fresh VPS: everything needs attention, fixes keep the ssh port open', () {
      final a = parseAudit(
          'ROOTLOGIN=yes\nPASSAUTH=yes\nUFW=inactive\nFIREWALLD=none\nINPUTRULES=0\nINPUTDROP=0\n'
          'F2B=none\nF2BACTIVE=inactive\nPKG=apt\nSECUPD=7\n',
          sshPort: 2222);
      final m = {for (final e in a) e.id: e};
      expect(a.every((e) => e.level == AuditLevel.warn), isTrue);
      expect(m['rootLogin']!.fix, contains('PermitRootLogin prohibit-password'));
      expect(m['passwordAuth']!.fix, contains('PasswordAuthentication no'));
      expect(m['firewall']!.value, 'inactive (ufw)');
      expect(m['firewall']!.fix, contains('ufw allow 2222/tcp'));
      expect(m['firewall']!.fix.indexOf('allow'), lessThan(m['firewall']!.fix.indexOf('enable')));
      expect(m['fail2ban']!.fix, contains('apt-get install -y fail2ban'));
      expect(m['updates']!.value, '7');
    });

    test('defaults, nftables, dnf and unreadable values', () {
      final a = parseAudit('ROOTLOGIN=\nPASSAUTH=\nUFW=none\nFIREWALLD=inactive\nINPUTRULES=5\nINPUTDROP=0\n'
          'F2B=installed\nF2BACTIVE=failed\nPKG=dnf\nSECUPD=\n');
      final m = {for (final e in a) e.id: e};
      expect(m['rootLogin']!.level, AuditLevel.ok, reason: 'OpenSSH default is prohibit-password');
      expect(m['passwordAuth']!.level, AuditLevel.warn, reason: 'default yes');
      expect(m['firewall']!.level, AuditLevel.ok);
      expect(m['fail2ban']!.fix, 'sudo systemctl enable --now fail2ban');
      expect(m['updates']!.level, AuditLevel.unknown);
      final u = parseAudit('UFW=none\nFIREWALLD=none\nINPUTRULES=\n');
      expect(u.firstWhere((e) => e.id == 'firewall').level, AuditLevel.unknown);
    });

    test('the audit block only reads', () {
      for (final bad in ['sed -i', 'systemctl start', 'systemctl stop', 'ufw enable', 'apt-get install', 'rm ']) {
        expect(auditCommand.contains(bad), isFalse, reason: bad);
      }
      expect(auditCommand, contains('apt-get -s'));
    });
  });

  test('destructive command detection', () {
    for (final c in [
      'rm -rf /var/www',
      'sudo reboot',
      'shutdown -h now',
      'cd /tmp && rm x',
      'mkfs.ext4 /dev/sdb1',
      'dd if=/dev/zero of=/dev/sda',
      'poweroff',
      'init 6',
    ]) {
      expect(isDestructiveCommand(c), isTrue, reason: c);
    }
    for (final c in ['uptime', 'df -h', 'free -m', 'docker ps', 'systemctl status nginx', 'echo firmware', 'ls /tmp/rmdir']) {
      expect(isDestructiveCommand(c), isFalse, reason: c);
    }
  });

  test('critical SFTP paths', () {
    for (final p in ['/', '/etc', '/etc/', '//etc//ssh', '/etc/passwd', '/etc/shadow', '/boot', '/usr', '/bin', '/sbin',
      '/lib', '/var', '/root', '/usr/../etc', '/./var/']) {
      expect(isCriticalPath(p), isTrue, reason: p);
    }
    for (final p in ['/etc/nginx', '/var/www', '/root/notes.txt', '/home/u/etc', '/usr/local/bin/x']) {
      expect(isCriticalPath(p), isFalse, reason: p);
    }
    expect(normalizeRemote('/a//b/./c/../d/'), '/a/b/d');
  });

  test('privacy masking', () {
    final h = Host(id: 'x', label: '', host: '203.0.113.7', port: 2222, user: 'root');
    expect(hostTitle(h, hide: false), '203.0.113.7');
    expect(hostTitle(h, hide: true), '•••.•••.•••.•••');
    expect(hostAddress(h, hide: true), '•••@•••.•••.•••.•••:2222');
    expect(hostAddress(h, hide: false), 'root@203.0.113.7:2222');
    final named = Host(id: 'y', label: 'Germany 1', host: 'de.example.com', user: 'admin');
    expect(hostTitle(named, hide: true), 'Germany 1');
    expect(hostAddress(named, hide: true), '•••@•••.•••.•••');
    expect(maskText('root@10.1.2.3:~'), isNot(contains('10.1.2.3')));
    expect(maskText('server 10.1.2.3 ok'), 'server •••.•••.•••.••• ok');
  });

  group('SOCKS5 client', () {
    test('no-auth and user/password, data flows both ways', () async {
      final proxy = await FakeSocks.start(user: 'u', pass: 'p');
      addTearDown(proxy.close);
      final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(echo.close);
      echo.listen((c) => c.listen((d) => c.add(d), onDone: c.close));

      final s = await connectSocks5('127.0.0.1', proxy.port, '127.0.0.1', echo.port, user: 'u', password: 'p');
      final got = <int>[];
      final done = Completer<void>();
      s.stream.listen((d) {
        got.addAll(d);
        if (got.length >= 5 && !done.isCompleted) done.complete();
      });
      s.sink.add(utf8.encode('hello'));
      await done.future.timeout(const Duration(seconds: 5));
      expect(utf8.decode(got), 'hello');
      expect(proxy.lastTarget, '127.0.0.1:${echo.port}');
      await s.close();

      // wrong password
      await expectLater(connectSocks5('127.0.0.1', proxy.port, '127.0.0.1', echo.port, user: 'u', password: 'x'),
          throwsA(isA<Socks5Error>().having((e) => e.auth, 'auth', isTrue)));
      // proxy wants a login but none is set
      await expectLater(connectSocks5('127.0.0.1', proxy.port, '127.0.0.1', echo.port),
          throwsA(isA<Socks5Error>().having((e) => e.auth, 'auth', isTrue)));
    });

    test('host names are resolved by the proxy and refusals are reported', () async {
      final proxy = await FakeSocks.start(refuse: true);
      addTearDown(proxy.close);
      await expectLater(connectSocks5('127.0.0.1', proxy.port, 'my.server.example', 22),
          throwsA(isA<Socks5Error>().having((e) => e.code, 'code', 5)));
      expect(proxy.lastTarget, 'my.server.example:22');
    });
  });

  test('host proxy settings round-trip through JSON', () {
    final h = Host(id: 'p', label: 'x', host: 'h', user: 'u', proxyHost: '10.0.0.9', proxyPort: 9050, proxyUser: 'me');
    final back = Host.fromJson(h.toJson());
    expect(back.hasProxy, isTrue);
    expect(back.proxyPort, 9050);
    expect(back.proxyUser, 'me');
    expect(Host.fromJson(Host(id: 'q', label: '', host: 'h', user: 'u').toJson()).hasProxy, isFalse);
    expect(Host(id: 'q', label: '', host: 'h', user: 'u').toJson().containsKey('proxyHost'), isFalse);
  });
}

/// A tiny SOCKS5 server for tests: optional username/password, CONNECT only.
class FakeSocks {
  FakeSocks._(this._server, this.user, this.pass, this.refuse);
  final ServerSocket _server;
  final String? user, pass;
  final bool refuse;
  String? lastTarget;
  int get port => _server.port;

  static Future<FakeSocks> start({String? user, String? pass, bool refuse = false}) async {
    final f = FakeSocks._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), user, pass, refuse);
    f._server.listen(f._serve);
    return f;
  }

  Future<void> close() => _server.close();

  Future<void> _serve(Socket c) async {
    final buf = <int>[];
    final waiters = <Completer<void>>[];
    Socket? upstream;
    c.listen((d) {
      if (upstream != null) return upstream.add(d);
      buf.addAll(d);
      for (final w in List.of(waiters)) {
        w.complete();
      }
      waiters.clear();
    }, onDone: () => upstream?.destroy(), onError: (_) {});
    Future<List<int>> take(int n) async {
      while (buf.length < n) {
        final w = Completer<void>();
        waiters.add(w);
        await w.future;
      }
      final r = buf.sublist(0, n);
      buf.removeRange(0, n);
      return r;
    }

    final h = await take(2);
    final methods = await take(h[1]);
    if (user != null) {
      if (!methods.contains(2)) {
        c.add([5, 0xFF]);
        return c.close();
      }
      c.add([5, 2]);
      final v = await take(2);
      final u = utf8.decode(await take(v[1]));
      final pl = (await take(1))[0];
      final p = utf8.decode(await take(pl));
      final ok = u == user && p == pass;
      c.add([1, ok ? 0 : 1]);
      if (!ok) return c.close();
    } else {
      c.add([5, 0]);
    }
    final req = await take(4);
    String host;
    if (req[3] == 1) {
      host = (await take(4)).join('.');
    } else if (req[3] == 3) {
      host = utf8.decode(await take((await take(1))[0]));
    } else {
      host = InternetAddress.fromRawAddress(Uint8List.fromList(await take(16))).address;
    }
    final pb = await take(2);
    final port = pb[0] << 8 | pb[1];
    lastTarget = '$host:$port';
    if (refuse) {
      c.add([5, 5, 0, 1, 0, 0, 0, 0, 0, 0]);
      return c.close();
    }
    final up = await Socket.connect(host, port);
    c.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
    upstream = up;
    if (buf.isNotEmpty) up.add(List.of(buf));
    buf.clear();
    up.listen(c.add, onDone: () => c.close(), onError: (_) {});
  }
}
