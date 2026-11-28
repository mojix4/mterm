// Remote file operations for the Files section (SFTP over the SSH login).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Largest file the built-in text editor opens.
const maxEditBytes = 1024 * 1024;

class RemoteEntry {
  const RemoteEntry(this.name, this.isDir, this.size, this.modified, {this.isLink = false});
  final String name;
  final bool isDir;
  final bool isLink;
  final int size;
  final DateTime? modified;
}

String joinRemote(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

String parentRemote(String path) {
  if (path == '/' || path.isEmpty) return '/';
  final p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = p.lastIndexOf('/');
  return i <= 0 ? '/' : p.substring(0, i);
}

/// The file is not text (binary data) or too big for the editor.
class NotTextError implements Exception {
  NotTextError(this.tooBig);
  final bool tooBig;
}

class RemoteFs {
  RemoteFs(this.sftp);
  final SftpClient sftp;

  static Future<RemoteFs> open(SSHClient client) async => RemoteFs(await client.sftp());

  Future<String> home() => sftp.absolute('.');

  /// Directory contents: folders first, then files, by name. No "." / "..".
  Future<List<RemoteEntry>> list(String path) async {
    final names = await sftp.listdir(path);
    final out = <RemoteEntry>[];
    for (final n in names) {
      if (n.filename == '.' || n.filename == '..') continue;
      var dir = n.attr.isDirectory;
      final link = n.attr.isSymbolicLink;
      if (link) {
        // a link to a folder should open like a folder
        try {
          dir = (await sftp.stat(joinRemote(path, n.filename))).isDirectory;
        } catch (_) {}
      }
      final mt = n.attr.modifyTime;
      out.add(RemoteEntry(n.filename, dir, n.attr.size ?? 0,
          mt == null ? null : DateTime.fromMillisecondsSinceEpoch(mt * 1000),
          isLink: link));
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<Uint8List> readBytes(String path, {void Function(int)? onProgress}) async {
    final f = await sftp.open(path);
    try {
      final b = BytesBuilder(copy: false);
      await for (final chunk in f.read(onProgress: onProgress)) {
        b.add(chunk);
      }
      return b.takeBytes();
    } finally {
      await f.close();
    }
  }

  /// Writes (creates or replaces) [path] with [data].
  Future<void> writeBytes(String path, Uint8List data) async {
    final f = await sftp.open(path,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    try {
      await f.writeBytes(data);
    } finally {
      await f.close();
    }
  }

  /// Uploads a local file by streaming it (large files don't fill memory).
  Future<void> uploadFile(File local, String remotePath, {void Function(int)? onProgress}) async {
    final f = await sftp.open(remotePath,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    try {
      await f.write(local.openRead().map(Uint8List.fromList), onProgress: onProgress).done;
    } finally {
      await f.close();
    }
  }

  /// Downloads [remotePath] straight into a local file.
  Future<void> downloadToFile(String remotePath, File local, {void Function(int)? onProgress}) async {
    final sink = local.openWrite();
    try {
      await sftp.download(remotePath, sink, onProgress: onProgress);
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Text of a small file for the editor. Throws [NotTextError].
  Future<String> readText(String path) async {
    final st = await sftp.stat(path);
    if ((st.size ?? 0) > maxEditBytes) throw NotTextError(true);
    final b = await readBytes(path);
    if (b.length > maxEditBytes) throw NotTextError(true);
    if (b.contains(0)) throw NotTextError(false);
    try {
      return utf8.decode(b);
    } on FormatException {
      throw NotTextError(false);
    }
  }

  Future<void> writeText(String path, String text) => writeBytes(path, Uint8List.fromList(utf8.encode(text)));

  /// Saves [data] to [path] without ever leaving a half-written file: writes
  /// a temporary file next to it, copies the original's permissions (and
  /// owner when allowed), then renames it over the original (posix-rename,
  /// atomic on OpenSSH). The temporary file is removed when anything fails.
  Future<void> writeBytesAtomic(String path, Uint8List data) async {
    SftpFileAttrs? old;
    try {
      old = await sftp.stat(path);
    } on SftpStatusError {
      old = null; // new file
    }
    final dir = parentRemote(path);
    final name = path.substring(path.lastIndexOf('/') + 1);
    final tmp = joinRemote(dir, '.$name.mterm-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}.tmp');
    try {
      await writeBytes(tmp, data);
      if (old?.mode != null) {
        await sftp.setStat(tmp, SftpFileAttrs(mode: SftpFileMode.value(old!.mode!.value & 0xFFF)));
      }
      if (old?.userID != null && old?.groupID != null) {
        try {
          await sftp.setStat(tmp, SftpFileAttrs(userID: old!.userID, groupID: old.groupID));
        } catch (_) {} // only root may give files away; keep ours then
      }
      await sftp.rename(tmp, path);
    } catch (_) {
      try {
        await sftp.remove(tmp);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> writeTextAtomic(String path, String text) =>
      writeBytesAtomic(path, Uint8List.fromList(utf8.encode(text)));

  Future<void> mkdir(String path) => sftp.mkdir(path);

  /// Renames; system paths ([isCriticalPath]) are refused.
  Future<void> rename(String from, String to) async {
    if (isCriticalPath(from)) throw CriticalPathError(from);
    await sftp.rename(from, to);
  }

  /// Deletes a file, or a folder with everything in it. System paths
  /// ([isCriticalPath]) are refused.
  Future<void> delete(String path, {required bool isDir}) async {
    if (isCriticalPath(path)) throw CriticalPathError(path);
    if (!isDir) return sftp.remove(path);
    for (final e in await list(path)) {
      final p = joinRemote(path, e.name);
      await delete(p, isDir: e.isDir && !e.isLink);
    }
    await sftp.rmdir(path);
  }

  void close() => sftp.close();
}

/// System paths the Files screen never deletes or renames.
const criticalPaths = {
  '/', '/etc', '/etc/ssh', '/etc/passwd', '/etc/shadow', '/boot', '/usr', '/bin', '/sbin', '/lib', '/lib64',
  '/var', '/root', '/home', '/proc', '/sys', '/dev',
};

/// [path] with duplicate slashes, "." and ".." resolved and no trailing slash.
String normalizeRemote(String path) {
  final parts = <String>[];
  for (final p in path.split('/')) {
    if (p.isEmpty || p == '.') continue;
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(p);
    }
  }
  return '/${parts.join('/')}';
}

bool isCriticalPath(String path) => path.trim().isEmpty || criticalPaths.contains(normalizeRemote(path));

/// Thrown instead of deleting or renaming a [criticalPaths] entry.
class CriticalPathError implements Exception {
  CriticalPathError(this.path);
  final String path;
  @override
  String toString() => 'protected system path: $path';
}

/// "12 KB", "3.4 MB"… (ASCII, shown LTR).
String formatSize(int n) {
  if (n < 1024) return '$n B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = n / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${u[i]}';
}
