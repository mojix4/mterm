// Finds text in the terminal buffer (scrollback + screen) for the search bar.
import 'package:xterm/xterm.dart';

class TermMatch {
  const TermMatch(this.y, this.x, this.length);

  /// Absolute buffer line and column of the first cell.
  final int y, x;
  final int length;
  @override
  bool operator ==(Object o) => o is TermMatch && o.y == y && o.x == x && o.length == length;
  @override
  int get hashCode => Object.hash(y, x, length);
  @override
  String toString() => 'TermMatch($y, $x, $length)';
}

/// Case-insensitive matches of [query] in [buffer], top to bottom (max [limit]).
List<TermMatch> findInBuffer(Buffer buffer, String query, {int limit = 1000}) {
  final q = query.toLowerCase();
  final out = <TermMatch>[];
  if (q.isEmpty) return out;
  for (var y = 0; y < buffer.lines.length && out.length < limit; y++) {
    final line = buffer.lines[y];
    // Map text positions back to cells (wide CJK chars take two cells).
    final cols = <int>[];
    final sb = StringBuffer();
    for (var x = 0; x < line.length; x++) {
      final cp = line.getCodePoint(x);
      if (cp == 0) {
        if (line.getWidth(x) == 0 && x > 0) continue; // second half of a wide char
        sb.write(' ');
      } else {
        sb.writeCharCode(cp);
      }
      final added = sb.length - cols.length;
      for (var i = 0; i < added; i++) {
        cols.add(x);
      }
    }
    final text = sb.toString().toLowerCase();
    var from = 0;
    while (out.length < limit) {
      final i = text.indexOf(q, from);
      if (i < 0 || i + q.length > cols.length) break;
      final x0 = cols[i];
      final xLast = cols[i + q.length - 1];
      final w = line.getWidth(xLast);
      out.add(TermMatch(y, x0, xLast + (w > 1 ? w : 1) - x0));
      from = i + q.length;
    }
  }
  return out;
}
