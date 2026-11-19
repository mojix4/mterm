import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'models.dart';
import 'store.dart';

/// Asks the user whether to trust a server key. [old] is set when the key changed.
typedef HostKeyPrompt = Future<bool> Function(String type, String fingerprint, String? old);

enum SessStatus { connecting, connected, closed, failed }

class TermSession extends ChangeNotifier {
  TermSession(this.host) {
    terminal = Terminal(maxLines: Store.i.settings.scrollback);
    terminal.onOutput = _onOutput;
    terminal.onResize = (w, h, pw, ph) => _shell?.resizeTerminal(w, h, pw, ph);
    terminal.onBell = () {
      if (Store.i.settings.vibrate) HapticFeedback.mediumImpact();
    };
    terminal.onTitleChange = (t) {
      title = t;
      notifyListeners();
    };
  }

  final Host host;
  late final Terminal terminal;
  SSHClient? _client;
  SSHSession? _shell;
  SessStatus status = SessStatus.connecting;
  String? error;
  String? title;
  bool ctrl = false;
  bool alt = false;

  /// Text typed on the current line, used for suggestions. null = unknown.
  String? line = '';
  final List<String> typed = [];

  bool get isLive => status == SessStatus.connected || status == SessStatus.connecting;

  /// Bumped on every connect/close so callbacks of an older connection
  /// (late close events, output) cannot touch the current one.
  int _gen = 0;

  /// Status lines written into the terminal itself. The terminal grid has no
  /// RTL shaping, so Persian here shows up reversed and broken: keep these ASCII
  /// (the Persian explanation is shown in the app's own banner).
  void _info(String s) => terminal.write('\x1b[90m$s\x1b[0m\r\n');

  Future<void> connect(HostKeyPrompt prompt) async {
    final gen = ++_gen;
    bool stale() => gen != _gen;
    status = SessStatus.connecting;
    error = null;
    notifyListeners();
    _info('Connecting to ${host.host}:${host.port} …');
    try {
      final sec = await Store.i.secret(host.id);
      List<SSHKeyPair>? ids;
      if (host.auth == 'key' && sec.privateKey.trim().isNotEmpty) {
        ids = SSHKeyPair.fromPem(sec.privateKey.trim(), sec.passphrase.isEmpty ? null : sec.passphrase);
      }
      final socket = await SSHSocket.connect(host.host, host.port, timeout: const Duration(seconds: 12));
      final ka = Store.i.settings.keepAlive;
      final client = SSHClient(
        socket,
        username: host.user,
        identities: ids,
        keepAliveInterval: ka > 0 ? Duration(seconds: ka) : null,
        onPasswordRequest: () => sec.password.isEmpty ? null : sec.password,
        onUserInfoRequest: (req) => req.prompts.map((_) => sec.password).toList(),
        onVerifyHostKey: (type, fp) async {
          final hex = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
          final known = Store.i.knownFingerprint(host.host, host.port);
          if (known == hex) return true;
          final ok = await prompt(type, hex, known);
          if (ok) await Store.i.trust(host.host, host.port, hex);
          return ok;
        },
      );
      if (stale()) return client.close();
      _client = client;
      await client.authenticated;
      final shell = await client.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: terminal.viewWidth, height: terminal.viewHeight),
      );
      if (stale()) {
        // closed or reconnected while we were logging in
        shell.close();
        client.close();
        return;
      }
      _shell = shell;
      status = SessStatus.connected;
      notifyListeners();
      Store.i.touchHost(host);
      const dec = Utf8Decoder(allowMalformed: true);
      void out(String d) {
        if (!stale()) terminal.write(d);
      }

