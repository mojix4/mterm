// Agentless server tools: the shell commands the Tools screen and the
// multi-server broadcast run over plain SSH exec, and pure parsers for their
// output (unit-tested with fixed sample text in test/server_tools_test.dart).
//
// Everything here only reads (/proc, df, ps, ss, systemctl, docker), except
// the explicit actions (kill, service start/stop/restart) the user confirms.

/// Wraps [cmd] so it runs as root when possible: directly for root, through
/// passwordless `sudo -n` otherwise, and as the plain user when sudo needs a
/// password (so read-only commands still show what the user may see).
String asRoot(String cmd) =>
    'if [ "\$(id -u)" = 0 ]; then $cmd; else sudo -n $cmd 2>/dev/null || $cmd; fi';

/// Quotes [s] for a POSIX shell.
String shQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

// ---------------------------------------------------------------------------
// Dashboard

/// One read-only block polled every few seconds by the Status tab. Sections
/// are separated by "@@name" marker lines.
const statusCommand = 'export LC_ALL=C; '
    'echo @@stat; head -n 1 /proc/stat; '
    'echo @@cpus; nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo; '
    'echo @@mem; cat /proc/meminfo; '
    'echo @@df; df -kP -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null || df -kP; '
    'echo @@net; cat /proc/net/dev; '
    'echo @@load; cat /proc/loadavg; '
    'echo @@up; cat /proc/uptime; '
    'echo @@os; cat /etc/os-release 2>/dev/null; '
    'echo @@kernel; uname -srm; '
    'echo @@end';

/// Splits "@@name" sectioned output into name → body.
Map<String, String> splitSections(String out) {
  final m = <String, String>{};
  String? cur;
  final buf = StringBuffer();
  for (final line in out.split('\n')) {
    final l = line.trimRight();
    if (l.startsWith('@@') && !l.contains(' ')) {
      if (cur != null) m[cur] = buf.toString();
      cur = l.substring(2);
      buf.clear();
    } else if (cur != null) {
      buf.writeln(l);
    }
  }
  if (cur != null && cur != 'end') m[cur] = buf.toString();
  return m;
}

/// The aggregate "cpu" line of /proc/stat.
class CpuTimes {
  const CpuTimes(this.idle, this.total);
  final int idle; // idle + iowait
  final int total;

  /// Busy percentage between [prev] and this sample (0..100).
  double usageSince(CpuTimes prev) {
    final dt = total - prev.total;
    if (dt <= 0) return 0;
    final di = idle - prev.idle;
    return ((dt - di) / dt * 100).clamp(0, 100).toDouble();
  }
}

CpuTimes? parseProcStat(String text) {
  for (final line in text.split('\n')) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.isEmpty || f.first != 'cpu') continue;
    final n = f.skip(1).map((e) => int.tryParse(e) ?? 0).toList();
    if (n.length < 4) return null;
    // user nice system idle iowait irq softirq steal (guest is inside user)
    final total = n.take(8).fold<int>(0, (a, b) => a + b);
    final idle = n[3] + (n.length > 4 ? n[4] : 0);
    return CpuTimes(idle, total);
  }
  return null;
}

class MemInfo {
  const MemInfo({required this.total, required this.available, required this.swapTotal, required this.swapFree});

  /// All in kB.
  final int total, available, swapTotal, swapFree;
  int get used => (total - available).clamp(0, total);
  int get swapUsed => (swapTotal - swapFree).clamp(0, swapTotal);
  double get usedPct => total == 0 ? 0 : used / total * 100;
  double get swapPct => swapTotal == 0 ? 0 : swapUsed / swapTotal * 100;
}

MemInfo? parseMeminfo(String text) {
  final v = <String, int>{};
  for (final line in text.split('\n')) {
    final m = RegExp(r'^(\w+(?:\(\w+\))?):\s+(\d+)').firstMatch(line.trim());
    if (m != null) v[m.group(1)!] = int.parse(m.group(2)!);
  }
  final total = v['MemTotal'];
  if (total == null) return null;
  // Old kernels (< 3.14) have no MemAvailable.
  final avail = v['MemAvailable'] ?? ((v['MemFree'] ?? 0) + (v['Buffers'] ?? 0) + (v['Cached'] ?? 0));
  return MemInfo(total: total, available: avail, swapTotal: v['SwapTotal'] ?? 0, swapFree: v['SwapFree'] ?? 0);
}

