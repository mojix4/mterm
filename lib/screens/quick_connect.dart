import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../session.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';
import 'terminal_screen.dart';

/// What the quick connect form produced: an unsaved host and its password.
class QuickTarget {
  const QuickTarget(this.host, this.password);
  final Host host;
  final String password;
}

/// Compact "connect without saving" form. Pops with a [QuickTarget] or null.
class QuickConnectDialog extends StatefulWidget {
  const QuickConnectDialog({super.key});
  @override
  State<QuickConnectDialog> createState() => _QuickConnectDialogState();
}

class _QuickConnectDialogState extends State<QuickConnectDialog> {
  final form = GlobalKey<FormState>();
  final host = TextEditingController();
  final port = TextEditingController(text: '22');
  final user = TextEditingController(text: 'root');
  final password = TextEditingController();
  bool showPw = false;

  void _submit() {
    if (!form.currentState!.validate()) return;
    final h = Host(
      id: newId(),
      label: '',
      host: host.text.trim(),
      port: int.parse(port.text.trim()),
      user: user.text.trim(),
      color: Store.i.hosts.length % Palette.hostColors.length,
    );
    Navigator.of(context).pop(QuickTarget(h, password.text));
  }

  @override
  Widget build(BuildContext context) {
    const ltr = TextDirection.ltr;
    final s = S.of(context);
    final p = context.pal;
    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.flash_on_rounded, color: p.accent, size: 32),
      title: Text(s['quickConnect']),
      content: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s['quickConnectHint'], style: TextStyle(color: p.muted, fontSize: 13)),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('qc-host'),
            controller: host,
            autofocus: true,
            textDirection: ltr,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: s['address'], hintText: s['addressHint']),
            validator: (v) => (v ?? '').trim().isEmpty ? s['enterAddress'] : null,
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                key: const ValueKey('qc-user'),
                controller: user,
                textDirection: ltr,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: s['username']),
                validator: (v) => (v ?? '').trim().isEmpty ? s['enterUsername'] : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                key: const ValueKey('qc-port'),
                controller: port,
                textDirection: ltr,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: s['port']),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 1 || n > 65535 ? s['invalid'] : null;
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('qc-password'),
            controller: password,
            textDirection: ltr,
            obscureText: !showPw,
            autocorrect: false,
            enableSuggestions: false,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: s['password'],
              suffixIcon: IconButton(
                key: const ValueKey('qc-show-pw'),
                icon: Icon(showPw ? Icons.visibility_off : Icons.visibility, color: p.muted),
                onPressed: () => setState(() => showPw = !showPw),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s['cancel'])),
        TextButton(
          key: const ValueKey('qc-connect'),
          onPressed: _submit,
          child: Text(s['connect'], style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Opens the quick connect form and, when filled in, connects without saving
/// anything. Returns the new session (null when cancelled).
Future<TermSession?> quickConnect(BuildContext context) async {
  final t = await showDialog<QuickTarget>(context: context, builder: (_) => const QuickConnectDialog());
  if (t == null || !context.mounted) return null;
  final s = Sessions.i.open(t.host, transient: true, password: t.password)..passwordPrompt = passwordPrompt;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TerminalScreen(session: s)));
  s.connect(hostKeyPrompt);
  return s;
}

/// Saves a Quick connect session's server and confirms it.
Future<void> saveQuickHost(TermSession s) async {
  await s.saveHost();
  final ctx = navKey.currentContext;
  if (ctx != null && ctx.mounted) toast(ctx, S.of(ctx)['serverSaved']);
}

/// Non-blocking "Save this server?" prompt (Save / Not now), shown once after
/// a Quick connect login.
void offerSaveHost(BuildContext context, TermSession s) {
  if (!s.transient || s.saveOffered) return;
  s.saveOffered = true;
  final l = S.of(context);
  final p = context.pal;
  final m = ScaffoldMessenger.of(context);
  final btn = TextStyle(color: p.accent, fontWeight: FontWeight.w700);
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: const ValueKey('save-server-snack'),
      duration: const Duration(seconds: 12),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l['saveServerQ'], style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(l['saveServerBody'], style: const TextStyle(fontSize: 12.5)),
        Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
          TextButton(
            key: const ValueKey('save-server-later'),
            onPressed: m.hideCurrentSnackBar,
            child: Text(l['notNow'], style: TextStyle(color: Theme.of(context).snackBarTheme.contentTextStyle?.color)),
          ),
          TextButton(
            key: const ValueKey('save-server-yes'),
            onPressed: () {
              m.hideCurrentSnackBar();
              saveQuickHost(s);
            },
            child: Text(l['save'], style: btn),
          ),
        ]),
      ]),
    ));
}
