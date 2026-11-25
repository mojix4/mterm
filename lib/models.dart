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

  /// Optional folder in the hosts list ('' = none).
  String group;
  List<String> tags;

  /// Command typed once right after the shell starts ('' = none).
  String startupCmd;

  /// Id of another saved host to connect through (SSH jump / ProxyJump).
  String? jumpHostId;

  /// Port forwarding rules started with each session.
  List<ForwardRule> forwards;

  Host({
    required this.id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.user,
    this.auth = 'password',
    this.color = 0,
    this.lastUsed,
    this.group = '',
    List<String>? tags,
    this.startupCmd = '',
    this.jumpHostId,
    List<ForwardRule>? forwards,
  })  : tags = tags ?? [],
        forwards = forwards ?? [];

  String get name => label.isEmpty ? host : label;

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
        // Newer optional fields: older app versions simply ignore them, and
        // hosts saved by older versions load with the defaults.
        if (group.isNotEmpty) 'group': group,
        if (tags.isNotEmpty) 'tags': tags,
        if (startupCmd.isNotEmpty) 'startupCmd': startupCmd,
        if (jumpHostId != null) 'jumpHostId': jumpHostId,
        if (forwards.isNotEmpty) 'forwards': forwards.map((f) => f.toJson()).toList(),
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
        group: (j['group'] ?? '') as String,
        tags: (j['tags'] as List?)?.map((e) => '$e').toList(),
        startupCmd: (j['startupCmd'] ?? '') as String,
        jumpHostId: j['jumpHostId'] as String?,
        forwards: (j['forwards'] as List?)
            ?.whereType<Map>()
            .map((e) => ForwardRule.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  Host copy() => Host.fromJson(toJson());
}

/// One port forwarding rule. 'local': 127.0.0.1:[localPort] on this device ->
/// [remoteHost]:[remotePort] as seen from the server. 'dynamic': a SOCKS5
/// proxy on 127.0.0.1:[localPort] whose connections leave from the server.
class ForwardRule {
  ForwardRule({
    String? id,
    this.type = 'local',
    required this.localPort,
    this.remoteHost = '127.0.0.1',
    this.remotePort = 0,
    this.autoStart = true,
  }) : id = id ?? newId();

  String id;
  String type; // local | dynamic
  int localPort;
  String remoteHost;
  int remotePort;
  bool autoStart;

  bool get isDynamic => type == 'dynamic';

  /// Short ASCII description, e.g. "L 8080 → 127.0.0.1:80" or "D 1080 (SOCKS5)".
  String get summary => isDynamic ? 'D $localPort (SOCKS5)' : 'L $localPort → $remoteHost:$remotePort';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
        'autoStart': autoStart,
      };

  factory ForwardRule.fromJson(Map<String, dynamic> j) => ForwardRule(
        id: j['id'] as String?,
        type: (j['type'] ?? 'local') as String,
        localPort: (j['localPort'] ?? 0) as int,
        remoteHost: (j['remoteHost'] ?? '127.0.0.1') as String,
        remotePort: (j['remotePort'] ?? 0) as int,
        autoStart: (j['autoStart'] ?? true) as bool,
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