class DiskUsage {
  const DiskUsage(this.fs, this.mount, this.totalKb, this.usedKb, this.availKb);
  final String fs, mount;
  final int totalKb, usedKb, availKb;
  double get usedPct => (usedKb + availKb) == 0 ? 0 : usedKb / (usedKb + availKb) * 100;
}

/// `df -kP` output. Pseudo filesystems and duplicate mounts are dropped.
List<DiskUsage> parseDf(String text) {
  final out = <DiskUsage>[];
  final seen = <String>{};
  const pseudo = {'tmpfs', 'devtmpfs', 'udev', 'overlay', 'squashfs', 'none', 'shm', 'efivarfs', 'run'};
  for (final line in text.split('\n')) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 6 || f[0] == 'Filesystem') continue;
    final total = int.tryParse(f[1]), used = int.tryParse(f[2]), avail = int.tryParse(f[3]);
    if (total == null || used == null || avail == null || total == 0) continue;
    final mount = f.sublist(5).join(' ');
    if (pseudo.contains(f[0]) || mount.startsWith('/snap/') || mount.startsWith('/run') || mount.startsWith('/dev')) {
      continue;
    }
    if (!seen.add(f[0] == mount ? mount : '${f[0]}|$mount')) continue;
    out.add(DiskUsage(f[0], mount, total, used, avail));
  }
  return out;
}

/// Total received / sent bytes over all real interfaces (not lo).
class NetTotals {
  const NetTotals(this.rx, this.tx);
  final int rx, tx;
}

NetTotals? parseNetDev(String text) {
  var rx = 0, tx = 0;
  var any = false;
  for (final line in text.split('\n')) {
    final i = line.indexOf(':');
    if (i < 0) continue;
    final name = line.substring(0, i).trim();
    if (name.isEmpty || name.contains('|') || name == 'lo') continue;
    final f = line.substring(i + 1).trim().split(RegExp(r'\s+'));
    if (f.length < 9) continue;
    rx += int.tryParse(f[0]) ?? 0;
    tx += int.tryParse(f[8]) ?? 0;
    any = true;
  }
  return any ? NetTotals(rx, tx) : null;
}

/// 1, 5 and 15 minute load averages.
List<double>? parseLoadavg(String text) {
  final f = text.trim().split(RegExp(r'\s+'));
  if (f.length < 3) return null;
  final v = f.take(3).map(double.tryParse).toList();
  if (v.any((e) => e == null)) return null;
  return v.cast<double>();
}

/// Seconds since boot from /proc/uptime.
double? parseUptime(String text) => double.tryParse(text.trim().split(RegExp(r'\s+')).first);

/// PRETTY_NAME (or NAME VERSION) from /etc/os-release.
String parseOsRelease(String text) {
  final v = <String, String>{};
  for (final line in text.split('\n')) {
    final i = line.indexOf('=');
    if (i <= 0) continue;
    var val = line.substring(i + 1).trim();
    if (val.length >= 2 && (val.startsWith('"') || val.startsWith("'"))) val = val.substring(1, val.length - 1);
    v[line.substring(0, i).trim()] = val;
  }
  return v['PRETTY_NAME'] ?? [v['NAME'], v['VERSION']].whereType<String>().join(' ');
}

/// One poll of the Status tab.
class StatusSample {
  StatusSample({
    this.cpu,
    this.cpus = 0,
    this.mem,
    this.disks = const [],
    this.net,
    this.load,
    this.uptime,
    this.os = '',
    this.kernel = '',
  });
  final CpuTimes? cpu;
  final int cpus;
  final MemInfo? mem;
  final List<DiskUsage> disks;
  final NetTotals? net;
  final List<double>? load;
  final double? uptime;
  final String os, kernel;
}

StatusSample parseStatus(String out) {
  final sec = splitSections(out);
  return StatusSample(
    cpu: parseProcStat(sec['stat'] ?? ''),
    cpus: int.tryParse((sec['cpus'] ?? '').trim()) ?? 0,
    mem: parseMeminfo(sec['mem'] ?? ''),
    disks: parseDf(sec['df'] ?? ''),
    net: parseNetDev(sec['net'] ?? ''),
    load: parseLoadavg(sec['load'] ?? ''),
    uptime: parseUptime(sec['up'] ?? ''),
    os: parseOsRelease(sec['os'] ?? ''),
    kernel: (sec['kernel'] ?? '').trim(),
  );
}

