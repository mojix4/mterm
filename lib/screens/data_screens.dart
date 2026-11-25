// Settings sub-screens about the user's data: session logs, backup / restore.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../backup.dart';
import '../device_files.dart';
import '../l10n.dart';
import '../session_log.dart';
import '../sftp_ops.dart' show formatSize;
import '../themes.dart';
import 'common.dart';

/// Saved session logs with view / share / save / delete.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<File>? logs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<File> l;
    try {
      l = await listLogs();
    } catch (_) {
      l = [];
    }
    if (mounted) setState(() => logs = l);
  }

  String _name(File f) => f.uri.pathSegments.last;

  Future<void> _delete(File f) async {
    final s = S.of(context);
    if (!await confirm(context, s['delete'], s.f('deleteFileBody', {'name': _name(f)}), ok: s['delete'], danger: true)) {
      return;
    }
    try {
      await f.delete();
    } catch (_) {}
    await _load();
  }

  Future<void> _deleteAll() async {
    final s = S.of(context);
    if (!await confirm(context, s['deleteAllLogs'], s['deleteAllLogsBody'], ok: s['delete'], danger: true)) return;
    for (final f in logs ?? <File>[]) {
      try {
        await f.delete();
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _save(File f) async {
    final s = S.of(context);
    try {
      final where = await saveToDevice(_name(f), await f.readAsBytes());
      if (where != null && mounted) toast(context, s.f('savedTo', {'path': where}));
    } catch (e) {
      if (mounted) toast(context, s.f('opFailed', {'msg': '$e'}));
    }
  }

  Future<void> _view(File f) async {
    final bytes = await f.readAsBytes();
    // very long logs: show the end
    final tail = bytes.length > 2000000 ? bytes.sublist(bytes.length - 2000000) : bytes;
    final text = utf8.decode(tail, allowMalformed: true);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (c) => Scaffold(
        appBar: AppBar(title: Ltr(_name(f), style: const TextStyle(fontSize: 15))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            text,
            key: const ValueKey('log-text'),
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final l = logs;
    return Scaffold(
      appBar: AppBar(title: Text(s['sessionLogs']), actions: [
        if (l != null && l.isNotEmpty)
          IconButton(tooltip: s['deleteAllLogs'], icon: const Icon(Icons.delete_sweep_outlined), onPressed: _deleteAll),
      ]),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : l.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(s['noLogs'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 40), children: [
                  Section(children: [
                    for (final f in l)
                      ListTile(
                        key: ValueKey('log-${_name(f)}'),
                        leading: Icon(Icons.description_outlined, color: p.muted),
                        title: Align(alignment: AlignmentDirectional.centerStart, child: Ltr(_name(f))),
                        subtitle: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Ltr(formatSize(f.lengthSync()), style: TextStyle(color: p.muted, fontSize: 12)),
                        ),
                        onTap: () => _view(f),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: p.muted),
                          onSelected: (v) {
                            switch (v) {
                              case 'share':
                                shareFile(f.path);
                              case 'save':
                                _save(f);
                              case 'delete':
                                _delete(f);
                            }
                          },
                          itemBuilder: (_) => [
                            if (canShareFiles) PopupMenuItem(value: 'share', child: Text(s['share'])),
                            PopupMenuItem(value: 'save', child: Text(s['saveToDevice'])),
                            PopupMenuItem(
                                value: 'delete', child: Text(s['delete'], style: TextStyle(color: p.red))),
                          ],
                        ),
                      ),
                  ]),
                ]),
    );
  }
}

/// Asks for the backup password ([twice]: with confirmation, for export).
Future<String?> askBackupPassword(BuildContext context, {required bool twice}) {
  final s = S.of(context);
  final a = TextEditingController(), b = TextEditingController();
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      title: Text(s['backupPassword']),
      content: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(twice ? s['backupPasswordHint'] : s['restorePasswordHint'],
              style: TextStyle(color: c.pal.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('backup-pw'),
            controller: a,
            obscureText: true,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: s['password']),
            validator: (v) => twice && (v ?? '').length < 6 ? s['backupPasswordShort'] : null,
          ),
          if (twice) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('backup-pw2'),
              controller: b,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: s['repeatPassword']),
              validator: (v) => v != a.text ? s['passwordsDontMatch'] : null,
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(s['cancel'])),
        TextButton(
          key: const ValueKey('backup-pw-ok'),
          onPressed: () {
            if (!form.currentState!.validate() || a.text.isEmpty) return;
            Navigator.pop(c, a.text);
          },
          child: Text(s['ok']),
        ),
      ],
    ),
  );
}

Future<T?> _withProgress<T>(BuildContext context, Future<T> Function() work) async {
  final s = S.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 16),
        Expanded(child: Text(s['pleaseWait'])),
      ]),
    ),
  );
  try {
    return await work();
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }
}

Future<void> exportBackup(BuildContext context) async {
  final s = S.of(context);
  final pw = await askBackupPassword(context, twice: true);
  if (pw == null || !context.mounted) return;
  try {
    final bytes = await _withProgress(context, () => createBackup(pw));
    if (bytes == null || !context.mounted) return;
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'mterm-backup-${t.year}${two(t.month)}${two(t.day)}.mterm';
    final where = await saveToDevice(name, bytes);
    if (where != null && context.mounted) toast(context, s.f('savedTo', {'path': where}));
  } catch (e) {
    if (context.mounted) toast(context, s.f('opFailed', {'msg': '$e'}));
  }
}

Future<void> importBackup(BuildContext context) async {
  final s = S.of(context);
  final picked = await pickFromDevice();
  if (picked == null || !context.mounted) return;
  Uint8List data;
  try {
    data = picked.bytes ?? await File(picked.path!).readAsBytes();
  } catch (e) {
    if (context.mounted) toast(context, s.f('opFailed', {'msg': '$e'}));
    return;
  }
  if (!context.mounted) return;
  final pw = await askBackupPassword(context, twice: false);
  if (pw == null || !context.mounted) return;
  Map<String, dynamic>? j;
  try {
    j = await _withProgress(context, () => readBackup(data, pw));
  } on BackupError catch (e) {
    if (context.mounted) toast(context, s[e.wrongPassword ? 'backupWrongPassword' : 'backupInvalid']);
    return;
  }
  if (j == null || !context.mounted) return;
  final mode = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(s['restoreTitle']),
      content: Text(s['restoreBody']),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(s['cancel'])),
        TextButton(
            key: const ValueKey('restore-merge'),
            onPressed: () => Navigator.pop(c, 'merge'),
            child: Text(s['restoreMerge'])),
        TextButton(
          key: const ValueKey('restore-replace'),
          onPressed: () => Navigator.pop(c, 'replace'),
          child: Text(s['restoreReplace'], style: TextStyle(color: c.pal.red, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return;
  final r = await applyBackup(j, replace: mode == 'replace');
  if (context.mounted) toast(context, s.f('restored', {'n': s.num(r.hosts)}));
}
