// SSH key helpers: generate an Ed25519 key in OpenSSH format, derive the public
// key line, and build the shell command that installs it in authorized_keys.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed;

class GeneratedKey {
  const GeneratedKey(this.privatePem, this.publicLine);
  final String privatePem;
  final String publicLine;
}

/// New Ed25519 key pair (unencrypted OpenSSH private key + "ssh-ed25519 AAAA… comment").
GeneratedKey generateEd25519({String comment = 'mterm'}) {
  final sk = ed.SigningKey.generate();
  final pub = Uint8List.fromList(sk.verifyKey.asTypedList);
  // OpenSSH stores the 64-byte "secret key" = 32-byte seed + 32-byte public key.
  final priv = Uint8List.fromList([...sk.seed.asTypedList, ...pub]);
  final pair = OpenSSHEd25519KeyPair(pub, priv, comment);
  return GeneratedKey(pair.toPem(), publicLineOf(pair, comment: comment));
}

String publicLineOf(SSHKeyPair pair, {String comment = 'mterm'}) {
  final pub = pair.toPublicKey().encode();
  return '${pair.type} ${base64.encode(pub)}${comment.isEmpty ? '' : ' $comment'}';
}

/// Public key line of a private key, or null when it can't be read
/// (bad format or wrong / missing passphrase).
String? publicKeyFromPrivate(String pem, {String passphrase = '', String comment = 'mterm'}) {
  try {
    final pairs = SSHKeyPair.fromPem(pem.trim(), passphrase.isEmpty ? null : passphrase);
    if (pairs.isEmpty) return null;
    return publicLineOf(pairs.first, comment: comment);
  } catch (_) {
    return null;
  }
}

/// Shell command that adds [publicLine] to ~/.ssh/authorized_keys once
/// (creates ~/.ssh with mode 700 and the file with mode 600). Prints
/// MTERM_KEY_ADDED or MTERM_KEY_EXISTS.
String installKeyCommand(String publicLine) {
  final line = publicLine.trim().replaceAll('\n', ' ');
  final q = "'${line.replaceAll("'", "'\\''")}'";
  // Match on "type base64" only, so a different comment is still a duplicate.
  final parts = line.split(' ');
  final core = parts.length >= 2 ? '${parts[0]} ${parts[1]}' : line;
  final qc = "'${core.replaceAll("'", "'\\''")}'";
  return 'umask 077; mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && '
      'chmod 600 ~/.ssh/authorized_keys && '
      'if grep -qF $qc ~/.ssh/authorized_keys; then echo MTERM_KEY_EXISTS; '
      'else { [ -s ~/.ssh/authorized_keys ] && [ -n "\$(tail -c1 ~/.ssh/authorized_keys)" ] && echo; echo $q; } >> ~/.ssh/authorized_keys && echo MTERM_KEY_ADDED; fi';
}
