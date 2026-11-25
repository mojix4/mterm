// Unit tests for the Termius-style features (no SSH server needed; runs in CI):
// host model compatibility, groups/tags search, ANSI stripping for logs,
// output search, encrypted backup, key generation + authorized_keys command.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/backup.dart';
import 'package:mterm/keys.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/host_edit_screen.dart' show parseTags;
import 'package:mterm/screens/hosts_screen.dart' show hostMatches, groupHosts;
import 'package:mterm/session_log.dart';
import 'package:mterm/sftp_ops.dart';
import 'package:mterm/store.dart';
import 'package:mterm/term_search.dart';
import 'package:xterm/xterm.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installMocks);
  setUp(freshStore);

  group('host model', () {
    test('hosts saved by older versions load with empty new fields', () {
      final h = Host.fromJson(
          {'id': 'a', 'label': 'x', 'host': '1.2.3.4', 'port': 22, 'user': 'root', 'auth': 'password', 'color': 1});
      expect(h.group, '');
      expect(h.tags, isEmpty);
      expect(h.startupCmd, '');
      expect(h.jumpHostId, isNull);
      expect(h.forwards, isEmpty);
      // and nothing new is written for them, so older app versions read the same JSON
      expect(h.toJson().keys.toSet(), {'id', 'label', 'host', 'port', 'user', 'auth', 'color', 'lastUsed'});
    });

    test('new fields round-trip', () {
      final h = Host(
        id: 'b',
        label: 'web',
        host: 'example.com',
        user: 'u',
        group: 'Work',
        tags: ['de', 'xui'],
        startupCmd: 'cd /srv',
        jumpHostId: 'a',
        forwards: [
          ForwardRule(id: 'r1', localPort: 8080, remoteHost: 'localhost', remotePort: 80),
          ForwardRule(id: 'r2', type: 'dynamic', localPort: 1080, autoStart: false),
        ],
      );
      final back = Host.fromJson(jsonDecode(jsonEncode(h.toJson())) as Map<String, dynamic>);
      expect([back.group, back.tags, back.startupCmd, back.jumpHostId], ['Work', ['de', 'xui'], 'cd /srv', 'a']);
      expect(back.forwards.map((f) => f.summary), ['L 8080 → localhost:80', 'D 1080 (SOCKS5)']);
      expect(back.forwards[1].autoStart, isFalse);
      expect(back.forwards[1].isDynamic, isTrue);
    });

    test('tags parse from commas (also Persian comma), no duplicates', () {
      expect(parseTags(' de, xui،vpn ,de,, '), ['de', 'xui', 'vpn']);
    });

    test('search covers name, address, user, group and tags; groups sorted, ungrouped last', () {
      final a = Host(id: 'a', label: 'Alpha', host: '10.0.0.1', user: 'root', group: 'Work', tags: ['germany']);
      final b = Host(id: 'b', label: 'Beta', host: 'b.example', user: 'admin');
      final c = Host(id: 'c', label: 'Gamma', host: '10.0.0.3', user: 'root', group: 'Arvan');
      expect(hostMatches(a, 'germ'), isTrue);
      expect(hostMatches(a, 'work'), isTrue);
      expect(hostMatches(b, 'admin'), isTrue);
      expect(hostMatches(b, 'germ'), isFalse);
      expect(groupHosts([a, b, c]).keys.toList(), ['Arvan', 'Work', '']);
    });
  });

  group('session log', () {
    test('ANSI codes are stripped even when split across chunks', () {
      final st = AnsiStripper();
      final out = [
        st.convert('\x1b[32mok\x1b['),
        st.convert('0m done\r\n'),
        st.convert('\x1b]0;title\x07x\x1b(By\n'),
      ].join();
      expect(out, 'ok done\nxy\n');
      expect(stripAnsi('ab\x08c'), 'ac');
    });

    test('file names are safe and sortable', () {
      expect(logFileName('my server/1', DateTime(2026, 1, 2, 3, 4, 5)), 'my_server_1_20260102-030405.txt');
    });

    test('a session log file collects plain text', () async {
      final tmp = await Directory.systemTemp.createTemp('mterm_logs');
      addTearDown(() => tmp.delete(recursive: true));
      appDocsDir = () async => tmp;
      final log = (await SessionLog.open('srv'))!;
      log.write('\x1b[1mhello\x1b[0m\r\n');
      log.write('world\n');
      await log.close();
      final files = await listLogs();
      expect(files, hasLength(1));
      expect(files.single.readAsStringSync(), 'hello\nworld\n');
    });
  });

  group('search in output', () {
    test('finds matches case-insensitively with cell positions', () {
      final t = Terminal(maxLines: 1000);
      t.write('Hello world\r\nfoo HELLO bar hello\r\n');
      final m = findInBuffer(t.buffer, 'hello');
      expect(m, [const TermMatch(0, 0, 5), const TermMatch(1, 4, 5), const TermMatch(1, 14, 5)]);
      expect(findInBuffer(t.buffer, ''), isEmpty);
      expect(findInBuffer(t.buffer, 'zzz'), isEmpty);
    });

    test('wide characters map to the right columns', () {
      final t = Terminal(maxLines: 100);
      t.write('中文 abc\r\n');
      expect(findInBuffer(t.buffer, 'abc'), [const TermMatch(0, 5, 3)]);
      expect(findInBuffer(t.buffer, '文'), [const TermMatch(0, 2, 2)]);
    });
  });

  group('backup', () {
    test('encrypt / decrypt round trip; wrong password and foreign file are rejected', () {
      final plain = Uint8List.fromList(utf8.encode('{"app":"mterm"}'));
      final enc = encryptBackup(plain, 'secret-pass', iterations: 2000);
      expect(ascii.decode(enc.sublist(0, 8)), 'MTERMBK1');
      expect(latin1.decode(enc).contains('mterm"'), isFalse, reason: 'payload must be encrypted');
      expect(decryptBackup(enc, 'secret-pass'), plain);
      expect(() => decryptBackup(enc, 'wrong'), throwsA(isA<BackupError>().having((e) => e.wrongPassword, 'wrong', true)));
      expect(() => decryptBackup(Uint8List.fromList(utf8.encode('hello world, not a backup at all.....')), 'x'),
          throwsA(isA<BackupError>().having((e) => e.wrongPassword, 'wrong', false)));
      // two exports of the same data differ (random salt + nonce)
      expect(encryptBackup(plain, 'secret-pass', iterations: 2000), isNot(enc));
    });

    test('collect -> replace restores servers, secrets, commands, known keys, history; PIN stays local', () async {
      final st = Store.i;
      await st.upsertHost(Host(id: 'h1', label: 'one', host: '1.1.1.1', user: 'root', tags: ['t']),
          HostSecret(password: 'pw1'));
      await st.upsertHost(Host(id: 'h2', label: 'two', host: '2.2.2.2', user: 'root', auth: 'key'),
          HostSecret(privateKey: 'KEYDATA', passphrase: 'pp'));
      await st.upsertSnippet(Snippet(id: 'x', name: 'mine', cmd: 'uptime'));
      await st.trust('1.1.1.1', 22, 'aa:bb');
      st.addHistory('ls -la');
      st.settings
        ..fontSize = 17
        ..pinHash = 'PIN_A'
        ..lockEnabled = true;
      await st.saveSettings();
      final data = jsonDecode(jsonEncode(await collectBackup())) as Map<String, dynamic>;
      expect((data['settings'] as Map).containsKey('pinHash'), isFalse);

      // a different device
      await freshStore();
      await st.upsertHost(Host(id: 'other', label: 'local', host: '9.9.9.9', user: 'root'), HostSecret());
      st.settings.pinHash = 'PIN_B';
      await st.saveSettings();
      final r = await applyBackup(data, replace: true);
      expect(r.hosts, 2);
      await reloadStore();
      expect(st.hosts.map((h) => h.id).toSet(), {'h1', 'h2'});
      expect(st.hosts.firstWhere((h) => h.id == 'h1').tags, ['t']);
      expect((await st.secret('h1')).password, 'pw1');
      expect((await st.secret('h2')).privateKey, 'KEYDATA');
      expect((await st.secret('h2')).passphrase, 'pp');
      expect(secure.containsKey('pw_other'), isFalse);
      expect(st.snippets.any((s) => s.cmd == 'uptime'), isTrue);
      expect(st.knownFingerprint('1.1.1.1', 22), 'aa:bb');
      expect(st.history, contains('ls -la'));
      expect(st.settings.fontSize, 17);
      expect(st.settings.pinHash, 'PIN_B', reason: 'the PIN of this device is never replaced');
    });

    test('merge keeps current servers and settings and adds the backup', () async {
      final st = Store.i;
      await st.upsertHost(Host(id: 'h1', label: 'one', host: '1.1.1.1', user: 'root'), HostSecret(password: 'pw1'));
      final data = jsonDecode(jsonEncode(await collectBackup())) as Map<String, dynamic>;
      await freshStore();
      await st.upsertHost(Host(id: 'mine', label: 'mine', host: '5.5.5.5', user: 'root'), HostSecret(password: 'm'));
      st.settings.fontSize = 21;
      await st.saveSettings();
      await applyBackup(data, replace: false);
      await reloadStore();
      expect(st.hosts.map((h) => h.id).toSet(), {'mine', 'h1'});
      expect((await st.secret('mine')).password, 'm');
      expect(st.settings.fontSize, 21);
    });
  });

  group('ssh keys', () {
    test('generated Ed25519 key is a valid OpenSSH key and its public line matches', () {
      final g = generateEd25519(comment: 'mterm@test');
      expect(g.privatePem, contains('BEGIN OPENSSH PRIVATE KEY'));
      expect(g.publicLine, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
      expect(g.publicLine, endsWith(' mterm@test'));
      final pairs = SSHKeyPair.fromPem(g.privatePem);
      expect(pairs.single.type, 'ssh-ed25519');
      expect(publicKeyFromPrivate(g.privatePem, comment: 'mterm@test'), g.publicLine);
      // signs and verifies
      final sig = pairs.single.sign(Uint8List.fromList([1, 2, 3]));
      expect(sig.encode(), isNotEmpty);
      expect(generateEd25519().publicLine, isNot(g.publicLine));
      expect(publicKeyFromPrivate('garbage'), isNull);
    });

    test('install command adds the key once, with safe permissions', () async {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      final home = await Directory.systemTemp.createTemp('mterm_home');
      addTearDown(() => home.delete(recursive: true));
      final key = generateEd25519(comment: "it's me").publicLine;
      Future<String> run(String line) async {
        final r = await Process.run('sh', ['-c', installKeyCommand(line)], environment: {'HOME': home.path});
        return '${r.stdout}${r.stderr}';
      }

      // an existing file without trailing newline must not get glued to our key
      Directory('${home.path}/.ssh').createSync();
      File('${home.path}/.ssh/authorized_keys').writeAsStringSync('ssh-rsa AAAAOLD old');
      expect(await run(key), contains('MTERM_KEY_ADDED'));
      expect(await run(key), contains('MTERM_KEY_EXISTS'));
      // same key, other comment: still a duplicate
      expect(await run(key.replaceAll("it's me", 'other')), contains('MTERM_KEY_EXISTS'));
      final lines = File('${home.path}/.ssh/authorized_keys').readAsLinesSync();
      expect(lines, ['ssh-rsa AAAAOLD old', key]);
      final mode = (await Process.run('stat', ['-c', '%a', '${home.path}/.ssh', '${home.path}/.ssh/authorized_keys']))
          .stdout
          .toString()
          .split('\n');
      expect(mode.take(2), ['700', '600']);
    });
  });

  test('sftp path helpers and sizes', () {
    expect(joinRemote('/', 'a'), '/a');
    expect(joinRemote('/home/u', 'a'), '/home/u/a');
    expect(parentRemote('/home/u'), '/home');
    expect(parentRemote('/home'), '/');
    expect(parentRemote('/'), '/');
    expect(formatSize(512), '512 B');
    expect(formatSize(1536), '1.5 KB');
    expect(formatSize(50 * 1024 * 1024), '50 MB');
  });
}
