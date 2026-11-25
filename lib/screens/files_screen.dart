// Files section: pick a saved server, then browse, download, upload, rename,
// delete and edit its files over SFTP (same login as the terminal).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../device_files.dart';
import '../l10n.dart';
import '../models.dart';
import '../session.dart';
import '../sftp_ops.dart';
import '../ssh_connect.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';

/// The bottom-nav tab: list of saved servers to open in the file manager.
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final s = S.of(context);
        final p = context.pal;
        final hosts = List.of(Store.i.hosts)..sort((a, b) => (b.lastUsed ?? '').compareTo(a.lastUsed ?? ''));
        return Scaffold(
          appBar: AppBar(title: Text(s['navFiles'])),
          body: hosts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.folder_open_rounded, size: 56, color: p.muted),
                      const SizedBox(height: 14),
                      Text(s['filesNoHosts'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 40), children: [
                  Section(title: s['filesPickHost'], children: [
                    for (final h in hosts)
                      ListTile(
                        key: ValueKey('files-host-${h.id}'),
                        leading: HostAvatar(color: h.color),
                        title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Ltr('sftp ${h.address}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ),
                        trailing: Icon(Icons.chevron_right, color: p.muted),
                        onTap: () => openFiles(context, h),
                      ),
                  ]),
                ]),
        );
      },
    );
  }
}

/// Opens the file manager for [h]. With a live [session] its connection is
/// reused, so there is no second login.
Future<void> openFiles(BuildContext context, Host h, {TermSession? session}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SftpBrowser(host: h, client: session?.client)));

class SftpBrowser extends StatefulWidget {
  const SftpBrowser({super.key, required this.host, this.client, this.keyPrompt, this.pwPrompt});
  final Host host;

  /// An already logged-in connection (from the terminal); null = log in here.
  final SSHClient? client;
  final HostKeyPrompt? keyPrompt;
  final PasswordPrompt? pwPrompt;

  @override
  State<SftpBrowser> createState() => SftpBrowserState();
}

class SftpBrowserState extends State<SftpBrowser> {
  SshLink? _link;
  RemoteFs? fs;
  String path = '';
  List<RemoteEntry> entries = [];
  bool loading = true;
  String? error;