/// Bytes per second between two samples, using the server's own uptime as
/// the clock. Null when it can't be worked out yet.
(double, double)? netRate(StatusSample prev, StatusSample cur) {
  final a = prev.net, b = cur.net, t0 = prev.uptime, t1 = cur.uptime;
  if (a == null || b == null || t0 == null || t1 == null || t1 <= t0) return null;
  final dt = t1 - t0;
  return (((b.rx - a.rx) / dt).clamp(0, double.infinity).toDouble(), ((b.tx - a.tx) / dt).clamp(0, double.infinity).toDouble());
}

/// "3d 4h", "5h 12m", "7m" (ASCII).
String formatUptime(double seconds) {
  final s = seconds.floor();
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// kB → "1.5 GB" (ASCII).
String formatKb(int kb) => formatBytes(kb * 1024.0);

String formatBytes(double n) {
  if (n < 1024) return '${n.round()} B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = n / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${u[i]}';
}

// ---------------------------------------------------------------------------
// Processes

const psCommand = 'LC_ALL=C ps -eo pid=,user=,pcpu=,pmem=,rss=,comm= 2>/dev/null';

class ProcInfo {
  const ProcInfo(this.pid, this.user, this.cpu, this.mem, this.rssKb, this.command);
  final int pid;
  final String user;
  final double cpu, mem;
  final int rssKb;
  final String command;
}

List<ProcInfo> parsePs(String text) {
  final out = <ProcInfo>[];
  for (final line in text.split('\n')) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 6) continue;
    final pid = int.tryParse(f[0]);
    final cpu = double.tryParse(f[2]), mem = double.tryParse(f[3]), rss = int.tryParse(f[4]);
    if (pid == null || cpu == null || mem == null || rss == null) continue;
    out.add(ProcInfo(pid, f[1], cpu, mem, rss, f.sublist(5).join(' ')));
  }
  return out;
}

enum ProcSort { cpu, mem }

List<ProcInfo> sortProcs(List<ProcInfo> list, ProcSort by) => List.of(list)
  ..sort((a, b) => by == ProcSort.cpu
      ? (b.cpu.compareTo(a.cpu) != 0 ? b.cpu.compareTo(a.cpu) : b.rssKb.compareTo(a.rssKb))
      : (b.rssKb.compareTo(a.rssKb) != 0 ? b.rssKb.compareTo(a.rssKb) : b.cpu.compareTo(a.cpu)));

/// PID 1 (init/systemd) and kernel bookkeeping PIDs can never be killed from the app.
bool isProtectedPid(int pid) => pid <= 1;

/// Kill command for [pid]; throws for protected PIDs.
String killCommand(int pid, {bool force = false}) {
  if (isProtectedPid(pid)) throw ArgumentError('protected pid $pid');
  return '${asRoot('kill -s ${force ? 'KILL' : 'TERM'} $pid')} 2>&1';
}

// ---------------------------------------------------------------------------
// Services

final servicesCommand = 'export LC_ALL=C; '
    'echo @@systemd; command -v systemctl >/dev/null 2>&1 && '
    'systemctl list-units --type=service --all --no-legend --no-pager --plain 2>/dev/null; '
    'echo @@docker; if command -v docker >/dev/null 2>&1; then echo DOCKER=yes; '
    '{ ${asRoot("docker ps -a --format '{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.State}}\\t{{.Status}}'")}; } 2>&1; '
    'else echo DOCKER=no; fi; echo @@end';

class ServiceUnit {
  const ServiceUnit(this.name, this.load, this.active, this.sub, this.description);
  final String name, load, active, sub, description;
  bool get running => sub == 'running';
  bool get failed => active == 'failed';
}

/// `systemctl list-units --type=service --all --no-legend --plain`.
List<ServiceUnit> parseSystemctl(String text) {
  final out = <ServiceUnit>[];
  for (var line in text.split('\n')) {
    line = line.trim();
    // some versions mark failed units with a leading bullet
    if (line.startsWith('●') || line.startsWith('*')) line = line.substring(1).trim();
    final f = line.split(RegExp(r'\s+'));
    if (f.length < 4 || !f[0].endsWith('.service')) continue;
    if (f[1] == 'not-found') continue;
    out.add(ServiceUnit(f[0], f[1], f[2], f[3], f.length > 4 ? f.sublist(4).join(' ') : ''));
  }
  return out;
}

