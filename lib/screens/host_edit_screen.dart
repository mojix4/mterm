import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../models.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';

class HostEditScreen extends StatefulWidget {
  const HostEditScreen({super.key, this.host, this.duplicate = false});
  final Host? host;
  final bool duplicate;
  @override
  State<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends State<HostEditScreen> {
  final form = GlobalKey<FormState>();
  final label = TextEditingController();
  final host = TextEditingController();
  final port = TextEditingController(text: '22');
  final user = TextEditingController(text: 'root');
  final password = TextEditingController();
  final key = TextEditingController();
  final passphrase = TextEditingController();
  String auth = 'password';
  int color = 0;
  bool showPw = false;
  bool saving = false;

  bool get isNew => widget.host == null || widget.duplicate;

  @override
  void initState() {
    super.initState();
    final h = widget.host;
    if (h != null) {
      label.text = widget.duplicate ? S.current.f('copyOf', {'name': h.label}) : h.label;
      host.text = h.host;
      port.text = '${h.port}';
      user.text = h.user;
      auth = h.auth;
      color = h.color;
      Store.i.secret(h.id).then((s) {
        if (!mounted) return;
        setState(() {
          password.text = s.password;
          key.text = s.privateKey;
          passphrase.text = s.passphrase;
        });
      });
    } else {
      color = Store.i.hosts.length % Palette.hostColors.length;
    }
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    final h = Host(
      id: isNew ? newId() : widget.host!.id,
      label: label.text.trim(),
      host: host.text.trim(),
      port: int.parse(port.text.trim()),
      user: user.text.trim(),
      auth: auth,
      color: color,
      lastUsed: isNew ? null : widget.host!.lastUsed,
    );
    await Store.i.upsertHost(
        h, HostSecret(password: password.text, privateKey: key.text.trim(), passphrase: passphrase.text));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pasteKey() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (!t.contains('PRIVATE KEY')) {
      if (mounted) toast(context, S.of(context)['noKeyInClipboard']);
      return;
    }
    setState(() => key.text = t);
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) =>
      InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix);

  @override
  Widget build(BuildContext context) {
    const ltr = TextDirection.ltr;
    final s = S.of(context);
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? s['newHost'] : s['editHost']),
        actions: [
          TextButton(
            onPressed: saving ? null : _save,
            child: Text(s['save'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          TextFormField(controller: label, decoration: _dec(s['labelOptional'], hint: s['labelHint'])),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: host,
                textDirection: ltr,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: _dec(s['address'], hint: s['addressHint']),
                validator: (v) => (v ?? '').trim().isEmpty ? s['enterAddress'] : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: port,
                textDirection: ltr,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _dec(s['port']),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 1 || n > 65535 ? s['invalid'] : null;
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: user,
            textDirection: ltr,
            autocorrect: false,
            decoration: _dec(s['username']),
            validator: (v) => (v ?? '').trim().isEmpty ? s['enterUsername'] : null,
          ),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'password', label: Text(s['password']), icon: const Icon(Icons.password)),
              ButtonSegment(value: 'key', label: Text(s['sshKey']), icon: const Icon(Icons.key)),
            ],
            selected: {auth},
            onSelectionChanged: (s) => setState(() => auth = s.first),
          ),
          const SizedBox(height: 14),
          if (auth == 'password')
            TextFormField(
              controller: password,
              textDirection: ltr,
              obscureText: !showPw,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _dec(s['password'],
                  suffix: IconButton(
                    icon: Icon(showPw ? Icons.visibility_off : Icons.visibility, color: p.muted),
                    onPressed: () => setState(() => showPw = !showPw),
                  )),
            )
          else ...[
            TextFormField(
              controller: key,
              textDirection: ltr,
              maxLines: 6,
              minLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5),
              decoration: _dec(s['privateKey'], hint: '-----BEGIN OPENSSH PRIVATE KEY-----'),
              validator: (v) =>
                  auth == 'key' && !(v ?? '').contains('PRIVATE KEY') ? s['invalidKey'] : null,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                  onPressed: _pasteKey, icon: const Icon(Icons.content_paste), label: Text(s['pasteKey'])),
            ),
            TextFormField(
              controller: passphrase,
              textDirection: ltr,
              obscureText: true,
              decoration: _dec(s['keyPassphrase']),
            ),
          ],
          const SizedBox(height: 22),
          Text(s['color'], style: TextStyle(color: p.muted, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (var i = 0; i < Palette.hostColors.length; i++)
              GestureDetector(
                onTap: () => setState(() => color = i),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Palette.hostColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: color == i ? p.text : Colors.transparent, width: 3),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 28),
          FilledButton(onPressed: saving ? null : _save, child: Text(s['save'])),
          const SizedBox(height: 12),
          Text(s['storageNote'], textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}
