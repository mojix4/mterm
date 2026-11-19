import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../session.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';

const Map<String, TerminalKey> _specialKeys = {
  'esc': TerminalKey.escape,
  'tab': TerminalKey.tab,
  '←': TerminalKey.arrowLeft,
  '↑': TerminalKey.arrowUp,
  '↓': TerminalKey.arrowDown,
  '→': TerminalKey.arrowRight,
  'home': TerminalKey.home,
  'end': TerminalKey.end,
  'pgup': TerminalKey.pageUp,
  'pgdn': TerminalKey.pageDown,
  'del': TerminalKey.delete,
};
const Map<String, String> _ctrlKeys = {'^C': '\x03', '^D': '\x04', '^Z': '\x1a', '^L': '\x0c', '^R': '\x12'};

/// Every key that can be placed on the key bar.
const allBarKeys = [
  'esc', 'tab', 'ctrl', 'alt', '←', '↑', '↓', '→', 'home', 'end', 'pgup', 'pgdn', 'del',
  '|', '/', '-', '~', ':', ';', '\$', '&', '*', '>', '<', '{', '}', '[', ']', '"', "'", '`', '\\', '=',
  '^C', '^D', '^Z', '^L', '^R', 'paste',
];

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.session});
  final TermSession session;
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  TermSession get s => widget.session;
  final controller = TerminalController();
  final focus = FocusNode();
  late double fontSize = Store.i.settings.fontSize;

  // pinch to zoom
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _pinchStartFont = 13;

  @override
  void initState() {
    super.initState();
    if (Store.i.settings.wakelock) WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  void _setFont(double v, {bool save = true}) {
    final f = v.clamp(8.0, 30.0);
    setState(() => fontSize = f);
    if (save) {
      Store.i.settings.fontSize = f;
      Store.i.saveSettings();
    }
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStartDist = _dist();
      _pinchStartFont = fontSize;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final d0 = _pinchStartDist;
    if (_pointers.length == 2 && d0 != null && d0 > 0) {
      final f = (_pinchStartFont * _dist() / d0).roundToDouble();
      if (f != fontSize) _setFont(f, save: false);
    }
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinchStartDist != null && _pointers.length < 2) {
      _pinchStartDist = null;
      _setFont(fontSize);
    }
  }

  double _dist() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  Future<void> _barKey(String k) async {
    HapticFeedback.selectionClick();
    if (k == 'ctrl') return s.toggleCtrl();
    if (k == 'alt') return s.toggleAlt();
    if (k == 'paste') return _paste();
    final sp = _specialKeys[k];
    if (sp != null) {
      s.key(sp);
    } else if (_ctrlKeys.containsKey(k)) {
      s.text(_ctrlKeys[k]!);
    } else {
      s.text(k);
    }
    focus.requestFocus();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t != null && t.isNotEmpty) s.terminal.paste(t);
  }

  void _copy() {
    final sel = controller.selection;
    if (sel == null) {
      toast(context, 'برای انتخاب متن، روی آن نگه دارید');
      return;
    }
    Clipboard.setData(ClipboardData(text: s.terminal.buffer.getText(sel)));
    controller.clearSelection();
    toast(context, 'کپی شد');
  }

  void _snippets() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (c, sc) {
          final items = Store.i.snippets;
          return ListView(controller: sc, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text('دستورها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('دستوری ذخیره نکرده‌اید', textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              ),
            for (final sn in items)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.bolt, color: C.amber),
                title: Text(sn.name),
                subtitle: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Ltr(sn.cmd,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: C.muted)),
                ),
                trailing: IconButton(
                  tooltip: 'فقط بنویس',
                  icon: const Icon(Icons.edit_note, color: C.muted),
                  onPressed: () {
                    Navigator.pop(c);
                    s.run(sn.cmd, enter: false);
                    focus.requestFocus();
                  },
                ),
                onTap: () {
                  Navigator.pop(c);
                  s.run(sn.cmd);
                  focus.requestFocus();
                },
              ),
            if (s.typed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text('تاریخچه همین نشست', style: TextStyle(color: C.muted, fontSize: 13)),
              ),
              for (final h in s.typed.take(30))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, color: C.muted, size: 20),
                  title: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Ltr(h, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13)),
                  ),
                  onTap: () {
                    Navigator.pop(c);
                    s.run(h);
                  },
                ),
            ],
          ]);
        },
      ),
    );
  }

  List<String> _suggestions() {
    final q = s.line;
    if (q == null || q.isEmpty) return const [];
    final pool = [...s.typed, ...Store.i.snippets.map((e) => e.cmd)];
    final out = <String>[];
    for (final c in pool) {
      if (c != q && c.startsWith(q) && !out.contains(c)) out.add(c);
      if (out.length >= 8) return out;
    }
    final ql = q.toLowerCase();
    for (final c in pool) {
      if (c != q && c.toLowerCase().contains(ql) && !out.contains(c)) out.add(c);
      if (out.length >= 8) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s, Store.i]),
      builder: (context, _) {
        final st = Store.i.settings;
        final theme = terminalThemes[st.theme] ?? terminalThemes['Termius']!;
        final light = theme.background.computeLuminance() > 0.5;
        final barBg = light ? const Color(0xFFF0F2F6) : Color.lerp(theme.background, Colors.white, 0.06)!;
        final keyBg = light ? Colors.white : Color.lerp(theme.background, Colors.white, 0.13)!;
        final fg = light ? const Color(0xFF24292F) : const Color(0xFFE6EBF7);
        final sugg = _suggestions();
        return Scaffold(
          backgroundColor: theme.background,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: barBg,
            foregroundColor: fg,
            toolbarHeight: 52,
            titleSpacing: 0,
            title: Row(children: [
              _dot(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.host.label.isEmpty ? s.host.host : s.host.label,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg)),
                  Ltr(s.title?.isNotEmpty == true ? s.title! : s.host.address,
                      style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.6))),
                ]),
              ),
            ]),
            actions: [
              IconButton(tooltip: 'دستورها', icon: const Icon(Icons.bolt), onPressed: _snippets),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'copy':
                      _copy();
                    case 'paste':
                      _paste();
                    case 'big':
                      _setFont(fontSize + 1);
                    case 'small':
                      _setFont(fontSize - 1);
                    case 'reconnect':
                      s.reconnect(hostKeyPrompt);
                    case 'close':
                      Sessions.i.close(s);
                      Navigator.of(context).pop();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copy', child: Text('کپی متن انتخاب‌شده')),
                  PopupMenuItem(value: 'paste', child: Text('چسباندن')),
                  PopupMenuItem(value: 'big', child: Text('بزرگ‌تر کردن فونت')),
                  PopupMenuItem(value: 'small', child: Text('کوچک‌تر کردن فونت')),
                  PopupMenuItem(value: 'reconnect', child: Text('اتصال دوباره')),
                  PopupMenuItem(value: 'close', child: Text('بستن نشست', style: TextStyle(color: C.red))),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Listener(
                    onPointerDown: _onDown,
                    onPointerMove: _onMove,
                    onPointerUp: _onUp,
                    onPointerCancel: _onUp,
                    child: Stack(children: [
                      TerminalView(
                        s.terminal,
                        controller: controller,
                        focusNode: focus,
                        autofocus: true,
                        theme: theme,
                        deleteDetection: true,
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                        cursorType: switch (st.cursor) {
                          'underline' => TerminalCursorType.underline,
                          'bar' => TerminalCursorType.verticalBar,
                          _ => TerminalCursorType.block,
                        },
                        textStyle: TerminalStyle(
                          fontSize: fontSize,
                          fontFamily: 'JetBrainsMono',
                          fontFamilyFallback: const ['monospace', 'Vazirmatn', 'Noto Color Emoji'],
                        ),
                      ),
                      if (s.status == SessStatus.failed || s.status == SessStatus.closed)
                        Positioned(left: 12, right: 12, bottom: 12, child: _reconnectBanner()),
                    ]),
                  ),
                ),
              ),
              if (sugg.isNotEmpty)
                Container(
                  color: barBg,
                  height: 40,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      children: [
                        for (final c in sugg)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Material(
                              color: keyBg,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  s.run(c, enter: false);
                                  focus.requestFocus();
                                },
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    child: Text(c,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, color: fg)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Container(
                color: barBg,
                height: 50,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                    children: [
                      for (final k in st.keys.where(allBarKeys.contains))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _KeyCap(
                            label: k == 'paste' ? null : k,
                            icon: k == 'paste' ? Icons.content_paste : null,
                            active: (k == 'ctrl' && s.ctrl) || (k == 'alt' && s.alt),
                            bg: keyBg,
                            fg: fg,
                            onTap: () => _barKey(k),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _dot() {
    final c = switch (s.status) {
      SessStatus.connected => C.green,
      SessStatus.connecting => C.amber,
      _ => C.red,
    };
    return Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  Widget _reconnectBanner() => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(s.status == SessStatus.failed ? Icons.error_outline : Icons.link_off, color: C.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.status == SessStatus.failed ? (s.error ?? 'اتصال ناموفق') : 'اتصال قطع شد',
                  style: const TextStyle(color: C.text, fontSize: 13.5)),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => s.reconnect(hostKeyPrompt),
              child: const Text('اتصال دوباره'),
            ),
          ]),
        ),
      );
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({this.label, this.icon, required this.active, required this.bg, required this.fg, required this.onTap});
  final String? label;
  final IconData? icon;
  final bool active;
  final Color bg, fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? C.accent : bg,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        // Keep the soft keyboard open: do not take focus from the terminal.
        canRequestFocus: false,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minWidth: math.max(42, (label?.length ?? 1) * 9.0 + 20)),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: icon != null
              ? Icon(icon, size: 18, color: active ? Colors.white : fg)
              : Text(label!,
                  style: TextStyle(
                      fontFamily: 'JetBrainsMono', fontSize: 14, color: active ? Colors.white : fg)),
        ),
      ),
    );
  }
}
