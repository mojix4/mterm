// Minimal SOCKS5 client (RFC 1928 + RFC 1929 username/password) used to reach
// a server through a per-host proxy. The proxy resolves the target name, so
// DNS for the server goes through the proxy too.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// The proxy refused or failed; [code] is the SOCKS reply code when known.
class Socks5Error implements Exception {
  Socks5Error(this.message, {this.code, this.auth = false});
  final String message;
  final int? code;

  /// The proxy rejected the username / password.
  final bool auth;
  @override
  String toString() => 'SOCKS5 proxy: $message';
}

const _replies = {
  1: 'general failure',
  2: 'connection not allowed by ruleset',
  3: 'network unreachable',
  4: 'host unreachable',
  5: 'connection refused',
  6: 'TTL expired',
  7: 'command not supported',
  8: 'address type not supported',
};

/// Opens a TCP connection to [host]:[port] through the SOCKS5 proxy at
/// [proxyHost]:[proxyPort] and returns it as an [SSHSocket].
Future<SSHSocket> connectSocks5(
  String proxyHost,
  int proxyPort,
  String host,
  int port, {
  String user = '',
  String password = '',
  Duration timeout = const Duration(seconds: 15),
}) async {
  final sock = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
  final reader = _Reader(sock);
  try {
    await _handshake(sock, reader, host, port, user, password).timeout(timeout);
  } catch (_) {
    sock.destroy();
    rethrow;
  }
  return reader.detach();
}

Future<void> _handshake(Socket sock, _Reader r, String host, int port, String user, String password) async {
  final withAuth = user.isNotEmpty;
  sock.add(withAuth ? [5, 2, 0, 2] : [5, 1, 0]);
  var b = await r.take(2);
  if (b[0] != 5) throw Socks5Error('not a SOCKS5 proxy');
  if (b[1] == 2) {
    if (!withAuth) throw Socks5Error('proxy needs a username and password', auth: true);
    final u = utf8.encode(user), p = utf8.encode(password);
    if (u.length > 255 || p.length > 255) throw Socks5Error('username or password too long', auth: true);
    sock.add([1, u.length, ...u, p.length, ...p]);
    b = await r.take(2);
    if (b[1] != 0) throw Socks5Error('username or password rejected', auth: true);
  } else if (b[1] != 0) {
    throw Socks5Error(b[1] == 0xFF ? 'no acceptable authentication method' : 'unsupported method ${b[1]}',
        auth: b[1] == 0xFF);
  }
  final ip = InternetAddress.tryParse(host);
  final List<int> addr;
  if (ip != null && ip.type == InternetAddressType.IPv4) {
    addr = [1, ...ip.rawAddress];
  } else if (ip != null && ip.type == InternetAddressType.IPv6) {
    addr = [4, ...ip.rawAddress];
  } else {
    final h = utf8.encode(host);
    if (h.length > 255) throw Socks5Error('host name too long');
    addr = [3, h.length, ...h];
  }
  sock.add([5, 1, 0, ...addr, port >> 8, port & 0xFF]);
  final head = await r.take(4);
  if (head[0] != 5) throw Socks5Error('bad reply');
  if (head[1] != 0) throw Socks5Error(_replies[head[1]] ?? 'error ${head[1]}', code: head[1]);
  final atyp = head[3];
  final skip = switch (atyp) { 1 => 4, 4 => 16, 3 => (await r.take(1))[0], _ => throw Socks5Error('bad reply') };
  await r.take(skip + 2); // bound address + port
}

/// Reads the handshake bytes from the socket's single subscription, then hands
/// everything after it (including bytes that arrived early) to the SSH layer.
class _Reader {
  _Reader(this.sock) {
    _sub = sock.listen(_onData, onError: _onError, onDone: _onDone);
  }
  final Socket sock;
  late final StreamSubscription<Uint8List> _sub;
  final _buf = BytesBuilder(copy: true);
  Completer<void>? _wait;
  Object? _error;
  bool _closed = false;
  StreamController<Uint8List>? _out;

  void _onData(Uint8List d) {
    final o = _out;
    if (o != null) return o.add(d);
    _buf.add(d);
    _wake();
  }

  void _onError(Object e) {
    if (_out != null) {
      _out!.addError(e);
    } else {
      _error = e;
    }
    _wake();
  }

  void _onDone() {
    _closed = true;
    _out?.close();
    _wake();
  }

  void _wake() {
    final w = _wait;
    _wait = null;
    w?.complete();
  }

  Future<Uint8List> take(int n) async {
    while (_buf.length < n) {
      if (_error != null) throw _error!;
      if (_closed) throw Socks5Error('proxy closed the connection');
      _wait = Completer<void>();
      await _wait!.future;
    }
    final all = _buf.takeBytes();
    _buf.add(Uint8List.sublistView(all, n));
    return Uint8List.sublistView(all, 0, n);
  }

  SSHSocket detach() {
    final o = StreamController<Uint8List>(
      onPause: _sub.pause,
      onResume: _sub.resume,
      onCancel: () => _sub.cancel(),
    );
    _out = o;
    if (_buf.length > 0) o.add(_buf.takeBytes());
    if (_closed) o.close();
    return _ProxiedSocket(sock, o.stream);
  }
}

class _ProxiedSocket implements SSHSocket {
  _ProxiedSocket(this._socket, this.stream);
  final Socket _socket;
  @override
  final Stream<Uint8List> stream;
  @override
  StreamSink<List<int>> get sink => _socket;
  @override
  Future<void> get done => _socket.done;
  @override
  Future<void> close() => _socket.close();
  @override
  void destroy() => _socket.destroy();
  @override
  Future<void> flush() => _socket.flush();
}