class DockerContainer {
  const DockerContainer(this.id, this.name, this.image, this.state, this.status);
  final String id, name, image, state, status;
  bool get running => state == 'running';
}

/// Tab-separated `docker ps -a --format` lines (ID, Names, Image, State, Status).
List<DockerContainer> parseDockerPs(String text) {
  final out = <DockerContainer>[];
  for (final line in text.split('\n')) {
    final f = line.trim().split('\t');
    if (f.length < 5 || !RegExp(r'^[0-9a-f]{6,64}$').hasMatch(f[0])) continue;
    out.add(DockerContainer(f[0], f[1], f[2], f[3].toLowerCase(), f[4]));
  }
  return out;
}

class ServicesSnapshot {
  const ServicesSnapshot(this.units, this.hasDocker, this.containers, this.dockerError);
  final List<ServiceUnit> units;
  final bool hasDocker;
  final List<DockerContainer> containers;

  /// Text docker printed instead of a list (e.g. permission denied), or ''.
  final String dockerError;
}

ServicesSnapshot parseServices(String out) {
  final sec = splitSections(out);
  final d = sec['docker'] ?? '';
  final has = d.contains('DOCKER=yes');
  final containers = parseDockerPs(d);
  var err = '';
  if (has && containers.isEmpty) {
    err = d
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.contains('DOCKER=yes'))
        .join('\n')
        .trim();
  }
  return ServicesSnapshot(parseSystemctl(sec['systemd'] ?? ''), has, containers, err);
}

/// Names a unit or container may have; anything else is refused before it
/// reaches the shell.
final _safeName = RegExp(r'^[A-Za-z0-9@._:\-]+$');
bool isSafeName(String n) => n.isNotEmpty && n.length < 200 && _safeName.hasMatch(n);

String serviceActionCommand(String unit, String action) {
  if (!isSafeName(unit) || !const {'start', 'stop', 'restart'}.contains(action)) throw ArgumentError(unit);
  return '${asRoot('systemctl $action $unit')} 2>&1';
}

String dockerActionCommand(String id, String action) {
  if (!isSafeName(id) || !const {'start', 'stop', 'restart'}.contains(action)) throw ArgumentError(id);
  return '${asRoot('docker $action $id')} 2>&1';
}

String serviceLogsCommand(String unit, {int lines = 200}) {
  if (!isSafeName(unit)) throw ArgumentError(unit);
  return '${asRoot('journalctl -u $unit -n $lines --no-pager')} 2>&1';
}

String dockerLogsCommand(String id, {int lines = 200}) {
  if (!isSafeName(id)) throw ArgumentError(id);
  return '${asRoot('docker logs --tail $lines $id')} 2>&1';
}

// ---------------------------------------------------------------------------
// Open ports

final portsCommand = 'export LC_ALL=C; ${asRoot('ss -tulnp')}';

class OpenPort {
  const OpenPort(this.proto, this.address, this.port, this.process, this.pid);
  final String proto; // tcp | udp
  final String address;
  final int port;
  final String process; // '' when not visible (needs root)
  final int? pid;

  /// Listens on every interface (reachable from outside unless firewalled).
  bool get public => const {'0.0.0.0', '*', '::', '[::]'}.contains(address);
}

/// `ss -tulnp` lines: Netid State Recv-Q Send-Q Local:Port Peer:Port [Process].
List<OpenPort> parseSs(String text) {
  final out = <OpenPort>[];
  final seen = <String>{};
  for (final line in text.split('\n')) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 5) continue;
    final proto = f[0].toLowerCase();
    if (proto != 'tcp' && proto != 'udp') continue;
    final local = f[4];
    final i = local.lastIndexOf(':');
    if (i <= 0) continue;
    final port = int.tryParse(local.substring(i + 1));
    if (port == null) continue;
    var addr = local.substring(0, i);
    final pct = addr.indexOf('%'); // 127.0.0.53%lo
    if (pct > 0) addr = addr.substring(0, pct);
    if (addr.startsWith('[') && addr.endsWith(']')) addr = addr.substring(1, addr.length - 1);
    var proc = '';
    int? pid;
    final rest = f.length > 6 ? f.sublist(6).join(' ') : '';
    final m = RegExp(r'\(\("([^"]+)",pid=(\d+)').firstMatch(rest);
    if (m != null) {
      proc = m.group(1)!;
      pid = int.tryParse(m.group(2)!);
    }
    if (!seen.add('$proto|$addr|$port|$proc')) continue;
    out.add(OpenPort(proto, addr, port, proc, pid));
  }
  out.sort((a, b) => a.port != b.port ? a.port.compareTo(b.port) : a.proto.compareTo(b.proto));
  return out;
}