      shell.stdout.cast<List<int>>().transform(dec).listen(out, onError: (_) {});
      shell.stderr.cast<List<int>>().transform(dec).listen(out, onError: (_) {});
      shell.done.whenComplete(() => _closed(gen)).ignore();
      client.done.whenComplete(() => _closed(gen)).ignore();
    } catch (e) {
      if (stale()) return;
      status = SessStatus.failed;
      error = _explain(e);
      _info('');
      terminal.write('\x1b[31m✕ Connection failed\x1b[0m \x1b[90m($e)\x1b[0m\r\n');
      _client?.close();
      _client = null;
      notifyListeners();
    }
  }

  void _closed(int gen) {
    if (gen != _gen) return;
    if (status == SessStatus.closed || status == SessStatus.failed) return;
    status = SessStatus.closed;
    _info('\r\n[connection closed]');
    notifyListeners();
  }

  static String _explain(Object e) {
    // The transport closing early (host key rejected, network drop) surfaces as an
    // auth abort; explain the real cause instead of blaming the password.
    if (e is SSHAuthAbortError) {
      final r = e.reason;
      if (r is SSHHostkeyError || r is SSHHandshakeError) return _explain(r!);
      if (r is SSHSocketError) return 'اتصال در حین ورود قطع شد';
      if (e.message.contains('timed out')) return 'سرور جواب نداد (Timeout)';
    }
    if (e is SSHAuthFailError || e is SSHAuthAbortError) return 'نام کاربری، رمز یا کلید اشتباه است';
    if (e is SSHHostkeyError) return 'کلید سرور تأیید نشد';
    if (e is SSHHandshakeError) return 'توافق رمزنگاری با سرور ممکن نشد';
    if (e is SSHKeyDecryptError) return 'رمز کلید خصوصی اشتباه است';
    if (e is SSHKeyDecodeError) return 'کلید خصوصی معتبر نیست';
    if (e is TimeoutException) return 'سرور جواب نداد (Timeout)';
    if (e is SocketException) {
      final m = e.osError?.message ?? e.message;
      if (m.contains('refused')) return 'اتصال رد شد؛ پورت SSH بسته است';
      if (m.contains('lookup') || m.contains('host')) return 'آدرس سرور پیدا نشد';
      return 'سرور در دسترس نیست: $m';
    }
    return e.toString();
  }

  // ---- input
  void _onOutput(String data) {
    if (ctrl && data.length == 1) {
      final c = data.toUpperCase().codeUnitAt(0);
      if (c >= 64 && c <= 95) {
        data = String.fromCharCode(c - 64);
      } else if (data == ' ') {
        data = '\x00';
      }
      ctrl = false;
      notifyListeners();
    }
    if (alt) {
      data = '\x1b$data';
      alt = false;
      notifyListeners();
    }
    _track(data);
    _send(data);
  }

  void _send(String data) {
    final s = _shell;
    if (s == null || status != SessStatus.connected) return;
    s.write(Uint8List.fromList(utf8.encode(data)));
  }

  /// Special key from the key bar.
  void key(TerminalKey k) {
    final c = ctrl, a = alt;
    ctrl = false;
    alt = false;
    line = null;
    terminal.keyInput(k, ctrl: c, alt: a);
    notifyListeners();
  }

  /// Plain text from the key bar or paste.
  void text(String t) => terminal.textInput(t);

  /// Runs a full command line (snippets, history, suggestions).
  void run(String cmd, {bool enter = true}) {
    _send('\x15$cmd${enter ? '\r' : ''}');
    if (enter) {
      _remember(cmd);
      line = '';
    } else {
      line = cmd;
    }
    notifyListeners();
  }

  void _remember(String cmd) {
    final c = cmd.trim();
    if (c.isEmpty) return;
    typed.remove(c);
    typed.insert(0, c);
    if (typed.length > 300) typed.removeLast();
  }

  void _track(String d) {
    final before = line;
    if (d == '\r') {
      if (line != null) _remember(line!);
      line = '';
    } else if (d == '\x7f' || d == '\b') {
      if (line != null && line!.isNotEmpty) line = line!.substring(0, line!.length - 1);
    } else if (d == '\x03' || d == '\x15' || d == '\x04') {
      line = '';
    } else if (d.contains('\r')) {
      line = '';
    } else if (d.codeUnits.any((c) => c < 32)) {
      line = null;
    } else if (line != null) {
      line = line! + d;
    }
    if (before != line) notifyListeners();
  }

  void toggleCtrl() {
    ctrl = !ctrl;
    notifyListeners();
  }

  void toggleAlt() {
    alt = !alt;
    notifyListeners();
  }

  Future<void> reconnect(HostKeyPrompt prompt) async {
    _gen++; // the old connection's close events must not mark the new one closed
    _shell?.close();
    _client?.close();
    _shell = null;
    _client = null;
    terminal.write('\r\n');
    await connect(prompt);
  }

  void close() {
    _gen++;
    _shell?.close();
    _client?.close();
    _shell = null;
    _client = null;
    if (status == SessStatus.closed) return;
    status = SessStatus.closed;
    notifyListeners();
  }
}

/// All open sessions, so the user can jump between servers like in Termius.
class Sessions extends ChangeNotifier {
  Sessions._();
  static final Sessions i = Sessions._();
  final List<TermSession> list = [];

  TermSession open(Host h) {
    final s = TermSession(h);
    s.addListener(notifyListeners);
    list.add(s);
    notifyListeners();
    return s;
  }

  void close(TermSession s) {
    s.close();
    s.removeListener(notifyListeners);
    list.remove(s);
    notifyListeners();
  }
}
