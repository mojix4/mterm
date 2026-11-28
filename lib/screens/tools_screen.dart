// Per-server Tools (ابزارها): live status, processes, services (systemd +
// Docker), open ports and a read-only security check. Agentless: every tab
// runs plain shell commands over SSH exec (see lib/server_tools.dart).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../models.dart';
import '../privacy.dart';
import '../server_tools.dart';
import '../session.dart';
import '../themes.dart';
import '../tool_conn.dart';
import 'common.dart';

/// Opens the Tools screen for [h]. With a live [session] its connection is reused.
Future<void> openTools(BuildContext context, Host h, {TermSession? session, int tab = 0}) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ServerToolsScreen(host: h, session: session, initialTab: tab)));

class ServerToolsScreen extends StatefulWidget {
  const ServerToolsScreen({
    super.key,
    required this.host,
    this.session,
    this.initialTab = 0,
    this.keyPrompt,
    this.pwPrompt,
    this.pollEvery = const Duration(seconds: 3),
    this.conn,
  });
  final Host host;
  final TermSession? session;
  final int initialTab;
  final HostKeyPrompt? keyPrompt;
  final PasswordPrompt? pwPrompt;
  final Duration pollEvery;

  /// Test hook: a ready-made connection (closed with the screen).
  final ToolConn? conn;

  @override
  State<ServerToolsScreen> createState() => _ServerToolsScreenState();
}

class _ServerToolsScreenState extends State<ServerToolsScreen> {
  late final conn = widget.conn ??
      ToolConn(widget.host,
      session: widget.session,
      hostKeyPrompt: widget.keyPrompt ?? hostKeyPrompt,
      passwordPrompt: widget.pwPrompt ?? passwordPrompt);

  @override
  void dispose() {
    conn.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['tools'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Ltr(hostTitle(widget.host), style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
          bottom: TabBar(
            key: const ValueKey('tools-tabs'),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            labelColor: p.accent,
            indicatorColor: p.accent,
            unselectedLabelColor: p.muted,
            tabs: [
              Tab(key: const ValueKey('tab-status'), text: s['toolsStatus']),
              Tab(key: const ValueKey('tab-procs'), text: s['toolsProcesses']),
              Tab(key: const ValueKey('tab-services'), text: s['toolsServices']),
              Tab(key: const ValueKey('tab-ports'), text: s['toolsPorts']),
              Tab(key: const ValueKey('tab-security'), text: s['toolsSecurity']),
            ],
          ),
        ),
        body: TabBarView(children: [
          StatusTab(conn: conn, every: widget.pollEvery),
          ProcessesTab(conn: conn),
          ServicesTab(conn: conn),
          PortsTab(conn: conn),
          SecurityTab(conn: conn),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// shared bits

/// Loads [load] once on open (and on refresh), with spinner / error / retry.
mixin _Loader<T extends StatefulWidget, D> on State<T> {
  D? data;
  String? error;
  bool loading = false;

  Future<D> load();

  @override
  void initState() {
    super.initState();
    loading = false;
    Future.microtask(reload);
  }

  Future<void> reload() async {
    if (loading || !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await load();
      if (!mounted) return;
      setState(() {
        data = d;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = describeError(e, S.of(context));
      });
    }
  }

  Widget body(Widget Function(D d) build) {
    final d = data;
    if (d == null && error != null) return ErrorRetry(message: error!, onRetry: reload);
    if (d == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(onRefresh: reload, child: build(d));
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: p.red, size: 40),
          const SizedBox(height: 12),
          Text(s.f('toolsFailed', {'msg': message}), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(key: const ValueKey('tools-retry'), onPressed: onRetry, child: Text(s['retry'])),
        ]),
      ),
    );
  }
}

String _pct(double v) => '${v.toStringAsFixed(v < 10 ? 1 : 0)}%';

Color _levelColor(Palette p, double pct) => pct >= 90 ? p.red : (pct >= 70 ? p.amber : p.green);

class _Bar extends StatelessWidget {
  const _Bar(this.pct);
  final double pct;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: (pct / 100).clamp(0, 1).toDouble(),
        minHeight: 8,
        backgroundColor: p.bg,
        color: _levelColor(p, pct),
      ),
    );
  }
}

