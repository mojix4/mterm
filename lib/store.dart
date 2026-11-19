import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppSettings {
  String theme = 'Termius';
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

  static const defaultKeys = [
    'esc', 'tab', 'ctrl', 'alt', '←', '↑', '↓', '→', '|', '/', '-', '~', 'home', 'end', '^C', 'paste'
  ];

  Map<String, dynamic> toJson() => {
        'theme': theme,
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
      };

  void load(Map<String, dynamic> j) {
    theme = j['theme'] ?? theme;
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
  }
}

/// Single place that owns all persisted data.
/// Host details live in SharedPreferences; passwords and keys live in the
/// Android Keystore-backed secure storage.
class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  late SharedPreferences _p;
  final _sec = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  List<Host> hosts = [];
  List<Snippet> snippets = [];
  Map<String, String> knownHosts = {};
  final settings = AppSettings();

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    hosts = _list('hosts').map(Host.fromJson).toList();
    final sn = _p.getString('snippets');
    snippets = sn == null ? _defaultSnippets() : _list('snippets').map(Snippet.fromJson).toList();
    knownHosts = Map<String, String>.from(jsonDecode(_p.getString('known_hosts') ?? '{}'));
    settings.load(jsonDecode(_p.getString('settings') ?? '{}'));
  }

  List<Map<String, dynamic>> _list(String k) =>
      (jsonDecode(_p.getString(k) ?? '[]') as List).cast<Map<String, dynamic>>();

  List<Snippet> _defaultSnippets() => [
        Snippet(id: 's1', name: 'مصرف رم و دیسک', cmd: 'free -h && df -h /'),
        Snippet(id: 's2', name: 'پرمصرف‌ترین پردازش‌ها', cmd: 'ps aux --sort=-%mem | head -12'),
        Snippet(id: 's3', name: 'پورت‌های باز', cmd: 'ss -tulpn'),
        Snippet(id: 's4', name: 'سرویس‌های خراب', cmd: 'systemctl --failed'),
        Snippet(id: 's5', name: 'آپدیت سیستم', cmd: 'apt update && apt upgrade -y'),
        Snippet(id: 's6', name: 'مانیتور زنده', cmd: 'htop'),
      ];

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
        password: await _sec.read(key: 'pw_$id') ?? '',
        privateKey: await _sec.read(key: 'key_$id') ?? '',
        passphrase: await _sec.read(key: 'pp_$id') ?? '',
      );

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
