import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keys.dart';
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
  final group = TextEditingController();
  final tags = TextEditingController();
  final startup = TextEditingController();
  String? jumpHostId;
  List<ForwardRule> forwards = [];
  String auth = 'password';
  int color = 0;
  bool showPw = false;
  bool saving = false;

  bool get isNew => widget.host == null || widget.duplicate;

  /// Groups already used by other servers, for one-tap picking.
  List<String> _groups() {
    final g = {for (final h in Store.i.hosts) if (h.group.trim().isNotEmpty) h.group.trim()}.toList()..sort();
    return g;
  }

  /// Saved servers this one can jump through (not itself, and not one that
  /// already jumps through this one).
  List<Host> _jumpCandidates() {
    final self = isNew ? null : widget.host!.id;
    return [
      for (final h in Store.i.hosts)
        if (h.id != self && (self == null || h.jumpHostId != self)) h
    ];
  }

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
      group.text = h.group;
      tags.text = h.tags.join(', ');
      startup.text = h.startupCmd;
      jumpHostId = Store.i.hosts.any((x) => x.id == h.jumpHostId) ? h.jumpHostId : null;
      forwards = [
        for (final f in h.forwards) widget.duplicate ? (ForwardRule.fromJson(f.toJson())..id = newId()) : ForwardRule.fromJson(f.toJson())
      ];
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
      group: group.text.trim(),
      tags: parseTags(tags.text),
      startupCmd: startup.text.trim(),
      jumpHostId: jumpHostId,
      forwards: forwards,
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

  Future<void> _generateKey() async {
    final s = S.of(context);
    if (key.text.trim().isNotEmpty &&
        !await confirm(context, s['generateKey'], s['replaceKeyBody'], ok: s['replace'], danger: true)) {
      return;
    }
    final g = generateEd25519(comment: 'mterm@${user.text.trim().isEmpty ? 'host' : user.text.trim()}');
    setState(() {
      key.text = g.privatePem.trim();
      passphrase.clear();
    });
    if (mounted) await showPublicKey(context, g.publicLine, generated: true);
  }

  Future<void> _copyPublic() async {
    final line = publicKeyFromPrivate(key.text, passphrase: passphrase.text);
    if (line == null) {
      toast(context, S.of(context)['invalidKey']);
      return;
    }
    await showPublicKey(context, line);
  }

  Future<void> _editForward([ForwardRule? r]) async {
    final res = await showDialog<ForwardRule>(context: context, builder: (_) => ForwardRuleDialog(rule: r));
    if (res == null) return;
    setState(() {
      final i = forwards.indexWhere((x) => x.id == res.id);
      if (i >= 0) {
        forwards[i] = res;
      } else {
        forwards.add(res);
      }
    });
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
            Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
              TextButton.icon(
                  key: const ValueKey('generate-key'),
                  onPressed: _generateKey,
                  icon: const Icon(Icons.auto_fix_high),
                  label: Text(s['generateKey'])),
              TextButton.icon(
                  key: const ValueKey('public-key'),
                  onPressed: _copyPublic,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: Text(s['publicKey'])),
              TextButton.icon(
                  onPressed: _pasteKey, icon: const Icon(Icons.content_paste), label: Text(s['pasteKey'])),
            ]),
            TextFormField(
              controller: passphrase,
              textDirection: ltr,
              obscureText: true,
              decoration: _dec(s['keyPassphrase']),
            ),
          ],
          const SizedBox(height: 22),
          Text(s['organize'], style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('group-field'),
            controller: group,
            decoration: _dec(s['groupOptional'], hint: s['groupHint']),
          ),
          if (_groups().isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final g in _groups())
                ActionChip(label: Text(g), onPressed: () => setState(() => group.text = g)),
            ]),
          ],
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('tags-field'),
            controller: tags,
            decoration: _dec(s['tagsOptional'], hint: s['tagsHint']),
          ),
          const SizedBox(height: 22),
          Text(s['advanced'], style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('startup-field'),
            controller: startup,
            textDirection: ltr,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
            decoration: _dec(s['startupCmd'], hint: s['startupHint']),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const ValueKey('jump-field'),
            initialValue: jumpHostId,
            isExpanded: true,
            decoration: _dec(s['jumpHost']),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(s['jumpNone'])),
              for (final h in _jumpCandidates())
                DropdownMenuItem<String?>(value: h.id, child: Text(h.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => jumpHostId = v),
          ),
          const SizedBox(height: 6),
          Text(s['jumpHint'], style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(s['portForwarding'], style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton.icon(
                key: const ValueKey('add-forward'),
                onPressed: () => _editForward(),
                icon: const Icon(Icons.add),
                label: Text(s['addRule'])),
          ]),
          if (forwards.isEmpty) Text(s['noRules'], style: TextStyle(color: p.muted, fontSize: 12.5)),
          for (final f in forwards)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(f.isDynamic ? Icons.public : Icons.swap_horiz, color: p.accent),
              title: Align(alignment: AlignmentDirectional.centerStart, child: Ltr(f.summary)),
              subtitle: Text(f.autoStart ? s['autoStartOn'] : s['autoStartOff'],
                  style: TextStyle(color: p.muted, fontSize: 12)),
              onTap: () => _editForward(f),
              trailing: IconButton(
                icon: Icon(Icons.remove_circle_outline, color: p.red),
                onPressed: () => setState(() => forwards.removeWhere((x) => x.id == f.id)),
              ),
            ),
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

