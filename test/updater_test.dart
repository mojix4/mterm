import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/updater.dart';

void main() {
  test('compareVersions', () {
    expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(compareVersions('v1.0.10', '1.0.10'), 0);
    expect(compareVersions('1.0.0', '1.0.11'), lessThan(0));
  });
  test('parseRelease picks platform asset', () {
    final j = {
      'tag_name': 'v1.0.12',
      'html_url': 'https://x/page',
      'assets': [
        {'name': 'MTerm-v1.0.12.apk', 'browser_download_url': 'https://x/a.apk'},
        {'name': 'MTerm-v1.0.12-windows-x64.zip', 'browser_download_url': 'https://x/w.zip'},
      ],
    };
    expect(parseRelease(j, windows: false).downloadUrl, 'https://x/a.apk');
    expect(parseRelease(j, windows: true).downloadUrl, 'https://x/w.zip');
    expect(parseRelease(j, windows: false).version, '1.0.12');
  });
}
