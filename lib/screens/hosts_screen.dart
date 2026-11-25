import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../session.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';
import 'files_screen.dart';
import 'host_edit_screen.dart';
import 'quick_connect.dart';

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
        final hosts = Store.i.hosts.where((h) => hostMatches(h, q)).toList()
          ..sort((a, b) => (b.lastUsed ?? '').compareTo(a.lastUsed ?? ''));
        final groups = groupHosts(hosts);
        return Scaffold(
          appBar: AppBar(title: Text(s['navHosts']), actions: [
            IconButton(
              key: const ValueKey('quick-connect'),
              tooltip: s['quickConnect'],
              icon: const Icon(Icons.flash_on_rounded),
              onPressed: () => quickConnect(context),
            ),
            const SizedBox(width: 4),
          ]),
          floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(
              key: const ValueKey('fab-quick-connect'),
              heroTag: 'fab_quick',
              tooltip: s['quickConnect'],
              onPressed: () => quickConnect(context),
              backgroundColor: p.surface2,
              foregroundColor: p.accent,
              child: const Icon(Icons.flash_on_rounded),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              key: const ValueKey('fab-add-host'),
              heroTag: 'fab_hosts',
              tooltip: s['addHost'],
              onPressed: () => _edit(null),
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
          ]),
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
                  if (hosts.isEmpty && q.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(s['noMatches'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                    ),
                  for (final g in groups.entries)
                    Section(
                      key: ValueKey('group-${g.key}'),
                      title: g.key.isNotEmpty ? g.key : (groups.length > 1 ? s['otherHosts'] : s['allHosts']),
                      children: [for (final h in g.value) _hostTile(s, p, h)],
                    ),
                ]),
        );
      },
    );
  }

  Widget _hostTile(S s, Palette p, Host h) => ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
        leading: HostAvatar(color: h.color),
        title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Ltr('ssh ${h.address}', style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
          if (h.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final t in h.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
                    child: Text(t, style: TextStyle(color: p.accent, fontSize: 11)),
                  ),
              ]),
            ),
        ]),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: p.muted),
          onSelected: (v) => _menu(v, h),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(s['edit'])),
            PopupMenuItem(value: 'files', child: Text(s['navFiles'])),
            PopupMenuItem(value: 'dup', child: Text(s['duplicateHost'])),
            PopupMenuItem(value: 'del', child: Text(s['delete'], style: TextStyle(color: p.red))),
          ],
        ),
        onTap: () => openHost(context, h),
      );

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
            const SizedBox(height: 10),
            OutlinedButton.icon(
                key: const ValueKey('empty-quick-connect'),
                onPressed: () => quickConnect(context),
                icon: const Icon(Icons.flash_on_rounded),
                label: Text(s['quickConnect'])),
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
    if (v == 'files') return openFiles(context, h);
    if (v == 'del') {
      final s = S.of(context);
      final ok = await confirm(
          context, s['deleteHostTitle'], s.f('deleteHostBody', {'name': h.label.isEmpty ? h.host : h.label}),
          ok: s['delete'], danger: true);
      if (ok) await Store.i.deleteHost(h);
    }
  }
}

/// Search over name, address, user, group and tags ([q] is lower-case).
bool hostMatches(Host h, String q) {
  if (q.isEmpty) return true;
  bool has(String v) => v.toLowerCase().contains(q);
  return has(h.label) || has(h.host) || has(h.user) || has(h.group) || h.tags.any(has);
}

/// Hosts by group name (sorted), ungrouped ('') last; order inside kept.
Map<String, List<Host>> groupHosts(List<Host> hosts) {
  final m = <String, List<Host>>{};
  for (final h in hosts) {
    m.putIfAbsent(h.group.trim(), () => []).add(h);
  }
  final keys = m.keys.where((k) => k.isNotEmpty).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return {for (final k in keys) k: m[k]!, if (m.containsKey('')) '': m['']!};
}
