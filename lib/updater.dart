import 'dart:convert';
import 'dart:io';

/// Version baked in by CI (--dart-define=APP_VERSION=1.0.<run>).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

const releasesRepo = 'mojix4/mterm-releases';
const releasesPage = 'https://github.com/$releasesRepo/releases/latest';

class UpdateInfo {
  UpdateInfo(this.version, this.downloadUrl, this.pageUrl);
  final String version;
  final String downloadUrl;
  final String pageUrl;
}

/// Compares dotted versions ("1.0.10" > "1.0.9").
int compareVersions(String a, String b) {
  List<int> p(String v) =>
      v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+-]')).map((e) => int.tryParse(e) ?? 0).toList();
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Picks the installer for this platform from a GitHub release JSON.
UpdateInfo parseRelease(Map<String, dynamic> j, {required bool windows, bool ios = false}) {
  final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
  final page = j['html_url'] as String? ?? releasesPage;
  String? url;
  for (final a in (j['assets'] as List? ?? const [])) {
    final name = (a['name'] as String? ?? '').toLowerCase();
    final ok = ios
        ? name.endsWith('.ipa')
        : windows ? name.endsWith('.zip') && name.contains('windows') : name.endsWith('.apk');
    if (ok) url = a['browser_download_url'] as String?;
  }
  return UpdateInfo(tag, url ?? page, page);
}

/// Latest published release, or throws on network / API errors.
Future<UpdateInfo> fetchLatest() async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final req = await c.getUrl(Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'MTerm/$appVersion');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    return parseRelease(jsonDecode(body) as Map<String, dynamic>, windows: Platform.isWindows, ios: Platform.isIOS);
  } finally {
    c.close(force: true);
  }
}
