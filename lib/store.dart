import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'models.dart';

class AppSettings {
  /// Terminal colour scheme; 'Auto' follows the app's light/dark mode.
  String theme = 'Auto';

  /// App theme: system | dark | light.
  String appTheme = 'system';

  /// UI language: 'system' or a code from languageCodes.
  String language = 'system';
  double fontSize = 13;
  String cursor = 'block'; // block | underline | bar
  int scrollback = 5000;
  List<String> keys = List.of(defaultKeys);
  bool vibrate = true;
  int keepAlive = 30; // seconds, 0 = off
  bool wakelock = true;
  bool lockEnabled = false;
  bool biometric = false;
  String pinHash = '';
  int lockAfter = 60; // seconds in background before locking again

  /// Save each session's output to a text file (Settings > Session logs).
  bool logSessions = false;

  static const defaultKeys = [
    'esc', 'tab', 'ctrl', 'alt', '←', '↑', '↓', '→', '|', '/', '-', '~', 'home', 'end', '^C', 'paste'
  ];

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'appTheme': appTheme,
        'language': language,
        'fontSize': fontSize,
        'cursor': cursor,
        'scrollback': scrollback,
        'keys': keys,
        'vibrate': vibrate,
        'keepAlive': keepAlive,
        'wakelock': wakelock,
        'lockEnabled': lockEnabled,
        'biometric': biometric,
        'pinHash': pinHash,
        'lockAfter': lockAfter,
        'logSessions': logSessions,
      };

  void load(Map<String, dynamic> j) {
    theme = j['theme'] ?? theme;
    appTheme = j['appTheme'] ?? appTheme;
    language = j['language'] ?? language;
    fontSize = (j['fontSize'] ?? fontSize).toDouble();
    cursor = j['cursor'] ?? cursor;
    scrollback = j['scrollback'] ?? scrollback;
    keys = (j['keys'] as List?)?.cast<String>() ?? keys;
    vibrate = j['vibrate'] ?? vibrate;
    keepAlive = j['keepAlive'] ?? keepAlive;
    wakelock = j['wakelock'] ?? wakelock;
    lockEnabled = j['lockEnabled'] ?? lockEnabled;
    biometric = j['biometric'] ?? biometric;
    pinHash = j['pinHash'] ?? pinHash;
    lockAfter = j['lockAfter'] ?? lockAfter;
    logSessions = j['logSessions'] ?? logSessions;
  }
}

