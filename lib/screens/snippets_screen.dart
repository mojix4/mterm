import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../builtin_commands.dart';
import '../l10n.dart';
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

  /// false = the user's own commands, true = the built-in ready commands.
  bool ready = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final s = S.of(context);
        final p = context.pal;
        return Scaffold(
          appBar: AppBar(title: Text(s['navSnippets'])),
          floatingActionButton: ready
              ? null
              : FloatingActionButton(
                  heroTag: 'fab_snips',
                  onPressed: () => edit(context, null),
                  backgroundColor: p.accent,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add),
                ),
          body: ListView(
              key: const ValueKey('snippets-list'),
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(s['myCommands']), icon: const Icon(Icons.bolt)),
                    ButtonSegment(value: true, label: Text(s['readyCommands']), icon: const Icon(Icons.auto_awesome)),
                  ],
                  selected: {ready},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => ready = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
                  decoration: InputDecoration(hintText: s['search'], prefixIcon: Icon(Icons.search, color: p.muted)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
                  child: Text(ready ? s['readyHint'] : s['snippetsHint'],
                      style: TextStyle(color: p.muted, fontSize: 12.5)),
                ),
                if (ready) ..._readyList(s, p) else ..._myList(s, p),
              ]),
        );
      },
    );
  }

  List<Widget> _myList(S s, Palette p) {
    final items = Store.i.snippets
        .where((x) => q.isEmpty || x.name.toLowerCase().contains(q) || x.cmd.toLowerCase().contains(q))
        .toList();
    return [
      if (items.isEmpty)
        _nothing(s, p)
      else
        Section(children: [
          for (final sn in items)
            ListTile(
              leading: _bolt(p),
              title: Text(sn.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Ltr(sn.cmd, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: p.muted)),
              ),
              trailing: Icon(Icons.play_arrow_rounded, color: p.green),
              onTap: () => _run(sn.cmd),
              onLongPress: () => edit(context, sn),
            ),
        ]),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(s['holdToEdit'], textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12)),
      ),
    ];
  }

  List<Widget> _readyList(S s, Palette p) {
    bool match(BuiltinCommand c) =>
        q.isEmpty ||
        builtinTitle(s.code, c).toLowerCase().contains(q) ||
        builtinDesc(s.code, c).toLowerCase().contains(q) ||
        c.cmd.toLowerCase().contains(q);
    final out = <Widget>[];
    for (final cat in builtinCategories) {
      final items = builtinCommands.where((c) => c.category == cat && match(c)).toList();
      if (items.isEmpty) continue;
      out.add(Section(title: builtinCategory(s.code, cat), children: [
        for (final c in items)
          ListTile(
            key: ValueKey('builtin-${c.id}'),
            leading: _bolt(p, ready: true),
            title: Text(builtinTitle(s.code, c), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(builtinDesc(s.code, c),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
              const SizedBox(height: 2),
              // Commands are always left-to-right, even in fa/ar.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Ltr(c.cmd, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, color: p.muted)),
              ),
            ]),
            trailing: Icon(Icons.more_horiz, color: p.muted),
            onTap: () => _builtinActions(c),
          ),
      ]));
    }
    if (out.isEmpty) out.add(_nothing(s, p));
    return out;
  }

  Widget _nothing(S s, Palette p) => Padding(
        padding: const EdgeInsets.all(40),
        child: Text(s['nothingFound'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
      );

  Widget _bolt(Palette p, {bool ready = false}) {
    final c = ready ? p.accent : p.amber;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Icon(ready ? Icons.auto_awesome : Icons.bolt, color: c),
    );
  }

  /// Run / copy / save-to-mine sheet for a built-in command.
  Future<void> _builtinActions(BuiltinCommand c) async {
    final s = S.of(context);
    final p = context.pal;
    final title = builtinTitle(s.code, c);
    final v = await showModalBottomSheet<String>(
      context: context,
      // grow to fit long commands so the actions never end up below the fold
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(builtinDesc(s.code, c), style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(c.cmd,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12.5, color: p.text)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.play_arrow_rounded, color: p.green),
              title: Text(s['run']),
              onTap: () => Navigator.pop(ctx, 'run'),
            ),
            ListTile(
              leading: Icon(Icons.copy, color: p.muted),
              title: Text(s['copy']),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: Icon(Icons.bookmark_add_outlined, color: p.accent),
              title: Text(s['saveToMine']),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'run':
        await _run(c.cmd, confirmFirst: c.confirm);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: c.cmd));
        if (mounted) toast(context, s['copied']);
      case 'save':
        await Store.i.upsertSnippet(Snippet(id: newId(), name: title, cmd: c.cmd));
        if (mounted) toast(context, s['savedToMine']);
    }
  }

  Future<void> _run(String cmd, {bool confirmFirst = false}) async {
    final s = S.of(context);
    final live = Sessions.i.list.where((x) => x.status == SessStatus.connected).toList();
    if (live.isEmpty) {
      toast(context, s['connectFirst']);
      return;
    }
    TermSession? target = live.length == 1 ? live.first : null;
    target ??= await showModalBottomSheet<TermSession>(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s['runOnWhich'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final x in live)
            ListTile(
              leading: HostAvatar(color: x.host.color, live: true, size: 38),
              title: Text(x.host.label.isEmpty ? x.host.host : x.host.label),
              onTap: () => Navigator.pop(c, x),
            ),
          const SizedBox(height: 12),
        ])),
      ),
    );
    if (target == null || !mounted) return;
    if (confirmFirst) {
      final name = target.host.label.isEmpty ? target.host.host : target.host.label;
      final ok = await confirm(context, s['confirmRunTitle'], s.f('confirmRunBody', {'server': name}), ok: s['run']);
      if (!ok || !mounted) return;
    }
    openSession(context, target);
    target.run(cmd);
  }

  static Future<void> edit(BuildContext context, Snippet? sn) async {
    final s = S.of(context);
    final p = context.pal;
    final name = TextEditingController(text: sn?.name ?? '');
    final cmd = TextEditingController(text: sn?.cmd ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(sn == null ? s['newSnippet'] : s['editSnippet'],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: InputDecoration(labelText: s['name'], hintText: s['nameHint'])),
          const SizedBox(height: 12),
          TextField(
            controller: cmd,
            textDirection: TextDirection.ltr,
            minLines: 2,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13.5),
            decoration: InputDecoration(labelText: s['command'], hintText: 'systemctl restart xray'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty || cmd.text.trim().isEmpty) return;
              await Store.i.upsertSnippet(Snippet(id: sn?.id ?? newId(), name: name.text.trim(), cmd: cmd.text.trim()));
              if (c.mounted) Navigator.pop(c);
            },
            child: Text(s['save']),
          ),
          if (sn != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await Store.i.deleteSnippet(sn);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(s['delete'], style: TextStyle(color: p.red)),
            ),
          ],
        ]),
      ),
    );
  }
}