List<String> parseTags(String text) {
  final out = <String>[];
  for (final t in text.split(RegExp(r'[,،\n]'))) {
    final v = t.trim();
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out;
}

/// Shows a public key line with a Copy button.
Future<void> showPublicKey(BuildContext context, String line, {bool generated = false}) {
  final s = S.of(context);
  final p = context.pal;
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      icon: Icon(Icons.vpn_key, color: p.green, size: 32),
      title: Text(s['publicKey']),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(generated ? s['keyGeneratedBody'] : s['publicKeyBody'], style: TextStyle(color: p.muted, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(10)),
          child: SelectableText(line,
              key: const ValueKey('public-key-text'),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, color: p.text)),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(s['ok'])),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: line));
            Navigator.pop(c);
            toast(context, s['copied']);
          },
          child: Text(s['copy'], style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// Add / edit one port forwarding rule.
class ForwardRuleDialog extends StatefulWidget {
  const ForwardRuleDialog({super.key, this.rule});
  final ForwardRule? rule;
  @override
  State<ForwardRuleDialog> createState() => _ForwardRuleDialogState();
}

class _ForwardRuleDialogState extends State<ForwardRuleDialog> {
  final form = GlobalKey<FormState>();
  late String type = widget.rule?.type ?? 'local';
  late final local = TextEditingController(text: widget.rule == null ? '' : '${widget.rule!.localPort}');
  late final rhost = TextEditingController(text: widget.rule?.remoteHost ?? '127.0.0.1');
  late final rport = TextEditingController(
      text: widget.rule == null || widget.rule!.remotePort == 0 ? '' : '${widget.rule!.remotePort}');
  late bool auto = widget.rule?.autoStart ?? true;

  String? _port(String? v, S s) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < 1 || n > 65535 ? s['invalid'] : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    const ltr = TextDirection.ltr;
    return AlertDialog(
      scrollable: true,
      title: Text(s['portForwarding']),
      content: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'local', label: Text(s['fwdLocal'])),
              ButtonSegment(value: 'dynamic', label: Text(s['fwdDynamic'])),
            ],
            selected: {type},
            onSelectionChanged: (v) => setState(() => type = v.first),
          ),
          const SizedBox(height: 8),
          Text(type == 'local' ? s['fwdLocalHint'] : s['fwdDynamicHint'],
              style: TextStyle(color: context.pal.muted, fontSize: 12)),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('fwd-local'),
            controller: local,
            textDirection: ltr,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: s['localPort']),
            validator: (v) => _port(v, s),
          ),
          if (type == 'local') ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('fwd-rhost'),
              controller: rhost,
              textDirection: ltr,
              autocorrect: false,
              decoration: InputDecoration(labelText: s['remoteHost']),
              validator: (v) => (v ?? '').trim().isEmpty ? s['invalid'] : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('fwd-rport'),
              controller: rport,
              textDirection: ltr,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: s['remotePort']),
              validator: (v) => _port(v, s),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s['autoStart']),
            value: auto,
            onChanged: (v) => setState(() => auto = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['cancel'])),
        TextButton(
          key: const ValueKey('fwd-save'),
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(
                context,
                ForwardRule(
                  id: widget.rule?.id,
                  type: type,
                  localPort: int.parse(local.text.trim()),
                  remoteHost: type == 'local' ? rhost.text.trim() : '',
                  remotePort: type == 'local' ? int.parse(rport.text.trim()) : 0,
                  autoStart: auto,
                ));
          },
          child: Text(s['save']),
        ),
      ],
    );
  }
}
