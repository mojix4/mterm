import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../session.dart';
import '../themes.dart';
import 'terminal_screen.dart';

/// A rounded card section like Termius' grouped lists.
class Section extends StatelessWidget {
  const Section({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 18, 8, 8),
          child: Text(title!, style: const TextStyle(color: C.muted, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            children[i],
          ]
        ]),
      ),
    ]);
  }
}

class Ltr extends StatelessWidget {
  const Ltr(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) =>
      Text(text, textDirection: TextDirection.ltr, style: style, overflow: TextOverflow.ellipsis, maxLines: 1);
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'تأیید', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok, style: TextStyle(color: danger ? C.red : C.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Shown when a server presents a key we have not seen, or a changed key.
Future<bool> hostKeyPrompt(String type, String fp, String? old) async {
  final ctx = navKey.currentContext;
  if (ctx == null) return false;
  final changed = old != null;
  final r = await showDialog<bool>(
    context: ctx,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      scrollable: true,
      icon: Icon(changed ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
          color: changed ? C.red : C.green, size: 36),
      title: Text(changed ? 'کلید سرور عوض شده!' : 'سرور جدید'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(changed
            ? 'کلید این سرور با دفعه قبل فرق دارد. اگر سرور را دوباره نصب نکرده‌اید، ممکن است کسی وسط راه باشد.'
            : 'اولین بار است به این سرور وصل می‌شوید. اثر انگشت کلید سرور:'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
          child: Text('$type\n$fp',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, color: C.muted)),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رد کردن')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(changed ? 'به هر حال وصل شو' : 'اعتماد و اتصال',
              style: TextStyle(color: changed ? C.red : C.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Opens a new SSH session to [h] and shows its terminal.
void openHost(BuildContext context, Host h) {
  final s = Sessions.i.open(h);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TerminalScreen(session: s)));
  s.connect(hostKeyPrompt);
}

void openSession(BuildContext context, TermSession s) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TerminalScreen(session: s)));
}

class HostAvatar extends StatelessWidget {
  const HostAvatar({super.key, required this.color, this.live = false, this.size = 44});
  final int color;
  final bool live;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = C.hostColors[color % C.hostColors.length];
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(13)),
        child: Icon(Icons.terminal_rounded, color: c, size: size * 0.5),
      ),
      if (live)
        PositionedDirectional(
          end: -2,
          bottom: -2,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
                color: C.green, shape: BoxShape.circle, border: Border.all(color: C.surface, width: 2.5)),
          ),
        ),
    ]);
  }
}