/// A label on the start side and an LTR value on the end side.
class _KV extends StatelessWidget {
  const _KV(this.k, this.v, {this.valueKey});
  final String k, v;
  final Key? valueKey;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: Text(k, style: TextStyle(color: p.muted, fontSize: 13))),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(v,
              key: valueKey,
              textDirection: TextDirection.ltr,
              textAlign: S.of(context).isRtl ? TextAlign.left : TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.trailing});
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
          if (trailing != null) ...[const SizedBox(width: 8), Flexible(child: trailing!)],
        ]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, S.of(context)['copied']);
}

/// Runs an action command and shows its result as a toast.
Future<bool> _runAction(BuildContext context, ToolConn conn, String cmd) async {
  final s = S.of(context);
  try {
    final r = await conn.run(cmd);
    if (!context.mounted) return r.ok;
    final out = r.output.trim();
    toast(context, r.ok ? s['actionDone'] : s.f('opFailed', {'msg': out.isEmpty ? 'exit ${r.exitCode}' : out}));
    return r.ok;
  } catch (e) {
    if (context.mounted) toast(context, s.f('opFailed', {'msg': describeError(e, s)}));
    return false;
  }
}

// ---------------------------------------------------------------------------
// Status (polled)

class StatusTab extends StatefulWidget {
  const StatusTab({super.key, required this.conn, this.every = const Duration(seconds: 3)});
  final ToolConn conn;
  final Duration every;
  @override
  State<StatusTab> createState() => StatusTabState();
}

class StatusTabState extends State<StatusTab> with WidgetsBindingObserver {
  StatusSample? cur, prev;
  double? cpu;
  (double, double)? rate;
  final cpuHistory = <double>[];
  String? error;
  Timer? _timer;
  bool _busy = false;

  /// Number of finished polls (tests use it to see that polling stops).
  int polls = 0;