  /// Progress text of a running upload/download (null = none).
  String? busy;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    fs?.close();
    _link?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var client = widget.client;
      if (client == null) {
        final link = await openSavedHost(widget.host,
            hostKeyPrompt: widget.keyPrompt ?? hostKeyPrompt,
            passwordPrompt: widget.pwPrompt ?? passwordPrompt,
            keepAlive: Store.i.settings.keepAlive);
        if (!mounted) return link.close();
        _link = link;
        client = link.client;
      }
      final f = await RemoteFs.open(client);
      if (!mounted) return f.close();
      fs = f;
      await cd(await f.home());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = describeError(e, S.of(context));
      });
    }
  }

  Future<void> cd(String dir) async {
    final f = fs;
    if (f == null) return;
    setState(() => loading = true);
    try {
      final list = await f.list(dir);
      if (!mounted) return;
      setState(() {
        path = dir;
        entries = list;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _fail(e);
    }
  }

  Future<void> refresh() => cd(path);

  void _fail(Object e) {
    if (!mounted) return;
    final s = S.of(context);
    toast(context, s.f('opFailed', {'msg': e is SftpStatusError ? e.message : describeError(e, s)}));
  }

  Future<T?> _run<T>(String label, Future<T> Function() op) async {
    setState(() => busy = label);
    try {
      return await op();
    } catch (e) {
      _fail(e);
      return null;
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<String?> _ask(String title, String label, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    final s = S.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('name-field'),
          controller: c,
          autofocus: true,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s['cancel'])),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(s['ok'])),
        ],
      ),
    );
  }

  bool _validName(String? n) => n != null && n.isNotEmpty && !n.contains('/') && n != '.' && n != '..';

  Future<void> newFolder() async {
    final s = S.of(context);
    final n = await _ask(s['newFolder'], s['folderName']);
    if (!_validName(n)) return;
    await _run(s['newFolder'], () => fs!.mkdir(joinRemote(path, n!)));
    await refresh();
  }

  Future<void> upload() async {
    final s = S.of(context);
    final picked = await pickFromDevice();
    if (picked == null || !mounted) return;
    final dest = joinRemote(path, picked.name);
    if (entries.any((e) => e.name == picked.name) &&
        !await confirm(context, s['replaceTitle'], s.f('replaceBody', {'name': picked.name}), ok: s['replace'])) {
      return;
    }
    final ok = await _run(s.f('uploading', {'name': picked.name}), () async {
      if (picked.path != null) {
        await fs!.uploadFile(File(picked.path!), dest);
      } else {
        await fs!.writeBytes(dest, picked.bytes ?? Uint8List(0));
      }
      return true;
    });
    if (ok == true && mounted) toast(context, s.f('uploaded', {'name': picked.name}));
    await refresh();
  }

  Future<void> download(RemoteEntry e) async {
    final s = S.of(context);
    final bytes = await _run(s.f('downloading', {'name': e.name}), () => fs!.readBytes(joinRemote(path, e.name)));
    if (bytes == null || !mounted) return;
    try {
      final where = await saveToDevice(e.name, bytes);
      if (where != null && mounted) toast(context, s.f('savedTo', {'path': where}));
    } catch (err) {
      _fail(err);
    }
  }

  Future<void> rename(RemoteEntry e) async {
    final s = S.of(context);
    final n = await _ask(s['rename'], s['newName'], initial: e.name);
    if (!_validName(n) || n == e.name) return;
    await _run(s['rename'], () => fs!.rename(joinRemote(path, e.name), joinRemote(path, n!)));
    await refresh();
  }

  Future<void> delete(RemoteEntry e) async {
    final s = S.of(context);
    final dir = e.isDir && !e.isLink;
    final ok = await confirm(
        context, s['delete'], s.f(dir ? 'deleteFolderBody' : 'deleteFileBody', {'name': e.name}),
        ok: s['delete'], danger: true);
    if (!ok) return;
    await _run(s['delete'], () => fs!.delete(joinRemote(path, e.name), isDir: dir));
    await refresh();
  }

  Future<void> edit(RemoteEntry e) async {
    final s = S.of(context);
    final p = joinRemote(path, e.name);
    String? text;
    try {
      text = await fs!.readText(p);
    } on NotTextError catch (x) {
      if (mounted) toast(context, s[x.tooBig ? 'fileTooBig' : 'notTextFile']);
      return;
    } catch (x) {
      _fail(x);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TextEditorScreen(fs: fs!, path: p, initial: text!)));
    await refresh();
  }

  Future<void> _actions(RemoteEntry e) async {
    final s = S.of(context);
    final p = context.pal;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Ltr(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          if (e.isDir) ListTile(leading: const Icon(Icons.folder_open), title: Text(s['open']), onTap: () => Navigator.pop(c, 'open')),
          if (!e.isDir) ...[
            ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(s['openEditor']),
                enabled: e.size <= maxEditBytes,
                onTap: () => Navigator.pop(c, 'edit')),
            ListTile(
                leading: const Icon(Icons.download), title: Text(s['download']), onTap: () => Navigator.pop(c, 'download')),
          ],
          ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(s['rename']),
              onTap: () => Navigator.pop(c, 'rename')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: p.red),
              title: Text(s['delete'], style: TextStyle(color: p.red)),
              onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    switch (v) {
      case 'open':
        await cd(joinRemote(path, e.name));
      case 'edit':
        await edit(e);
      case 'download':
        await download(e);
      case 'rename':
        await rename(e);
      case 'delete':
        await delete(e);
    }
  }

  Future<void> _tap(RemoteEntry e) async {
    if (e.isDir) return cd(joinRemote(path, e.name));
    return _actions(e);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final ready = fs != null && error == null;
    return PopScope(
      // The system back button goes up one folder before leaving.
      canPop: !ready || path == '/' || path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cd(parentRemote(path));
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.host.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (path.isNotEmpty) Ltr(path, style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
          actions: [
            if (ready) ...[
              IconButton(
                  key: const ValueKey('sftp-upload'),
                  tooltip: s['upload'],
                  icon: const Icon(Icons.upload_file),
                  onPressed: busy == null ? upload : null),
              IconButton(
                  key: const ValueKey('sftp-mkdir'),
                  tooltip: s['newFolder'],
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: busy == null ? newFolder : null),
              IconButton(tooltip: s['refresh'], icon: const Icon(Icons.refresh), onPressed: refresh),
            ],
          ],
          bottom: busy != null || loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3, color: p.accent))
              : null,
        ),
        body: Column(children: [
          if (busy != null)
            Container(
              width: double.infinity,
              color: p.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(busy!, style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          Expanded(child: _body(s, p)),
        ]),
      ),
    );
  }

  Widget _body(S s, Palette p) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: p.red, size: 40),
            const SizedBox(height: 12),
            Text(s.f('sftpFailed', {'msg': error!}), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _connect, child: Text(s['reconnect'])),
          ]),
        ),
      );
    }
    if (fs == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(key: const ValueKey('sftp-list'), padding: const EdgeInsets.only(bottom: 40), children: [
        if (path != '/')
          ListTile(
            key: const ValueKey('sftp-up'),
            leading: Icon(Icons.drive_folder_upload, color: p.muted),
            title: Text(s['goUp']),
            subtitle: Ltr(parentRemote(path), style: TextStyle(color: p.muted, fontSize: 12)),
            onTap: () => cd(parentRemote(path)),
          ),
        if (entries.isEmpty && !loading)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(s['emptyFolder'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
          ),
        for (final e in entries)
          ListTile(
            key: ValueKey('sftp-${e.name}'),
            leading: Icon(e.isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                color: e.isDir ? p.amber : p.muted),
            title: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Ltr(e.name, style: const TextStyle(fontSize: 14.5)),
            ),
            subtitle: e.isDir
                ? null
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr(formatSize(e.size), style: TextStyle(color: p.muted, fontSize: 12)),
                  ),
            trailing: IconButton(
              icon: Icon(Icons.more_vert, color: p.muted),
              onPressed: () => _actions(e),
            ),
            onTap: () => _tap(e),
            onLongPress: () => _actions(e),
          ),
      ]),
    );
  }
}

