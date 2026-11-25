// Session logs: each session's output as plain text (ANSI codes removed) in
// <app documents>/logs/<host>_<timestamp>.txt. Off by default (Settings).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// App documents folder; tests point it at a temp folder.
Future<Directory> Function() appDocsDir = getApplicationDocumentsDirectory;

Future<Directory> logsDir() async {
  final d = Directory('${(await appDocsDir()).path}${Platform.pathSeparator}logs');
  if (!d.existsSync()) await d.create(recursive: true);
  return d;
}

/// Saved logs, newest first.
Future<List<File>> listLogs() async {
  final d = await logsDir();
  final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.txt')).toList()
    ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return files;
}

/// Removes terminal control sequences from a stream of output chunks. Keeps
/// state between chunks, because an escape sequence can be split across them.
class AnsiStripper {
  int _st = 0; // 0 text, 1 after ESC, 2 CSI, 3 OSC/DCS string, 4 ESC inside string, 5 one more char
  String convert(String s) {
    final out = StringBuffer();
    for (final c in s.runes) {
      switch (_st) {
        case 0:
          if (c == 0x1b) {
            _st = 1;
          } else if (c == 0x0a || c == 0x09 || c >= 0x20 && c != 0x7f) {
            out.writeCharCode(c);
          } else if (c == 0x08) {
            // backspace: drop the last char written in this chunk
            final t = out.toString();
            out.clear();
            if (t.isNotEmpty) out.write(t.substring(0, t.length - 1));
          }
        // \r, bell and other C0 controls are dropped
        case 1:
          if (c == 0x5b) {
            _st = 2; // [
          } else if (c == 0x5d || c == 0x50 || c == 0x5f || c == 0x5e || c == 0x58) {
            _st = 3; // ] P _ ^ X: string until BEL or ESC \
          } else if (c == 0x28 || c == 0x29 || c == 0x2a || c == 0x2b || c == 0x23 || c == 0x25) {
            _st = 5; // charset designation etc.: one more byte
          } else {
            _st = 0;
          }
        case 2:
          if (c >= 0x40 && c <= 0x7e) _st = 0;
        case 3:
          if (c == 0x07) {
            _st = 0;
          } else if (c == 0x1b) {
            _st = 4;
          }
        case 4:
          _st = c == 0x5c ? 0 : 3;
        case 5:
          _st = 0;
      }
    }
    return out.toString();
  }
}

String stripAnsi(String s) => AnsiStripper().convert(s);

/// File name safe on Android and Windows.
String logFileName(String host, DateTime t) {
  final safe = host.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  String two(int n) => n.toString().padLeft(2, '0');
  final ts = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return '${safe}_$ts.txt';
}

/// Writes one session's output to its log file.
class SessionLog {
  SessionLog._(this.file, this._sink);
  final File file;
  final IOSink _sink;
  final _strip = AnsiStripper();
  bool _closed = false;

  static Future<SessionLog?> open(String host) async {
    try {
      final d = await logsDir();
      final f = File('${d.path}${Platform.pathSeparator}${logFileName(host, DateTime.now())}');
      return SessionLog._(f, f.openWrite(mode: FileMode.append));
    } catch (e) {
      debugPrint('session log: $e');
      return null;
    }
  }

  void write(String data) {
    if (_closed) return;
    final t = _strip.convert(data);
    if (t.isNotEmpty) _sink.write(t);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sink.flush();
      await _sink.close();
    } catch (_) {}
  }
}