  bool get polling => _timer != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // no polling while the app is in the background
    if (state == AppLifecycleState.resumed) {
      if (error == null) _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _stop();
    }
  }

  void _start() {
    if (_timer != null) return;
    _poll();
    _timer = Timer.periodic(widget.every, (_) => _poll());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final r = await widget.conn.run(statusCommand, timeout: const Duration(seconds: 15));
      final sample = parseStatus(r.output);
      if (!mounted) return;
      setState(() {
        prev = cur;
        cur = sample;
        error = null;
        polls++;
        final a = prev?.cpu, b = sample.cpu;
        if (a != null && b != null) {
          cpu = b.usageSince(a);
          cpuHistory.add(cpu!);
          if (cpuHistory.length > 40) cpuHistory.removeAt(0);
        }
        if (prev != null) rate = netRate(prev!, sample);
      });
    } catch (e) {
      if (!mounted) return;
      _stop();
      setState(() => error = describeError(e, S.of(context)));
    } finally {
      _busy = false;
    }
  }

  void _retry() {
    setState(() => error = null);
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final c = cur;
    if (c == null && error != null) return ErrorRetry(message: error!, onRetry: _retry);
    if (c == null) return const Center(child: CircularProgressIndicator());
    final mem = c.mem;
    return ListView(key: const ValueKey('status-list'), padding: const EdgeInsets.fromLTRB(14, 2, 14, 40), children: [
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: p.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              leading: Icon(Icons.pause_circle_outline, color: p.red),
              title: Text(s.f('toolsFailed', {'msg': error!}), style: const TextStyle(fontSize: 13)),
              trailing: TextButton(onPressed: _retry, child: Text(s['retry'])),
            ),
          ),
        ),
      _Card(
        title: s['dashCpu'],
        trailing: Text(cpu == null ? s['dashMeasuring'] : _pct(cpu!),
            key: const ValueKey('dash-cpu'),
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontWeight: cpu == null ? FontWeight.w500 : FontWeight.w800,
                fontSize: cpu == null ? 13 : 18,
                color: cpu == null ? p.muted : _levelColor(p, cpu!))),
        children: [
          SizedBox(
            height: 46,
            child: CustomPaint(painter: _Spark(cpuHistory, p.accent, p.bg), size: Size.infinite),
          ),
          const SizedBox(height: 6),
          _KV(s['dashCoresLabel'], '${c.cpus}'),
          if (c.load != null)
            _KV(s['dashLoad'], c.load!.map((e) => e.toStringAsFixed(2)).join('  '), valueKey: const ValueKey('dash-load')),
        ],
      ),
      if (mem != null)
        _Card(
          title: s['dashMemory'],
          trailing: Text(_pct(mem.usedPct),
              key: const ValueKey('dash-ram'),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _levelColor(p, mem.usedPct))),
          children: [
            _Bar(mem.usedPct),
            const SizedBox(height: 6),
            _KV(s['dashRam'], '${formatKb(mem.used)} / ${formatKb(mem.total)}'),
            const SizedBox(height: 6),
            if (mem.swapTotal > 0) ...[
              _Bar(mem.swapPct),
              const SizedBox(height: 6),
              _KV(s['dashSwap'], '${formatKb(mem.swapUsed)} / ${formatKb(mem.swapTotal)}'),
            ] else
              _KV(s['dashSwap'], s['dashNoSwap']),
          ],
        ),
      _Card(title: s['dashNetwork'], children: [
        _KV('↓ ${s['dashDownload']}', rate == null ? '…' : '${formatBytes(rate!.$1)}/s',
            valueKey: const ValueKey('dash-rx')),
        _KV('↑ ${s['dashUpload']}', rate == null ? '…' : '${formatBytes(rate!.$2)}/s',
            valueKey: const ValueKey('dash-tx')),
      ]),
      if (c.disks.isNotEmpty)
        _Card(title: s['dashDisks'], children: [
          for (final d in c.disks) ...[
            Row(children: [
              Expanded(child: Ltr(d.mount, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Text('${formatKb(d.usedKb)} / ${formatKb(d.totalKb)} · ${_pct(d.usedPct)}',
                  textDirection: TextDirection.ltr, style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            _Bar(d.usedPct),
            const SizedBox(height: 10),
          ],
        ]),
      _Card(title: s['dashSystem'], children: [
        if (c.os.isNotEmpty) _KV(s['dashOs'], c.os, valueKey: const ValueKey('dash-os')),
        if (c.kernel.isNotEmpty) _KV(s['dashKernel'], c.kernel),
        if (c.uptime != null) _KV(s['dashUptime'], formatUptime(c.uptime!), valueKey: const ValueKey('dash-uptime')),
      ]),
    ]);
  }
}

class _Spark extends CustomPainter {
  _Spark(this.values, this.color, this.bg);
  final List<double> values;
  final Color color, bg;
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(r, Paint()..color = bg);
    if (values.length < 2) return;
    final n = math.max(values.length, 20);
    final dx = size.width / (n - 1);
    final x0 = size.width - dx * (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = x0 + dx * i, y = size.height - (values[i] / 100).clamp(0, 1) * (size.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(x0, size.height)
      ..close();
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Spark old) => true;
}

// ---------------------------------------------------------------------------
// Processes

class ProcessesTab extends StatefulWidget {
  const ProcessesTab({super.key, required this.conn});
  final ToolConn conn;
  @override
  State<ProcessesTab> createState() => _ProcessesTabState();
}

class _ProcessesTabState extends State<ProcessesTab> with _Loader<ProcessesTab, List<ProcInfo>> {
  ProcSort sort = ProcSort.cpu;

  @override
  Future<List<ProcInfo>> load() async => parsePs((await widget.conn.run(psCommand)).output);

  Future<void> _actions(ProcInfo pr) async {
    final s = S.of(context);
    final p = context.pal;
    final prot = isProtectedPid(pr.pid);
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Ltr('${pr.command}  (PID ${pr.pid})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          if (prot)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s['killProtected'], style: TextStyle(color: p.muted)),
            )
          else ...[
            ListTile(
                key: const ValueKey('kill-term'),
                leading: const Icon(Icons.stop_circle_outlined),
                title: Text(s['killTerm']),
                onTap: () => Navigator.pop(c, 'TERM')),
            ListTile(
                key: const ValueKey('kill-force'),
                leading: Icon(Icons.dangerous_outlined, color: p.red),
                title: Text(s['killForce'], style: TextStyle(color: p.red)),
                onTap: () => Navigator.pop(c, 'KILL')),
          ],
        ]),
      ),
    );
    if (v == null || prot || !mounted) return;
    final ok = await confirm(
        context, s['killTitle'], s.f('killBody', {'sig': 'SIG$v', 'name': pr.command, 'pid': pr.pid}),
        ok: v == 'KILL' ? s['killForceShort'] : s['killTermShort'], danger: true);
    if (!ok || !mounted) return;
    await _runAction(context, widget.conn, killCommand(pr.pid, force: v == 'KILL'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
        child: Row(children: [
          Expanded(
            child: SegmentedButton<ProcSort>(
              key: const ValueKey('proc-sort'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ProcSort.cpu, label: Text(s['sortCpu'])),
                ButtonSegment(value: ProcSort.mem, label: Text(s['sortRam'])),
              ],
              selected: {sort},
              onSelectionChanged: (v) => setState(() => sort = v.first),
            ),
          ),
          IconButton(tooltip: s['refresh'], icon: const Icon(Icons.refresh), onPressed: reload),
        ]),
      ),
      if (loading && data != null) LinearProgressIndicator(minHeight: 2, color: p.accent),
      Expanded(
        child: body((list) {
          final top = sortProcs(list, sort).take(60).toList();
          return ListView.separated(
            key: const ValueKey('proc-list'),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 40),
            itemCount: top.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 12, endIndent: 12),
            itemBuilder: (_, i) {
              final pr = top[i];
              return ListTile(
                key: ValueKey('proc-${pr.pid}'),
                dense: true,
                title: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr(pr.command, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                subtitle: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr('PID ${pr.pid} · ${privacyOn ? '•••' : pr.user}',
                        style: TextStyle(color: p.muted, fontSize: 12))),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${pr.cpu.toStringAsFixed(1)}%',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontWeight: sort == ProcSort.cpu ? FontWeight.w800 : FontWeight.w500,
                          color: sort == ProcSort.cpu ? p.text : p.muted)),
                  Text(formatKb(pr.rssKb),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: sort == ProcSort.mem ? FontWeight.w800 : FontWeight.w500,
                          color: sort == ProcSort.mem ? p.text : p.muted)),
                ]),
                onTap: () => _actions(pr),
              );
            },
          );
        }),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Services

