// Privacy mode: hides server addresses and user names in the app's own UI
// (lists, titles, dialogs), e.g. for screenshots or screen sharing. Terminal
// output is never changed.
import 'models.dart';
import 'store.dart';

bool get privacyOn => Store.i.settings.privacy;

const _dots = '•••';

/// "203.0.113.7" → "•••.•••.•••.•••", "srv.example.com" → "•••.•••.•••".
String maskHost(String host) {
  final h = host.trim();
  if (h.isEmpty) return h;
  final parts = h.split(RegExp(r'[.:]'));
  if (parts.length <= 1) return _dots;
  return parts.take(4).map((_) => _dots).join(h.contains('.') ? '.' : ':');
}

/// Hides IPv4/IPv6 addresses and "user@host" pairs inside free text.
String maskText(String text) => text
    .replaceAllMapped(RegExp(r'[\w.\-]+@[\w.\-:\[\]]+'), (_) => '$_dots@$_dots')
    .replaceAllMapped(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b'), (_) => '$_dots.$_dots.$_dots.$_dots')
    .replaceAllMapped(RegExp(r'\b([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\b'), (m) => m[0]!.length > 4 ? _dots : m[0]!);

/// The server's name as shown in the UI: its label, or its (masked) address.
String hostTitle(Host h, {bool? hide}) {
  final p = hide ?? privacyOn;
  final label = h.label.trim();
  if (label.isEmpty || label == h.host) return p ? maskHost(h.host) : h.host;
  return p ? maskText(label) : label;
}

/// "user@host[:port]" as shown in the UI.
String hostAddress(Host h, {bool? hide}) {
  if (!(hide ?? privacyOn)) return h.address;
  final a = '$_dots@${maskHost(h.host)}';
  return h.port == 22 ? a : '$a:${h.port}';
}

/// Free text from the server (e.g. a terminal window title) for the UI.
String uiText(String text) => privacyOn ? maskText(text) : text;
