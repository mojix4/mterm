import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../session.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';
import 'host_edit_screen.dart';

class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});
  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Store.i, Sessions.i]),
      builder: (context, _) {
        final s = S.of(context);
        final p = context.pal;
        final sessions = Sessions.i.list;
        final hosts = Store.i.hosts
            .where((h) =>
                q.isEmpty ||
                h.label.toLowerCase().contains(q) ||
                h.host.toLowerCase().contains(q) ||
                h.user.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => (b.lastUsed ?? '').compareTo(a.lastUsed ?? ''));
        return Scaffold(
          appBar: AppBar(title: Text(s['navHosts'])),
          floatingActionButton: FloatingActionButton(
            heroTag: 'fab_hosts',
            onPressed: () => _edit(null),
            backgroundColor: p.accent,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
          body: Store.i.hosts.isEmpty && sessions.isEmpty
              ? _empty(s, p)
              : ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 100), children: [
                  TextField(
                    onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: s['searchHosts'],
                      prefixIcon: Icon(Icons.search, color: p.muted),
                    ),
                  ),
                  if (sessions.isNotEmpty)
                    Section(title: s['openSessions'], children: [
                      for (final ss in sessions)
                        ListTile(
                          leading: HostAvatar(color: ss.host.color, live: ss.status == SessStatus.connected),
                          title: Text(ss.host.label.isEmpty ? ss.host.host : ss.host.label),
                          subtitle: Text(_status(s, ss), style: TextStyle(color: _statusColor(p, ss), fontSize: 12.5)),
                          trailing: IconButton(
                            icon: Icon(Icons.close, color: p.muted),
                            onPressed: () => Sessions.i.close(ss),
                          ),
                          onTap: () => openSession(context, ss),
                        ),
                    ]),
                  if (hosts.isNotEmpty)
                    Section(title: s['allHosts'], children: [
                      for (final h in hosts)
                        ListTile(
                          contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
                          leading: HostAvatar(color: h.color),
                          title: Text(h.label.isEmpty ? h.host : h.label,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Ltr('ssh ${h.address}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: p.muted),
                            onSelected: (v) => _menu(v, h),
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'edit', child: Text(s['edit'])),
                              PopupMenuItem(value: 'dup', child: Text(s['duplicateHost'])),
                              PopupMenuItem(value: 'del', child: Text(s['delete'], style: TextStyle(color: p.red))),
                            ],
                          ),
                          onTap: () => openHost(context, h),
                        ),
                    ]),
                ]),
        );
      },
    );
  }

  String _status(S s, TermSession ss) => switch (ss.status) {
        SessStatus.connecting => s['statusConnecting'],
        SessStatus.connected => s['statusConnected'],
        SessStatus.closed => s['statusClosed'],
        SessStatus.failed => ss.errorIn(s) ?? s['statusError'],
      };

  Color _statusColor(Palette p, TermSession ss) => switch (ss.status) {
        SessStatus.connecting => p.amber,
        SessStatus.connected => p.green,
        _ => p.red,
      };

  Widget _empty(S s, Palette p) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(26)),
              child: Icon(Icons.terminal_rounded, size: 42, color: p.green),
            ),
            const SizedBox(height: 20),
            Text(s['emptyTitle'],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 8),
            Text(s['emptyBody'], textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.6)),
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: () => _edit(null), icon: const Icon(Icons.add), label: Text(s['addHost'])),
          ]),
        ),
      );

  Future<void> _edit(Host? h, {bool duplicate = false}) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => HostEditScreen(host: h, duplicate: duplicate)));
  }

  Future<void> _menu(String v, Host h) async {
    if (v == 'edit') return _edit(h);
    if (v == 'dup') return _edit(h, duplicate: true);
    if (v == 'del') {
      final s = S.of(context);
      final ok = await confirm(
          context, s['deleteHostTitle'], s.f('deleteHostBody', {'name': h.label.isEmpty ? h.host : h.label}),
          ok: s['delete'], danger: true);
      if (ok) await Store.i.deleteHost(h);
    }
  }
}
