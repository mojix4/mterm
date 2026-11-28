// One place that opens authenticated SSH connections, shared by the terminal
// (TermSession), the file manager (SFTP) and jump hosts.
import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import 'models.dart';
import 'socks5.dart';
import 'store.dart';

/// Asks the user whether to trust a server key. [old] is set when the key changed.
typedef HostKeyPrompt = Future<bool> Function(String type, String fingerprint, String? old);

/// What the user typed in the password dialog.
class PasswordAnswer {
  const PasswordAnswer(this.password, {this.remember = true});
  final String password;
  final bool remember;
}

/// Asks the user for [host]'s password. [wrong] is true after a failed login.
/// Returns null when the user cancels.
typedef PasswordPrompt = Future<PasswordAnswer?> Function(Host host, {bool wrong});

/// An authenticated connection, plus the jump host connection it runs through.
class SshLink {
  SshLink(this.client, [this.via]);
  final SSHClient client;
  final SshLink? via;

  void close() {
    client.close();
    via?.close();
  }

  /// Completes when this connection (or the jump host under it) ends.
  Future<void> get done => Future.any([client.done, if (via != null) via!.done]);
}

/// The jump host could not be reached or logged in to; [cause] says why.
class JumpHostError implements Exception {
  JumpHostError(this.jump, this.cause);
  final Host? jump; // null: the saved jump host no longer exists
  final Object cause;
  @override
  String toString() => 'jump host ${jump?.name ?? '?'}: $cause';
}

/// Checks a server key against the saved known hosts (trust on first use).
Future<bool> Function(String, List<int>) hostKeyVerifier(Host host, HostKeyPrompt prompt) => (type, fp) async {
      final hex = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
      final known = Store.i.knownFingerprint(host.host, host.port);
      if (known == hex) return true;
      final ok = await prompt(type, hex, known);
      if (ok) await Store.i.trust(host.host, host.port, hex);
      return ok;
    };

/// Opens an authenticated connection to [host]: directly, or through its jump
/// host when [Host.jumpHostId] is set (the jump host uses its own saved login,
/// and asks with [jumpPasswordPrompt] when it has no saved password).
///
/// [onLink] gets the connection before authentication finishes, so the caller
/// can close it if the user gives up meanwhile.
Future<SshLink> openSsh(
  Host host, {
  required HostSecret secret,
  required HostKeyPrompt hostKeyPrompt,
  Future<String?> Function()? password,
  PasswordPrompt? jumpPasswordPrompt,
  int keepAlive = 0,
  void Function(SshLink link)? onLink,
  int depth = 0,
}) async {
  List<SSHKeyPair>? ids;
  if (host.auth == 'key' && secret.privateKey.trim().isNotEmpty) {
    ids = SSHKeyPair.fromPem(secret.privateKey.trim(), secret.passphrase.isEmpty ? null : secret.passphrase);
  }
  SshLink? via;
  SSHSocket socket;
  final jumpId = host.jumpHostId;
  if (jumpId != null && jumpId.isNotEmpty && jumpId != host.id) {
    Host? jump;
    for (final h in Store.i.hosts) {
      if (h.id == jumpId) jump = h;
    }
    if (jump == null) throw JumpHostError(null, 'not found');
    if (depth >= 3) throw JumpHostError(jump, 'too many jump hosts');
    try {
      via = await openSavedHost(jump,
          hostKeyPrompt: hostKeyPrompt, passwordPrompt: jumpPasswordPrompt, keepAlive: keepAlive, depth: depth + 1);
      socket = await via.client.forwardLocal(host.host, host.port).timeout(const Duration(seconds: 15));
    } catch (e) {
      via?.close();
      if (e is JumpHostError) rethrow;
      throw JumpHostError(jump, e);
    }
  } else if (host.hasProxy) {
    // the jump host (above) uses its own proxy setting; a direct connection
    // goes through this host's SOCKS5 proxy
    socket = await connectSocks5(host.proxyHost.trim(), host.proxyPort, host.host, host.port,
        user: host.proxyUser, password: secret.proxyPassword, timeout: const Duration(seconds: 15));
  } else {
    socket = await SSHSocket.connect(host.host, host.port, timeout: const Duration(seconds: 12));
  }
  final client = SSHClient(
    socket,
    username: host.user,
    identities: ids,
    keepAliveInterval: keepAlive > 0 ? Duration(seconds: keepAlive) : null,
    onPasswordRequest: password,
    onUserInfoRequest: (req) async {
      final p = await password?.call();
      return p == null ? null : req.prompts.map((_) => p).toList();
    },
    onVerifyHostKey: hostKeyVerifier(host, hostKeyPrompt),
  );
  final link = SshLink(client, via);
  onLink?.call(link);
  try {
    await client.authenticated;
  } catch (_) {
    link.close();
    rethrow;
  }
  return link;
}

/// Connects to a saved host with its stored login. Asks for the password with
/// [passwordPrompt] when none is saved or the saved one is rejected (up to 3
/// tries) and remembers it like the terminal does.
Future<SshLink> openSavedHost(
  Host host, {
  required HostKeyPrompt hostKeyPrompt,
  PasswordPrompt? passwordPrompt,
  int keepAlive = 0,
  int depth = 0,
}) async {
  final sec = await Store.i.secret(host.id);
  var pw = sec.password;
  var remember = false;
  var typed = false;
  var cancelled = false;
  var wrong = false;
  for (var attempt = 0;; attempt++) {
    Future<String?> password() async {
      if ((pw.isEmpty || wrong) && host.auth == 'password' && passwordPrompt != null && !cancelled) {
        final a = await passwordPrompt(host, wrong: wrong);
        wrong = false;
        if (a == null || a.password.isEmpty) {
          cancelled = true;
          return null;
        }
        pw = a.password;
        remember = a.remember;
        typed = true;
      }
      return pw.isEmpty ? null : pw;
    }

    try {
      final link = await openSsh(host,
          secret: sec,
          hostKeyPrompt: hostKeyPrompt,
          password: password,
          jumpPasswordPrompt: passwordPrompt,
          keepAlive: keepAlive,
          depth: depth);
      if (typed && remember && pw != sec.password) await Store.i.savePassword(host.id, pw);
      return link;
    } on SSHAuthFailError {
      if (host.auth != 'password' || passwordPrompt == null || cancelled || attempt >= 2) rethrow;
      wrong = true;
    }
  }
}
