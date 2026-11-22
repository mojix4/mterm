import 'package:flutter/material.dart';

import '../l10n.dart';
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
          child: Text(title!, style: TextStyle(color: context.pal.muted, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      Material(
        color: context.pal.surface,
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

Future<bool> confirm(BuildContext context, String title, String body, {String? ok, bool danger = false}) async {
  final s = S.of(context);
  final p = context.pal;
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s['cancel'])),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok ?? s['ok'], style: TextStyle(color: danger ? p.red : p.accent, fontWeight: FontWeight.w700)),
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
  final s = S.of(ctx);
  final p = ctx.pal;
  final r = await showDialog<bool>(
    context: ctx,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      scrollable: true,
      icon: Icon(changed ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
          color: changed ? p.red : p.green, size: 36),
      title: Text(changed ? s['hostKeyChangedTitle'] : s['hostKeyNewTitle']),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(changed ? s['hostKeyChangedBody'] : s['hostKeyNewBody']),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(10)),
          child: Text('$type\n$fp',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, color: p.muted)),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s['reject'])),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(changed ? s['connectAnyway'] : s['trustConnect'],
              style: TextStyle(color: changed ? p.red : p.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a server password (none saved, or the saved one was rejected),
/// with "Remember password" ticked by default.
Future<PasswordAnswer?> passwordPrompt(Host h, {bool wrong = false}) async {
  final ctx = navKey.currentContext;
  if (ctx == null) return null;
  final s = S.of(ctx);
  final p = ctx.pal;
  final pw = TextEditingController();
  var remember = true;
  var show = false;
  void submit(BuildContext c) {
    if (pw.text.isEmpty) return;
    Navigator.pop(c, PasswordAnswer(pw.text, remember: remember));
  }

  final r = await showDialog<PasswordAnswer>(
    context: ctx,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        scrollable: true,
        icon: Icon(wrong ? Icons.lock_reset : Icons.lock_outline, color: wrong ? p.red : p.accent, size: 32),
        title: Text(s['pwTitle']),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Ltr(h.address, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12.5, color: p.muted)),
          if (wrong) ...[
            const SizedBox(height: 8),
            Text(s['pwWrong'], style: TextStyle(color: p.red, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('pw-field'),
            controller: pw,
            autofocus: true,
            obscureText: !show,
            autocorrect: false,
            enableSuggestions: false,
            textDirection: TextDirection.ltr,
            onSubmitted: (_) => submit(c),
            decoration: InputDecoration(
              labelText: s['password'],
              suffixIcon: IconButton(
                icon: Icon(show ? Icons.visibility_off : Icons.visibility, color: p.muted),
                onPressed: () => setState(() => show = !show),
              ),
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: remember,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(s['rememberPw']),
            onChanged: (v) => setState(() => remember = v ?? true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s['cancel'])),
          TextButton(
            onPressed: () => submit(c),
            child: Text(s['connect'], style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
  // pw is not disposed here: the dialog's exit animation still uses it.
  return r;
}

/// Opens a new SSH session to [h] and shows its terminal.
void openHost(BuildContext context, Host h) {
  final s = Sessions.i.open(h)..passwordPrompt = passwordPrompt;
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
    final c = Palette.hostColors[color % Palette.hostColors.length];
    final p = context.pal;
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
            decoration:
                BoxDecoration(color: p.green, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 2.5)),
          ),
        ),
    ]);
  }
}