/// Single place that owns all persisted data.
/// Host details live in SharedPreferences; passwords and keys live in the
/// Android Keystore-backed secure storage.
class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  late SharedPreferences _p;
  // Android: Keystore-backed EncryptedSharedPreferences. Windows: DPAPI-encrypted
  // file in the app's support folder. Same storage keys on every platform.
  final _sec = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  List<Host> hosts = [];
  List<Snippet> snippets = [];
  Map<String, String> knownHosts = {};
  final settings = AppSettings();

  /// Commands the user ran (newest first), kept across sessions for suggestions.
  List<String> history = [];

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    // Same keys since 1.0 ('settings', 'hosts', 'snippets', 'known_hosts' and
    // pw_/key_/pp_<id> in secure storage): updates never migrate or wipe them.
    settings.load(jsonDecode(_p.getString('settings') ?? '{}'));
    hosts = _list('hosts').map(Host.fromJson).toList();
    final sn = _p.getString('snippets');
    // Untouched defaults are not persisted, so they come up in the current language.
    snippets = sn == null ? _defaultSnippets() : _list('snippets').map(Snippet.fromJson).toList();
    knownHosts = Map<String, String>.from(jsonDecode(_p.getString('known_hosts') ?? '{}'));
    history = _p.getStringList('cmd_history') ?? [];
  }

  void addHistory(String cmd) {
    final c = cmd.trim();
    if (c.isEmpty || c.length > 500) return;
    history.remove(c);
    history.insert(0, c);
    if (history.length > 500) history.removeRange(500, history.length);
    _p.setStringList('cmd_history', history);
  }

  Future<void> clearHistory() async {
    history = [];
    await _p.remove('cmd_history');
    notifyListeners();
  }

  List<Map<String, dynamic>> _list(String k) =>
      (jsonDecode(_p.getString(k) ?? '[]') as List).cast<Map<String, dynamic>>();

  List<Snippet> _defaultSnippets() {
    final s = S.current;
    return [
      Snippet(id: 's1', name: s['snipRamDisk'], cmd: 'free -h && df -h /'),
      Snippet(id: 's2', name: s['snipTopProcs'], cmd: 'ps aux --sort=-%mem | head -12'),
      Snippet(id: 's3', name: s['snipOpenPorts'], cmd: 'ss -tulpn'),
      Snippet(id: 's4', name: s['snipFailedServices'], cmd: 'systemctl --failed'),
      Snippet(id: 's5', name: s['snipUpdate'], cmd: 'apt update && apt upgrade -y'),
      Snippet(id: 's6', name: s['snipMonitor'], cmd: 'htop'),
    ];
  }

  Future<void> _saveHosts() => _p.setString('hosts', jsonEncode(hosts.map((h) => h.toJson()).toList()));
  Future<void> _saveSnippets() =>
      _p.setString('snippets', jsonEncode(snippets.map((s) => s.toJson()).toList()));
  Future<void> saveSettings() async {
    await _p.setString('settings', jsonEncode(settings.toJson()));
    notifyListeners();
  }

  // ---- hosts
  Future<void> upsertHost(Host h, HostSecret s) async {
    final idx = hosts.indexWhere((x) => x.id == h.id);
    if (idx >= 0) {
      hosts[idx] = h;
    } else {
      hosts.add(h);
    }
    await _sec.write(key: 'pw_${h.id}', value: s.password);
    await _sec.write(key: 'key_${h.id}', value: s.privateKey);
    await _sec.write(key: 'pp_${h.id}', value: s.passphrase);
    await _saveHosts();
    notifyListeners();
  }

  /// Saves changed host details (not its password or key).
  Future<void> updateHost(Host h) async {
    final idx = hosts.indexWhere((x) => x.id == h.id);
    if (idx < 0) return;
    hosts[idx] = h;
    await _saveHosts();
    notifyListeners();
  }

  /// Stores a private key for host [id] (e.g. one generated by the app).
  Future<void> saveKey(String id, String privateKey, {String passphrase = ''}) async {
    await _sec.write(key: 'key_$id', value: privateKey);
    await _sec.write(key: 'pp_$id', value: passphrase);
    notifyListeners();
  }

  Future<void> deleteHost(Host h) async {
    hosts.removeWhere((x) => x.id == h.id);
    for (final k in ['pw_', 'key_', 'pp_']) {
      await _sec.delete(key: '$k${h.id}');
    }
    await _saveHosts();
    notifyListeners();
  }

  Future<void> touchHost(Host h) async {
    h.lastUsed = DateTime.now().toIso8601String();
    await _saveHosts();
    notifyListeners();
  }

  Future<HostSecret> secret(String id) async => HostSecret(
        password: await _read('pw_$id'),
        privateKey: await _read('key_$id'),
        passphrase: await _read('pp_$id'),
      );

  /// A failed read (e.g. keystore hiccup) is treated as "not saved" so the app
  /// asks for the password instead of crashing; nothing is deleted.
  Future<String> _read(String key) async {
    try {
      return await _sec.read(key: key) ?? '';
    } catch (e) {
      debugPrint('secure storage read $key failed: $e');
      return '';
    }
  }

  /// Remembers [password] for host [id] (used after a successful login when
  /// "Remember password" was ticked). Replaces a wrong saved password.
  Future<void> savePassword(String id, String password) async {
    await _sec.write(key: 'pw_$id', value: password);
    notifyListeners();
  }

  // ---- snippets
  Future<void> upsertSnippet(Snippet s) async {
    final idx = snippets.indexWhere((x) => x.id == s.id);
    if (idx >= 0) {
      snippets[idx] = s;
    } else {
      snippets.add(s);
    }
    await _saveSnippets();
    notifyListeners();
  }

  Future<void> deleteSnippet(Snippet s) async {
    snippets.removeWhere((x) => x.id == s.id);
    await _saveSnippets();
    notifyListeners();
  }

  // ---- restore from backup
  Future<void> importSnippets(List<Snippet> items, {required bool replace}) async {
    if (replace) snippets = [];
    for (final sn in items) {
      final idx = snippets.indexWhere((x) => x.id == sn.id);
      if (idx >= 0) {
        snippets[idx] = sn;
      } else {
        snippets.add(sn);
      }
    }
    await _saveSnippets();
    notifyListeners();
  }

  Future<void> importKnownHosts(Map<String, String> items, {required bool replace}) async {
    if (replace) {
      knownHosts = Map.of(items);
    } else {
      // keep the key we already trust for a server
      for (final e in items.entries) {
        knownHosts.putIfAbsent(e.key, () => e.value);
      }
    }
    await _p.setString('known_hosts', jsonEncode(knownHosts));
    notifyListeners();
  }

  Future<void> importHistory(List<String> items, {required bool replace}) async {
    final merged = <String>[...(replace ? const <String>[] : history)];
    for (final c in items) {
      if (!merged.contains(c)) merged.add(c);
    }
    history = merged.take(500).toList();
    await _p.setStringList('cmd_history', history);
    notifyListeners();
  }

  // ---- known hosts (trust on first use)
  String? knownFingerprint(String host, int port) => knownHosts['$host:$port'];
  Future<void> trust(String host, int port, String fp) async {
    knownHosts['$host:$port'] = fp;
    await _p.setString('known_hosts', jsonEncode(knownHosts));
    notifyListeners();
  }

  Future<void> clearKnownHosts() async {
    knownHosts.clear();
    await _p.setString('known_hosts', '{}');
    notifyListeners();
  }

  // ---- PIN
  static String hashPin(String pin) => sha256.convert(utf8.encode('mterm:$pin')).toString();
}
