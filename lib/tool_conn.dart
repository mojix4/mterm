// SSH exec for the Tools screen and broadcast: reuses the logged-in
// connection of an open terminal session for the same server, otherwise opens
// a short-lived one of its own (same host-key and password prompts as the
// terminal, same proxy / jump host settings).
import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'models.dart';
import 'session.dart';
import 'ssh_connect.dart';
import 'store.dart';

class ExecResult {
  const ExecResult(this.output, this.exitCode);

  /// stdout followed by stderr.
  final String output;
  final int? exitCode;
  bool get ok => exitCode == 0;
}

class ToolConn {
  ToolConn(this.host, {this.session, required this.hostKeyPrompt, this.passwordPrompt});
  final Host host;

  /// The terminal session this was opened from (its connection is reused).
  final TermSession? session;
  final HostKeyPrompt hostKeyPrompt;
  final PasswordPrompt? passwordPrompt;

  SshLink? _own;
  Future<SSHClient>? _opening;
  bool _closed = false;

  /// A live terminal connection to the same saved server, if there is one.
  SSHClient? _shared() {
    final c = session?.client;
    if (c != null && !c.isClosed) return c;
    for (final s in Sessions.i.list) {
      final sc = s.client;
      if (s.host.id == host.id && sc != null && !sc.isClosed) return sc;
    }
    return null;
  }

  /// True while this uses a terminal session's connection.
  bool get sharesSession => _own == null && _shared() != null;

  Future<SSHClient> client() {
    final shared = _shared();
    if (shared != null) return Future.value(shared);
    final own = _own;
    if (own != null && !own.client.isClosed) return Future.value(own.client);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<SSHClient> _open() async {
    final link = await openSavedHost(host,
        hostKeyPrompt: hostKeyPrompt, passwordPrompt: passwordPrompt, keepAlive: Store.i.settings.keepAlive);
    if (_closed) {
      link.close();
      throw StateError('closed');
    }
    _own?.close();
    _own = link;
    return link.client;
  }

  /// Runs [cmd] in its own channel and returns its output and exit code.
  Future<ExecResult> run(String cmd, {Duration timeout = const Duration(seconds: 30)}) async {
    final c = await client().timeout(const Duration(seconds: 60));
    final SSHSession sess;
    try {
      sess = await c.execute(cmd).timeout(const Duration(seconds: 15));
    } catch (e) {
      // a dropped private connection is reopened on the next call
      if (_own != null && _own!.client == c) {
        _own!.close();
        _own = null;
      }
      rethrow;
    }
    final out = <int>[], err = <int>[];
    final a = sess.stdout.listen(out.addAll).asFuture<void>();
    final b = sess.stderr.listen(err.addAll).asFuture<void>();
    try {
      await Future.wait([a, b, sess.done]).timeout(timeout);
    } on TimeoutException {
      sess.close();
      rethrow;
    }
    const dec = Utf8Decoder(allowMalformed: true);
    return ExecResult(dec.convert(out) + dec.convert(err), sess.exitCode);
  }

  void close() {
    _closed = true;
    _own?.close();
    _own = null;
  }
}
