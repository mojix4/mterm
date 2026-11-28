// Multi-server broadcast: run one command on several saved servers at once
// and show each server's output in its own card.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../models.dart';
import '../privacy.dart';
import '../server_tools.dart';
import '../session.dart';
import '../store.dart';
import '../themes.dart';
import '../tool_conn.dart';
import 'common.dart';

Future<void> openBroadcast(BuildContext context, {String command = ''}) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => BroadcastScreen(initialCommand: command)));

/// One server's run.
class BroadcastResult {
  BroadcastResult(this.host);
  final Host host;
  bool running = true;
  String output = '';
  int? exitCode;
  String? error;
}

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key, this.initialCommand = '', this.keyPrompt, this.pwPrompt, this.connFor});
  final String initialCommand;
  final HostKeyPrompt? keyPrompt;
  final PasswordPrompt? pwPrompt;

  /// Test hook: makes the connection for a server.
  final ToolConn Function(Host h)? connFor;
  @override
  State<BroadcastScreen> createState() => BroadcastScreenState();
}

class BroadcastScreenState extends State<BroadcastScreen> {
  late final cmd = TextEditingController(text: widget.initialCommand);
  final selected = <String>{};
  final results = <BroadcastResult>[];
  final _conns = <String, ToolConn>{};
  bool running = false;

  @override
  void dispose() {
    for (final c in _conns.values) {
      c.close();
    }
    cmd.dispose();
    super.dispose();
  }

  List<Host> get _hosts => List.of(Store.i.hosts)..sort((a, b) => hostTitle(a).compareTo(hostTitle(b)));

  ToolConn _conn(Host h) => _conns.putIfAbsent(
      h.id,
      () =>
          widget.connFor?.call(h) ??
          ToolConn(h,
          hostKeyPrompt: widget.keyPrompt ?? hostKeyPrompt, passwordPrompt: widget.pwPrompt ?? passwordPrompt));

  /// Runs the command on every selected server (all at once).
  Future<void> run() async {
    final s = S.of(context);
    final c = cmd.text.trim();
    final hosts = _hosts.where((h) => selected.contains(h.id)).toList();
    if (c.isEmpty || hosts.isEmpty || running) return;
    FocusScope.of(context).unfocus();
    if (isDestructiveCommand(c) &&
        !await confirm(context, s['bcDangerTitle'], s.f('bcDangerBody', {'n': s.num(hosts.length), 'cmd': c}),
            ok: s['bcRunAnyway'], danger: true)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      running = true;
      results
        ..clear()
        ..addAll(hosts.map(BroadcastResult.new));
    });
    await Future.wait(results.map((r) async {
      try {
        final out = await _conn(r.host).run(c, timeout: const Duration(seconds: 120));
        r.output = out.output;
        r.exitCode = out.exitCode;
      } catch (e) {
        r.error = describeError(e, s);
      }
      r.running = false;
      if (mounted) setState(() {});
    }));
    if (mounted) setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final hosts = _hosts;
    final n = hosts.where((h) => selected.contains(h.id)).length;
    return Scaffold(
      appBar: AppBar(title: Text(s['broadcast'])),
      body: hosts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(s['bcNoHosts'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
              ),
            )
          : ListView(key: const ValueKey('bc-list'), padding: const EdgeInsets.fromLTRB(14, 0, 14, 40), children: [
              Text(s['bcIntro'], style: TextStyle(color: p.muted, fontSize: 13, height: 1.5)),
              Section(title: s['bcPickHosts'], children: [
                CheckboxListTile(
                  key: const ValueKey('bc-all'),
                  value: n == hosts.length ? true : (n == 0 ? false : null),
                  tristate: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(s['bcSelectAll'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  onChanged: running
                      ? null
                      : (_) => setState(() {
                            if (n == hosts.length) {
                              selected.clear();
                            } else {
                              selected.addAll(hosts.map((h) => h.id));
                            }
                          }),
                ),
                for (final h in hosts)
                  CheckboxListTile(
                    key: ValueKey('bc-host-${h.id}'),
                    value: selected.contains(h.id),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(hostTitle(h), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Ltr(hostAddress(h), style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                    onChanged: running
                        ? null
                        : (v) => setState(() => v == true ? selected.add(h.id) : selected.remove(h.id)),
                  ),
              ]),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('bc-command'),
                controller: cmd,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
                decoration: InputDecoration(labelText: s['bcCommand'], hintText: 'uptime'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('bc-run'),
                onPressed: running || n == 0 || cmd.text.trim().isEmpty ? null : run,
                icon: running
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(s.f('bcRun', {'n': s.num(n)})),
              ),
              for (final r in results) _ResultCard(r),
            ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(this.r);
  final BroadcastResult r;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final failed = r.error != null || (r.exitCode != null && r.exitCode != 0);
    final status = r.running
        ? s['bcRunning']
        : r.error != null
            ? s['statusError']
            : s.f('bcExit', {'code': '${r.exitCode ?? '?'}'});
    final text = r.error ?? (r.output.trim().isEmpty ? s['bcNoOutput'] : r.output.trimRight());
    return Container(
      key: ValueKey('bc-result-${r.host.id}'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: r.running ? p.surface : (failed ? p.red : p.green).withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(hostTitle(r.host),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (r.running)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Text(status, style: TextStyle(color: r.running ? p.muted : (failed ? p.red : p.green), fontSize: 12)),
          IconButton(
            key: ValueKey('bc-copy-${r.host.id}'),
            tooltip: s['copy'],
            icon: const Icon(Icons.copy, size: 18),
            onPressed: r.running
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: r.error ?? r.output));
                    if (context.mounted) toast(context, s['copied']);
                  },
          ),
        ]),
        if (!r.running)
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            margin: const EdgeInsetsDirectional.only(end: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(text,
                    key: ValueKey('bc-output-${r.host.id}'),
                    style: TextStyle(
                        fontFamily: 'JetBrainsMono', fontSize: 11.5, color: r.error != null ? p.red : p.text)),
              ),
            ),
          ),
      ]),
    );
  }
}