/// Simple editor for small remote text files.
class TextEditorScreen extends StatefulWidget {
  const TextEditorScreen({super.key, required this.fs, required this.path, required this.initial});
  final RemoteFs fs;
  final String path;
  final String initial;
  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late final c = TextEditingController(text: widget.initial);
  late String saved = widget.initial;
  bool saving = false;

  bool get dirty => c.text != saved;

  @override
  void initState() {
    super.initState();
    c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<bool> save() async {
    final s = S.of(context);
    setState(() => saving = true);
    try {
      final t = c.text;
      await widget.fs.writeText(widget.path, t);
      saved = t;
      if (mounted) toast(context, s['fileSaved']);
      return true;
    } catch (e) {
      if (mounted) toast(context, s.f('opFailed', {'msg': e is SftpStatusError ? e.message : '$e'}));
      return false;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await confirm(context, s['unsavedTitle'], s['unsavedBody'], ok: s['discard'], danger: true)) {
          saved = c.text;
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Ltr(widget.path.split('/').last, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            TextButton(
              key: const ValueKey('editor-save'),
              onPressed: saving || !dirty ? null : save,
              child: Text(s['save'], style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            key: const ValueKey('editor-field'),
            controller: c,
            expands: true,
            maxLines: null,
            minLines: null,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, color: p.text),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ),
    );
  }
}
