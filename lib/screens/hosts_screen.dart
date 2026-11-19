import 'package:flutter/material.dart';

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
          appBar: AppBar(title: const Text('سرورها')),
          floatingActionButton: FloatingActionButton(
            heroTag: 'fab_hosts',
            onPressed: () => _edit(null),
            backgroundColor: C.accent,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
          body: Store.i.hosts.isEmpty && sessions.isEmpty
              ? _empty()
              : ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 100), children: [
                  TextField(
                    onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'جستجوی سرور…',
                      prefixIcon: Icon(Icons.search, color: C.muted),
                    ),
                  ),
                  if (sessions.isNotEmpty)
                    Section(title: 'نشست‌های باز', children: [
                      for (final s in sessions)
                        ListTile(
                          leading: HostAvatar(color: s.host.color, live: s.status == SessStatus.connected),
                          title: Text(s.host.label.isEmpty ? s.host.host : s.host.label),
                          subtitle: Text(_status(s), style: TextStyle(color: _statusColor(s), fontSize: 12.5)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: C.muted),
                            onPressed: () => Sessions.i.close(s),
                          ),
                          onTap: () => openSession(context, s),
                        ),
                    ]),
                  if (hosts.isNotEmpty)
                    Section(title: 'همه سرورها', children: [
                      for (final h in hosts)
                        ListTile(
                          contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
                          leading: HostAvatar(color: h.color),
                          title: Text(h.label.isEmpty ? h.host : h.label,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Ltr('ssh ${h.address}', style: const TextStyle(color: C.muted, fontSize: 12.5)),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: C.muted),
                            onSelected: (v) => _menu(v, h),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                              PopupMenuItem(value: 'dup', child: Text('کپی از این سرور')),
                              PopupMenuItem(value: 'del', child: Text('حذف', style: TextStyle(color: C.red))),
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

  String _status(TermSession s) => switch (s.status) {
        SessStatus.connecting => 'در حال اتصال…',
        SessStatus.connected => 'وصل',
        SessStatus.closed => 'قطع شده',
        SessStatus.failed => s.error ?? 'خطا',
      };

  Color _statusColor(TermSession s) => switch (s.status) {
        SessStatus.connecting => C.amber,
        SessStatus.connected => C.green,
        _ => C.red,
      };

  Widget _empty() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(26)),
              child: const Icon(Icons.terminal_rounded, size: 42, color: C.green),
            ),
            const SizedBox(height: 20),
            const Text('هنوز سروری اضافه نکرده‌اید',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.text)),
            const SizedBox(height: 8),
            const Text('آی‌پی، نام کاربری و رمز یا کلید سرورتان را وارد کنید و با یک لمس وصل شوید.',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.6)),
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('افزودن سرور')),
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
      final ok = await confirm(context, 'حذف سرور', '«${h.label.isEmpty ? h.host : h.label}» و رمزش از گوشی پاک شود؟',
          ok: 'حذف', danger: true);
      if (ok) await Store.i.deleteHost(h);
    }
  }
}