class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key, required this.conn});
  final ToolConn conn;
  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> with _Loader<ServicesTab, ServicesSnapshot> {
  bool docker = false;
  bool runningOnly = false;
  String q = '';

  @override
  Future<ServicesSnapshot> load() async =>
      parseServices((await widget.conn.run(servicesCommand, timeout: const Duration(seconds: 30))).output);

  Future<void> _act({required String name, required bool isDocker, required String id}) async {
    final s = S.of(context);
    final p = context.pal;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Ltr(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          ListTile(
              key: const ValueKey('svc-logs'),
              leading: const Icon(Icons.article_outlined),
              title: Text(s['svcLogs']),
              onTap: () => Navigator.pop(c, 'logs')),
          ListTile(
              key: const ValueKey('svc-start'),
              leading: Icon(Icons.play_arrow_rounded, color: p.green),
              title: Text(s['svcStart']),
              onTap: () => Navigator.pop(c, 'start')),
          ListTile(
              key: const ValueKey('svc-restart'),
              leading: Icon(Icons.restart_alt, color: p.amber),
              title: Text(s['svcRestart']),
              onTap: () => Navigator.pop(c, 'restart')),
          ListTile(
              key: const ValueKey('svc-stop'),
              leading: Icon(Icons.stop_rounded, color: p.red),
              title: Text(s['svcStop'], style: TextStyle(color: p.red)),
              onTap: () => Navigator.pop(c, 'stop')),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'logs') {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LogViewerScreen(
              title: name,
              conn: widget.conn,
              command: isDocker ? dockerLogsCommand(id) : serviceLogsCommand(id))));
      return;
    }
    final body = switch (v) {
      'start' => s.f('svcConfirmStart', {'name': name}),
      'stop' => s.f('svcConfirmStop', {'name': name}),
      _ => s.f('svcConfirmRestart', {'name': name}),
    };
    final label = switch (v) { 'start' => s['svcStart'], 'stop' => s['svcStop'], _ => s['svcRestart'] };
    if (!await confirm(context, label, body, ok: label, danger: v != 'start') || !mounted) return;
    await _runAction(context, widget.conn, isDocker ? dockerActionCommand(id, v) : serviceActionCommand(id, v));
    if (mounted) reload();
  }

  Widget _dot(Palette p, bool running, bool failed) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: failed ? p.red : (running ? p.green : p.muted)),
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final snap = data;
    final showDocker = snap?.hasDocker ?? false;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
        child: Row(children: [
          if (showDocker)
            Expanded(
              child: SegmentedButton<bool>(
                key: const ValueKey('svc-kind'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(s['svcSystemd'])),
                  ButtonSegment(value: true, label: Text(s['svcDocker'])),
                ],
                selected: {docker},
                onSelectionChanged: (v) => setState(() => docker = v.first),
              ),
            )
          else
            Expanded(child: Text(s['svcSystemd'], style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(tooltip: s['refresh'], icon: const Icon(Icons.refresh), onPressed: reload),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('svc-filter'),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                  hintText: s['search'], isDense: true, prefixIcon: Icon(Icons.search, color: p.muted, size: 20)),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            key: const ValueKey('svc-running'),
            label: Text(s['svcRunningOnly']),
            selected: runningOnly,
            onSelected: (v) => setState(() => runningOnly = v),
          ),
        ]),
      ),
      if (loading && data != null) Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 2, color: p.accent)),
      Expanded(
        child: body((snap) {
          final items = <Widget>[];
          if (docker && snap.hasDocker) {
            if (snap.dockerError.isNotEmpty) {
              items.add(Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.f('svcDockerError', {'msg': snap.dockerError}), style: TextStyle(color: p.red)),
              ));
            }
            for (final c in snap.containers) {
              if (runningOnly && !c.running) continue;
              if (q.isNotEmpty && !'${c.name} ${c.image}'.toLowerCase().contains(q)) continue;
              items.add(ListTile(
                key: ValueKey('ctr-${c.name}'),
                dense: true,
                leading: _dot(p, c.running, c.state == 'exited' && !c.status.startsWith('Exited (0)')),
                title: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                subtitle: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr('${c.image} · ${c.status}', style: TextStyle(color: p.muted, fontSize: 12))),
                onTap: () => _act(name: c.name, isDocker: true, id: c.id),
              ));
            }
          } else {
            for (final u in snap.units) {
              if (runningOnly && !u.running) continue;
              if (q.isNotEmpty && !'${u.name} ${u.description}'.toLowerCase().contains(q)) continue;
              items.add(ListTile(
                key: ValueKey('svc-${u.name}'),
                dense: true,
                leading: _dot(p, u.running, u.failed),
                title: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr(u.name.replaceAll(RegExp(r'\.service$'), ''),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                subtitle: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr('${u.active}/${u.sub}${u.description.isEmpty ? '' : ' · ${u.description}'}',
                        style: TextStyle(color: u.failed ? p.red : p.muted, fontSize: 12))),
                onTap: () => _act(name: u.name, isDocker: false, id: u.name),
              ));
            }
          }
          return ListView(
            key: const ValueKey('svc-list'),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 40),
            children: items.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(s['nothingToShow'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                    )
                  ]
                : items,
          );
        }),
      ),
    ]);
  }
}

