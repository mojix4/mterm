// Encrypted backup of everything the user set up: servers with their passwords
// and keys, commands, settings (not the PIN lock), known server keys and
// command history.
//
// File format (.mterm): "MTERMBK1" | iterations (uint32 BE) | salt (16) |
// nonce (12) | AES-256-GCM(ciphertext + 16-byte tag) of the UTF-8 JSON payload.
// The key is PBKDF2-HMAC-SHA256(password, salt, iterations).
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'models.dart';
import 'store.dart';

const _magic = 'MTERMBK1';
const backupIterations = 120000;

class BackupError implements Exception {
  BackupError(this.wrongPassword);

  /// True when the password is wrong or the file was changed; false when the
  /// file is not an MTerm backup at all.
  final bool wrongPassword;
  @override
  String toString() => wrongPassword ? 'wrong password or damaged backup' : 'not an MTerm backup';
}

Uint8List _deriveKey(String password, Uint8List salt, int iterations) {
  final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
  return d.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List _random(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// Encrypts [plain] with [password]. Pure, so it can run in an isolate.
Uint8List encryptBackup(Uint8List plain, String password, {int iterations = backupIterations}) {
  final salt = _random(16), nonce = _random(12);
  final key = _deriveKey(password, salt, iterations);
  final gcm = GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final ct = gcm.process(plain);
  final it = ByteData(4)..setUint32(0, iterations);
  return Uint8List.fromList([...ascii.encode(_magic), ...it.buffer.asUint8List(), ...salt, ...nonce, ...ct]);
}

/// Decrypts a backup file. Throws [BackupError].
Uint8List decryptBackup(Uint8List data, String password) {
  if (data.length < 8 + 4 + 16 + 12 + 16 || ascii.decode(data.sublist(0, 8), allowInvalid: true) != _magic) {
    throw BackupError(false);
  }
  final iterations = ByteData.sublistView(data, 8, 12).getUint32(0);
  if (iterations < 1000 || iterations > 10000000) throw BackupError(false);
  final salt = data.sublist(12, 28), nonce = data.sublist(28, 40), ct = data.sublist(40);
  final key = _deriveKey(password, salt, iterations);
  final gcm = GCMBlockCipher(AESEngine())..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  try {
    return gcm.process(ct);
  } catch (_) {
    throw BackupError(true);
  }
}

/// Settings that never leave the device (the PIN lock belongs to this phone).
const _localOnlySettings = {'pinHash', 'lockEnabled', 'biometric'};

/// Everything to back up, as JSON-ready data.
Future<Map<String, dynamic>> collectBackup() async {
  final st = Store.i;
  final secrets = <String, dynamic>{};
  for (final h in st.hosts) {
    final sec = await st.secret(h.id);
    secrets[h.id] = {
      'pw': sec.password,
      'key': sec.privateKey,
      'pp': sec.passphrase,
      if (sec.proxyPassword.isNotEmpty) 'pxp': sec.proxyPassword,
    };
  }
  return {
    'app': 'mterm',
    'version': 1,
    'created': DateTime.now().toIso8601String(),
    'hosts': st.hosts.map((h) => h.toJson()).toList(),
    'secrets': secrets,
    'snippets': st.snippets.map((s) => s.toJson()).toList(),
    'settings': st.settings.toJson()..removeWhere((k, _) => _localOnlySettings.contains(k)),
    'knownHosts': st.knownHosts,
    'history': st.history,
  };
}

/// Builds the encrypted backup file contents.
Future<Uint8List> createBackup(String password) async {
  final plain = Uint8List.fromList(utf8.encode(jsonEncode(await collectBackup())));
  return compute((_) => encryptBackup(plain, password), null);
}

/// Decrypts and parses a backup file (in an isolate). Throws [BackupError].
Future<Map<String, dynamic>> readBackup(Uint8List data, String password) async {
  final plain = await compute((_) => decryptBackup(data, password), null);
  try {
    final j = jsonDecode(utf8.decode(plain));
    if (j is Map<String, dynamic> && j['app'] == 'mterm') return j;
  } catch (_) {}
  throw BackupError(false);
}

class RestoreResult {
  const RestoreResult(this.hosts, this.snippets);
  final int hosts, snippets;
}

/// Applies a decrypted backup. [replace]: wipe current servers, commands,
/// known keys and history first and take the backup's settings too.
/// Otherwise merge: add the backup's items (same id = backup wins), keep the
/// current settings and known keys.
Future<RestoreResult> applyBackup(Map<String, dynamic> j, {required bool replace}) async {
  final st = Store.i;
  final hosts = (j['hosts'] as List? ?? []).whereType<Map>().map((e) => Host.fromJson(e.cast<String, dynamic>()));
  final secrets = (j['secrets'] as Map?)?.cast<String, dynamic>() ?? {};
  final snippets =
      (j['snippets'] as List? ?? []).whereType<Map>().map((e) => Snippet.fromJson(e.cast<String, dynamic>())).toList();
  final known = ((j['knownHosts'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v'));
  final history = ((j['history'] as List?) ?? []).map((e) => '$e').toList();

  if (replace) {
    for (final h in List.of(st.hosts)) {
      await st.deleteHost(h);
    }
  }
  var n = 0;
  for (final h in hosts) {
    final sec = (secrets[h.id] as Map?)?.cast<String, dynamic>() ?? {};
    await st.upsertHost(
        h,
        HostSecret(
            password: (sec['pw'] ?? '') as String,
            privateKey: (sec['key'] ?? '') as String,
            passphrase: (sec['pp'] ?? '') as String,
            proxyPassword: (sec['pxp'] ?? '') as String));
    n++;
  }
  await st.importSnippets(snippets, replace: replace);
  await st.importKnownHosts(known, replace: replace);
  await st.importHistory(history, replace: replace);
  if (replace) {
    final keep = {for (final k in _localOnlySettings) k: st.settings.toJson()[k]};
    final set = ((j['settings'] as Map?) ?? {}).cast<String, dynamic>();
    st.settings.load({...set, ...keep});
    await st.saveSettings();
  }
  return RestoreResult(n, snippets.length);
}
