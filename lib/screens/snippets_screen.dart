import 'package:flutter/material.dart';

import '../models.dart';
import '../session.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';

class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key});
  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final items = Store.i.snippets
            .where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.cmd.toLowerCase().contains(q))
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('دستورها')),
          floatingActionButton: FloatingActionButton(
            heroTag: 'fab_snips',
            onPressed: () => edit(context, null),
            backgroundColor: C.accent,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 100), children: [
            TextField(
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'جستجو…', prefixIcon: Icon(Icons.search, color: C.muted)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 14, 8, 0),
              child: Text('دستورهای پرکاربرد را ذخیره کنید و داخل ترمینال با دکمه ⚡ اجرا کنید.',
                  style: TextStyle(color: C.muted, fontSize: 12.5)),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Text('چیزی پیدا نشد', textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              )
            else
              Section(children: [
                for (final s in items)
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: C.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.bolt, color: C.amber),
                    ),
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Ltr(s.cmd,
                          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: C.muted)),
                    ),
                    trailing: const Icon(Icons.play_arrow_rounded, color: C.green),
                    onTap: () => _run(s),
                    onLongPress: () => edit(context, s),
                  ),
              ]),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('برای ویرایش یا حذف، روی دستور نگه دارید.',
                  textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12)),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _run(Snippet sn) async {
    final live = Sessions.i.list.where((s) => s.status == SessStatus.connected).toList();
    if (live.isEmpty) {
      toast(context, 'اول از بخش سرورها به یک سرور وصل شوید');
      return;
    }
    TermSession? target = live.length == 1 ? live.first : null;
    target ??= await showModalBottomSheet<TermSession>(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اجرا روی کدام سرور؟', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final s in live)
            ListTile(
              leading: HostAvatar(color: s.host.color, live: true, size: 38),
              title: Text(s.host.label.isEmpty ? s.host.host : s.host.label),
              onTap: () => Navigator.pop(c, s),
            ),
          const SizedBox(height: 12),
        ])),
      ),
    );
    if (target == null || !mounted) return;
    openSession(context, target);
    target.run(sn.cmd);
  }

  static Future<void> edit(BuildContext context, Snippet? s) async {
    final name = TextEditingController(text: s?.name ?? '');
    final cmd = TextEditingController(text: s?.cmd ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s == null ? 'دستور جدید' : 'ویرایش دستور',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'نام', hintText: 'مثلاً ری‌استارت xray')),
          const SizedBox(height: 12),
          TextField(
            controller: cmd,
            textDirection: TextDirection.ltr,
            minLines: 2,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13.5),
            decoration: const InputDecoration(labelText: 'دستور', hintText: 'systemctl restart xray'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty || cmd.text.trim().isEmpty) return;
              await Store.i.upsertSnippet(
                  Snippet(id: s?.id ?? newId(), name: name.text.trim(), cmd: cmd.text.trim()));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('ذخیره'),
          ),
          if (s != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await Store.i.deleteSnippet(s);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('حذف', style: TextStyle(color: C.red)),
            ),
          ],
        ]),
      ),
    );
  }
}
