import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/suggest.dart';

void main() {
  test('built-in commands complete like Termius', () {
    expect(suggestCommands('apt', [], []).take(2), ['apt update', 'apt upgrade']);
    expect(suggestCommands('systemctl ', [], []).first, 'systemctl status ');
    expect(suggestCommands('', [], []), isEmpty);
    expect(suggestCommands(null, [], []), isEmpty);
  });
  test('history wins, no duplicates, max 4', () {
    final r = suggestCommands('ap', ['apt install nginx', 'apt update'], ['apt update && apt upgrade -y']);
    expect(r.first, 'apt install nginx');
    expect(r.length, 4);
    expect(r.where((e) => e == 'apt update').length, 1);
  });
}
