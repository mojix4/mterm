class Host {
  String id;
  String label;
  String host;
  int port;
  String user;

  /// 'password' or 'key'
  String auth;
  int color;
  String? lastUsed;

  Host({
    required this.id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.user,
    this.auth = 'password',
    this.color = 0,
    this.lastUsed,
  });

  String get address => port == 22 ? '$user@$host' : '$user@$host:$port';

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'user': user,
        'auth': auth,
        'color': color,
        'lastUsed': lastUsed,
      };

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: j['id'] as String,
        label: (j['label'] ?? '') as String,
        host: (j['host'] ?? '') as String,
        port: (j['port'] ?? 22) as int,
        user: (j['user'] ?? 'root') as String,
        auth: (j['auth'] ?? 'password') as String,
        color: (j['color'] ?? 0) as int,
        lastUsed: j['lastUsed'] as String?,
      );
}

class HostSecret {
  String password;
  String privateKey;
  String passphrase;
  HostSecret({this.password = '', this.privateKey = '', this.passphrase = ''});
}

class Snippet {
  String id;
  String name;
  String cmd;
  Snippet({required this.id, required this.name, required this.cmd});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'cmd': cmd};
  factory Snippet.fromJson(Map<String, dynamic> j) =>
      Snippet(id: j['id'] as String, name: j['name'] as String, cmd: j['cmd'] as String);
}

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