// ---------------------------------------------------------------------------
// Security check (read-only)

/// One read-only audit block; prints KEY=value lines.
const auditCommand = r'''
export LC_ALL=C
R() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@" 2>/dev/null || "$@"; fi; }
T=$(R sshd -T 2>/dev/null)
cfg() {
  v=$(printf '%s\n' "$T" | awk -v k="$1" 'tolower($1)==k{print tolower($2); exit}')
  # effective settings need root; otherwise read the files (first match wins,
  # sshd_config.d is included first on modern Ubuntu)
  [ -z "$v" ] && v=$(cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null | awk -v k="$1" 'tolower($1)==k{print tolower($2); exit}')
  echo "$v"
}
echo "ROOTLOGIN=$(cfg permitrootlogin)"
echo "PASSAUTH=$(cfg passwordauthentication)"
if command -v ufw >/dev/null 2>&1; then echo "UFW=$(R ufw status 2>/dev/null | head -n 1 | awk '{print tolower($2)}')"; else echo UFW=none; fi
if systemctl cat firewalld.service >/dev/null 2>&1; then echo "FIREWALLD=$(systemctl is-active firewalld 2>/dev/null)"; else echo FIREWALLD=none; fi
RS=$(R nft list ruleset 2>/dev/null)
if [ -n "$RS" ]; then
  printf '%s\n' "$RS" | awk '/hook input/{c=1; if ($0 ~ /policy drop/) d=1; next} c&&/^[[:space:]]*}/{c=0} c&&NF{n++} END{print "INPUTRULES=" n+0; print "INPUTDROP=" (d?1:0)}'
else
  IP=$(R iptables -S INPUT 2>/dev/null)
  if [ -n "$IP" ]; then
    echo "INPUTRULES=$(printf '%s\n' "$IP" | grep -c '^-A')"
    printf '%s\n' "$IP" | grep -q '^-P INPUT DROP' && echo INPUTDROP=1 || echo INPUTDROP=0
  else echo INPUTRULES=; fi
fi
if command -v fail2ban-server >/dev/null 2>&1; then echo F2B=installed; else echo F2B=none; fi
echo "F2BACTIVE=$(systemctl is-active fail2ban 2>/dev/null)"
if command -v apt-get >/dev/null 2>&1; then
  echo PKG=apt
  echo "SECUPD=$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c '^Inst .*[Ss]ecurity')"
elif command -v dnf >/dev/null 2>&1; then
  echo PKG=dnf
  echo "SECUPD=$(timeout 25 dnf -q -C updateinfo list --security 2>/dev/null | grep -c .)"
else echo PKG=none; echo SECUPD=; fi
echo AUDIT_END
''';

enum AuditLevel { ok, warn, unknown }

class AuditItem {
  const AuditItem(this.id, this.level, this.value, {this.fix = ''});

  /// rootLogin | passwordAuth | firewall | fail2ban | updates
  final String id;
  final AuditLevel level;

  /// What was found, short and ASCII (e.g. "yes", "active (ufw)", "3").
  final String value;

  /// Copyable command that fixes it ('' when nothing to fix).
  final String fix;
}

Map<String, String> parseKeyValues(String out) {
  final m = <String, String>{};
  for (final line in out.split('\n')) {
    final i = line.indexOf('=');
    if (i <= 0) continue;
    final k = line.substring(0, i).trim();
    if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(k)) continue;
    m[k] = line.substring(i + 1).trim();
  }
  return m;
}