/// Last log lines of a service or container: scrollable LTR monospace text.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key, required this.title, required this.conn, required this.command});
  final String title;
  final ToolConn conn;
  final String command;
  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> with _Loader<LogViewerScreen, String> {
  final _v = ScrollController();

  @override
  Future<String> load() async => (await widget.conn.run(widget.command, timeout: const Duration(seconds: 30))).output;

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['svcLogs'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Ltr(widget.title, style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
        actions: [
          IconButton(
              tooltip: s['copy'],
              icon: const Icon(Icons.copy_all),
              onPressed: data == null ? null : () => _copy(context, data!)),
          IconButton(tooltip: s['refresh'], icon: const Icon(Icons.refresh), onPressed: reload),
        ],
        bottom: loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3, color: p.accent))
            : null,
      ),
      body: body((text) {
        final t = text.trim().isEmpty ? s['logsEmpty'] : text;
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scrollbar(
            controller: _v,
            child: SingleChildScrollView(
              key: const ValueKey('log-scroll'),
              controller: _v,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(t,
                    key: const ValueKey('log-text'),
                    style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, color: p.text, height: 1.35)),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Ports

class PortsTab extends StatefulWidget {
  const PortsTab({super.key, required this.conn});
  final ToolConn conn;
  @override
  State<PortsTab> createState() => _PortsTabState();
}

class _PortsTabState extends State<PortsTab> with _Loader<PortsTab, List<OpenPort>> {
  @override
  Future<List<OpenPort>> load() async => parseSs((await widget.conn.run(portsCommand)).output);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    return body((ports) {
      final noProc = ports.any((e) => e.process.isEmpty);
      return ListView(key: const ValueKey('ports-list'), padding: const EdgeInsets.fromLTRB(14, 8, 14, 40), children: [
        Row(children: [
          Expanded(
              child: Text(s.f('portsCount', {'n': s.num(ports.length)}),
                  style: TextStyle(color: p.muted, fontWeight: FontWeight.w700))),
          IconButton(tooltip: s['refresh'], icon: const Icon(Icons.refresh), onPressed: reload),
        ]),
        if (ports.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Text(s['portsNone'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
          ),
        if (ports.isNotEmpty)
          Section(children: [
            for (final o in ports)
              ListTile(
                key: ValueKey('port-${o.proto}-${o.port}-${o.address}'),
                dense: true,
                leading: Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                      color: (o.proto == 'tcp' ? p.accent : p.amber).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(o.proto.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: o.proto == 'tcp' ? p.accent : p.amber)),
                ),
                title: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Ltr('${o.port}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                subtitle: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Ltr(
                      '${privacyOn && !o.public && o.address != '127.0.0.1' && o.address != '::1' ? maskHost(o.address) : o.address}'
                      '${o.process.isEmpty ? '' : ' · ${o.process}${o.pid == null ? '' : ' (${o.pid})'}'}',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ),
                trailing: o.public
                    ? Tooltip(message: s['portsPublic'], child: Icon(Icons.public, color: p.amber, size: 20))
                    : Tooltip(message: s['portsLocal'], child: Icon(Icons.lock_outline, color: p.green, size: 20)),
              ),
          ]),
        if (noProc && ports.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(s['portsNoProcHint'], style: TextStyle(color: p.muted, fontSize: 12)),
          ),
      ]);
    });
  }
}

// ---------------------------------------------------------------------------
// Security check

class SecurityTab extends StatefulWidget {
  const SecurityTab({super.key, required this.conn});
  final ToolConn conn;
  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab> {
  List<AuditItem>? items;
  String? error;
  bool running = false;

  Future<void> _run() async {
    setState(() {
      running = true;
      error = null;
    });
    try {
      final r = await widget.conn.run(auditCommand, timeout: const Duration(seconds: 60));
      final list = parseAudit(r.output, sshPort: widget.conn.host.port);
      if (!mounted) return;
      setState(() {
        items = list;
        running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        running = false;
        error = describeError(e, S.of(context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    return ListView(key: const ValueKey('audit-list'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
      Text(s['auditIntro'], style: TextStyle(color: p.muted, fontSize: 13, height: 1.5)),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('audit-run'),
        onPressed: running ? null : _run,
        icon: running
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.shield_outlined),
        label: Text(items == null ? s['auditRun'] : s['auditRunAgain']),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(s.f('toolsFailed', {'msg': error!}), style: TextStyle(color: p.red)),
        ),
      for (final it in items ?? const <AuditItem>[]) _AuditCard(it),
    ]);
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard(this.it);
  final AuditItem it;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final (icon, color, status) = switch (it.level) {
      AuditLevel.ok => (Icons.check_circle, p.green, s['auditOk']),
      AuditLevel.warn => (Icons.warning_amber_rounded, p.amber, s['auditWarn']),
      AuditLevel.unknown => (Icons.help_outline, p.muted, s['auditUnknown']),
    };
    final title = switch (it.id) {
      'rootLogin' => s['auditRootLogin'],
      'passwordAuth' => s['auditPasswordAuth'],
      'firewall' => s['auditFirewall'],
      'fail2ban' => s['auditFail2ban'],
      _ => s['auditUpdates'],
    };
    final info = switch (it.id) {
      'rootLogin' => s['auditRootLoginInfo'],
      'passwordAuth' => s['auditPasswordAuthInfo'],
      'firewall' => s['auditFirewallInfo'],
      'fail2ban' => s['auditFail2banInfo'],
      _ => s['auditUpdatesInfo'],
    };
    return Container(
      key: ValueKey('audit-${it.id}'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
          Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(it.value,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: p.muted)),
        ),
        const SizedBox(height: 6),
        Text(info, style: const TextStyle(fontSize: 13, height: 1.5)),
        if (it.fix.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(s['auditFix'], style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 2, 6),
            decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(
                child: Text(it.fix,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, color: p.text)),
              ),
              IconButton(
                key: ValueKey('audit-copy-${it.id}'),
                tooltip: s['copy'],
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copy(context, it.fix),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
