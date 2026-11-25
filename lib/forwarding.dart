// Port forwarding over an open SSH connection: local (-L) and dynamic SOCKS5 (-D).
// Listeners bind to 127.0.0.1 only, so other devices on the network can't use them.
import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

/// A running listener for one [ForwardRule].
class _Running {
  _Running({this.server, this.socks});
  final ServerSocket? server;
  final SSHDynamicForward? socks;
  final Set<Socket> conns = {};

  int get port => server?.port ?? socks!.port;

  Future<void> close() async {
    for (final c in conns.toList()) {
      c.destroy();
    }
    await server?.close();
    await socks?.close();
  }
}

/// Starts and stops the forwarding rules of one session.
class ForwardManager extends ChangeNotifier {
  final Map<String, _Running> _running = {};

  /// Last start error per rule id (e.g. port already in use).
  final Map<String, String> errors = {};

  bool isRunning(ForwardRule r) => _running.containsKey(r.id);

  /// The local port actually bound (differs from the rule only for port 0).
  int? boundPort(ForwardRule r) => _running[r.id]?.port;

  int get activeCount => _running.length;

  /// Bumped by [stopAll], so a rule still starting when the session ends is
  /// closed right away instead of staying open.
  int _epoch = 0;

  /// Starts every rule marked [ForwardRule.autoStart].
  Future<void> startAuto(SSHClient client, List<ForwardRule> rules) async {
    for (final r in rules) {
      if (r.autoStart) await start(client, r);
    }
  }

  Future<bool> start(SSHClient client, ForwardRule r) async {
    if (_running.containsKey(r.id)) return true;
    errors.remove(r.id);
    final epoch = _epoch;
    try {
      _Running run;
      if (r.isDynamic) {
        run = _Running(socks: await client.forwardDynamic(bindHost: '127.0.0.1', bindPort: r.localPort));
      } else {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, r.localPort);
        run = _Running(server: server);
        server.listen((sock) => _pipe(client, run, sock, r.remoteHost, r.remotePort), onError: (_) {});
      }
      if (epoch != _epoch || _running.containsKey(r.id)) {
        await run.close();
        return false;
      }
      _running[r.id] = run;
      notifyListeners();
      return true;
    } catch (e) {
      errors[r.id] = e is SocketException ? (e.osError?.message ?? e.message) : '$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> stop(ForwardRule r) async {
    final run = _running.remove(r.id);
    notifyListeners();
    await run?.close();
  }

  Future<void> stopAll() async {
    _epoch++;
    final all = _running.values.toList();
    _running.clear();
    if (all.isNotEmpty) notifyListeners();
    for (final r in all) {
      await r.close();
    }
  }

  /// Joins a local TCP connection to a new SSH direct-tcpip channel.
  static Future<void> _pipe(SSHClient client, _Running run, Socket sock, String host, int port) async {
    run.conns.add(sock);
    SSHForwardChannel ch;
    try {
      ch = await client.forwardLocal(host, port).timeout(const Duration(seconds: 15));
    } catch (_) {
      run.conns.remove(sock);
      sock.destroy();
      return;
    }
    var closed = false;
    void done() {
      if (closed) return;
      closed = true;
      run.conns.remove(sock);
      sock.destroy();
      ch.destroy();
    }

    ch.stream.listen((d) {
      try {
        sock.add(d);
      } catch (_) {
        done();
      }
    }, onDone: () async {
      try {
        await sock.flush();
      } catch (_) {}
      done();
    }, onError: (_) => done());
    sock.listen((d) => ch.sink.add(d), onDone: () {
      ch.sink.close();
      // half-close: let the remote finish sending, then tear down
      Timer(const Duration(seconds: 5), done);
    }, onError: (_) => done());
  }
}