/// Turns the audit output into checks. [sshPort] is used in the firewall fix
/// so it never locks the user out of a server on a custom port.
List<AuditItem> parseAudit(String out, {int sshPort = 22}) {
  final v = parseKeyValues(out);
  final items = <AuditItem>[];
  const reload = 'sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd';

  // PermitRootLogin: OpenSSH's default (when unset) is prohibit-password.
  final root = (v['ROOTLOGIN'] ?? '').toLowerCase();
  final rootLevel = root == 'yes'
      ? AuditLevel.warn
      : (root.isEmpty || const {'no', 'prohibit-password', 'without-password', 'forced-commands-only'}.contains(root))
          ? AuditLevel.ok
          : AuditLevel.unknown;
  items.add(AuditItem('rootLogin', rootLevel, root.isEmpty ? 'default (prohibit-password)' : root,
      fix: rootLevel == AuditLevel.ok
          ? ''
          : "sudo sed -i -E 's/^#?\\s*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && $reload"));

  // PasswordAuthentication: default yes.
  final pa = (v['PASSAUTH'] ?? '').toLowerCase();
  final paLevel = pa == 'no' ? AuditLevel.ok : (pa.isEmpty || pa == 'yes') ? AuditLevel.warn : AuditLevel.unknown;
  items.add(AuditItem('passwordAuth', paLevel, pa.isEmpty ? 'default (yes)' : pa,
      fix: paLevel == AuditLevel.ok
          ? ''
          : "sudo sed -i -E 's/^#?\\s*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null; $reload"));

  // Firewall: ufw / firewalld active, or input rules in nftables/iptables.
  final ufw = v['UFW'] ?? 'none', fwd = v['FIREWALLD'] ?? 'none';
  final rules = int.tryParse(v['INPUTRULES'] ?? ''), drop = v['INPUTDROP'] == '1';
  String fwValue;
  AuditLevel fwLevel;
  if (ufw == 'active') {
    fwValue = 'active (ufw)';
    fwLevel = AuditLevel.ok;
  } else if (fwd == 'active') {
    fwValue = 'active (firewalld)';
    fwLevel = AuditLevel.ok;
  } else if (drop || (rules ?? 0) > 0) {
    fwValue = 'input rules: ${rules ?? 0}${drop ? ', policy drop' : ''}';
    fwLevel = AuditLevel.ok;
  } else if (rules == 0 || ufw == 'inactive' || fwd == 'inactive') {
    fwValue = ufw == 'inactive' ? 'inactive (ufw)' : 'no rules';
    fwLevel = AuditLevel.warn;
  } else {
    fwValue = 'unknown';
    fwLevel = AuditLevel.unknown;
  }
  final pkgApt = (v['PKG'] ?? '') != 'dnf';
  items.add(AuditItem('firewall', fwLevel, fwValue,
      fix: fwLevel == AuditLevel.ok
          ? ''
          : pkgApt || ufw != 'none'
              ? 'sudo apt-get install -y ufw && sudo ufw allow $sshPort/tcp && sudo ufw --force enable'
              : 'sudo dnf install -y firewalld && sudo systemctl enable --now firewalld && sudo firewall-cmd --permanent --add-port=$sshPort/tcp && sudo firewall-cmd --reload'));

  // fail2ban
  final f2b = v['F2B'] ?? 'none', f2bActive = v['F2BACTIVE'] ?? '';
  final f2bLevel = f2bActive == 'active' ? AuditLevel.ok : AuditLevel.warn;
  items.add(AuditItem('fail2ban', f2bLevel,
      f2bActive == 'active' ? 'running' : (f2b == 'installed' ? 'installed, not running' : 'not installed'),
      fix: f2bLevel == AuditLevel.ok
          ? ''
          : f2b == 'installed'
              ? 'sudo systemctl enable --now fail2ban'
              : pkgApt
                  ? 'sudo apt-get install -y fail2ban && sudo systemctl enable --now fail2ban'
                  : 'sudo dnf install -y epel-release fail2ban && sudo systemctl enable --now fail2ban'));

  // pending security updates
  final pkg = v['PKG'] ?? 'none';
  final n = int.tryParse(v['SECUPD'] ?? '');
  final upLevel = n == null ? AuditLevel.unknown : (n == 0 ? AuditLevel.ok : AuditLevel.warn);
  items.add(AuditItem('updates', upLevel, n == null ? 'unknown' : '$n',
      fix: upLevel == AuditLevel.ok
          ? ''
          : pkg == 'dnf'
              ? 'sudo dnf upgrade --security -y'
              : 'sudo apt-get update && sudo apt-get upgrade -y'));
  return items;
}

// ---------------------------------------------------------------------------
// Broadcast

/// Commands that delete data or take the server down; the broadcast screen
/// asks before running them.
bool isDestructiveCommand(String cmd) => RegExp(
      r'(^|[\s;&|(`$])(sudo\s+)?(rm|reboot|shutdown|poweroff|halt|mkfs(\.\w+)?|dd|wipefs|fdisk|init\s+[06])(\s|$|;)',
    ).hasMatch(cmd.trim());
