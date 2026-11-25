import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../l10n.dart';
import '../session.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';
import 'quick_connect.dart';
import '../suggest.dart';

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
  'esc',
  'tab',
  'ctrl',
  'alt',
  '←',
  '↑',
  '↓',
  '→',
  'home',
  'end',
  'pgup',
  'pgdn',
  'del',
  '|',
  '/',
  '-',
  '~',
  ':',
  ';',
  '\$',
  '&',
  '*',
  '>',
  '<',
  '{',
  '}',
  '[',
  ']',
  '"',
  "'",
  '`',
  '\\',
  '=',
  '^C',
  '^D',
  '^Z',
  '^L',
  '^R',
  'paste',
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
    s.addListener(_offerSave);
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerSave());
  }

  /// Quick connect: once logged in, ask (without blocking) whether to keep the server.
  void _offerSave() {
    if (!mounted || !s.transient || s.saveOffered || s.status != SessStatus.connected) return;
    offerSaveHost(context, s);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    s.removeListener(_offerSave);
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

  // long press -> Copy / Paste menu (mobile)
  Timer? _holdTimer;
  Offset? _holdAt;
  bool _held = false;

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    _holdTimer?.cancel();
    _held = false;
    if (_pointers.length == 1 && e.kind == PointerDeviceKind.touch) {
      _holdAt = e.position;
      _holdTimer = Timer(const Duration(milliseconds: 450), () => _held = true);
    } else {
      _holdAt = null;
    }
    if (_pointers.length == 2) {
      _pinchStartDist = _dist();
      _pinchStartFont = fontSize;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final h = _holdAt;
    if (!_held && h != null && (e.position - h).distance > 12) {
      _holdTimer?.cancel();
      _holdAt = null;
    }
    final d0 = _pinchStartDist;
    if (_pointers.length == 2 && d0 != null && d0 > 0) {
      final f = (_pinchStartFont * _dist() / d0).roundToDouble();
      if (f != fontSize) _setFont(f, save: false);
    }
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    _holdTimer?.cancel();
    if (_held && _holdAt != null && e is PointerUpEvent && _pointers.isEmpty) {
      _showEditMenu(e.position);
    }
    _held = false;
    _holdAt = null;
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

  Future<void> _showEditMenu(Offset at) async {
    final l = S.of(context);
    final hasSel = controller.selection != null;
    final size = MediaQuery.of(context).size;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy - 56, size.width - at.dx, size.height - at.dy),
      items: [
        if (hasSel) PopupMenuItem(value: 'copy', child: Text(l['copySelection'])),
        PopupMenuItem(value: 'paste', child: Text(l['paste'])),
      ],
    );
    if (v == 'copy') _copy();
    if (v == 'paste') {
      controller.clearSelection();
      await _paste();
      focus.requestFocus();
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t != null && t.isNotEmpty) s.terminal.paste(t);
  }

  void _copy() {
    final sel = controller.selection;
    final l = S.of(context);
    if (sel == null) {
      toast(context, l['selectHint']);
      return;
    }
    Clipboard.setData(ClipboardData(text: s.terminal.buffer.getText(sel)));
    controller.clearSelection();
    toast(context, l['copied']);
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
          final l = S.of(c);
          final p = c.pal;
          return ListView(controller: sc, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(l['navSnippets'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l['noSnippetsSaved'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
              ),
            for (final sn in items)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(Icons.bolt, color: p.amber),
                title: Text(sn.name),
                subtitle: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Ltr(sn.cmd, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: p.muted)),
                ),
                trailing: IconButton(
                  tooltip: l['typeOnly'],
                  icon: Icon(Icons.edit_note, color: p.muted),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text(l['sessionHistory'], style: TextStyle(color: p.muted, fontSize: 13)),
              ),
              for (final h in s.typed.take(30))
                ListTile(
                  dense: true,
                  leading: Icon(Icons.history, color: p.muted, size: 20),
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

  List<String> _suggestions() => s.terminal.isUsingAltBuffer
      ? const []
      : suggestCommands(s.line, [...s.typed, ...Store.i.history], Store.i.snippets.map((e) => e.cmd));

  // ---- Termius-style prediction popup under the cursor
  final _tvKey = GlobalKey<TerminalViewState>();
  final _stackKey = GlobalKey();
  Rect? _cursor;

  void _trackCursor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tv = _tvKey.currentState;
      final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (tv == null || box == null || !box.hasSize) return;
      Rect r;
      try {
        final g = tv.globalCursorRect;
        r = box.globalToLocal(g.topLeft) & g.size;
      } catch (_) {
        return;
      }
      if (r != _cursor) setState(() => _cursor = r);
    });
  }

  Widget _predictions(List<String> items, BoxConstraints c, bool light) {
    final r = _cursor;
    if (r == null) return const SizedBox.shrink();
    const itemH = 40.0;
    final h = items.length * itemH;
    const w = 240.0;
    final maxW = math.min(w, c.maxWidth - 8);
    final double left = r.left.clamp(4.0, math.max(4.0, c.maxWidth - maxW - 4)).toDouble();
    final below = r.bottom + 4;
    final top = below + h <= c.maxHeight ? below : math.max(0.0, r.top - h - 4);
    final q = s.line ?? '';
    final bg = light ? const Color(0xFFFFFFFF) : const Color(0xFFE6E9EF);
    const fg = Color(0xFF1B1F27);
    return Positioned(
      left: left,
      top: top,
      width: maxW,
      child: Material(
        key: const ValueKey('predictions'),
        color: bg,
        elevation: 6,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0x33000000))),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0x22000000)),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                s.run(items[i], enter: false);
                focus.requestFocus();
              },
              child: SizedBox(
                height: itemH - (i > 0 ? 1 : 0),
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      items[i].startsWith(q)
                          ? TextSpan(children: [
                              TextSpan(text: q, style: const TextStyle(fontWeight: FontWeight.w800)),
                              TextSpan(text: items[i].substring(q.length)),
                            ])
                          : TextSpan(text: items[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, color: fg),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s, Store.i]),
      builder: (context, _) {
        final st = Store.i.settings;
        final l = S.of(context);
        final theme = terminalThemeFor(st.theme, Theme.of(context).brightness);
        final light = theme.background.computeLuminance() > 0.5;
        final barBg = light ? const Color(0xFFF0F2F6) : Color.lerp(theme.background, Colors.white, 0.06)!;
        final keyBg = light ? Colors.white : Color.lerp(theme.background, Colors.white, 0.13)!;
        final fg = light ? const Color(0xFF24292F) : const Color(0xFFE6EBF7);
        final sugg = _suggestions();
        if (sugg.isNotEmpty) _trackCursor();
        return Scaffold(
          backgroundColor: theme.background,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: barBg,
            foregroundColor: fg,
            systemOverlayStyle: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
                .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: barBg),
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
              IconButton(tooltip: l['navSnippets'], icon: const Icon(Icons.bolt), onPressed: _snippets),
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
                      _reconnect();
                    case 'saveServer':
                      saveQuickHost(s);
                    case 'close':
                      Sessions.i.close(s);
                      Navigator.of(context).pop();
                  }
                },
                itemBuilder: (_) => [
                  if (s.transient) PopupMenuItem(value: 'saveServer', child: Text(l['saveServer'])),
                  PopupMenuItem(value: 'copy', child: Text(l['copySelection'])),
                  PopupMenuItem(value: 'paste', child: Text(l['paste'])),
                  PopupMenuItem(value: 'big', child: Text(l['fontBigger'])),
                  PopupMenuItem(value: 'small', child: Text(l['fontSmaller'])),
                  PopupMenuItem(value: 'reconnect', child: Text(l['reconnect'])),
                  PopupMenuItem(
                      value: 'close', child: Text(l['closeSession'], style: TextStyle(color: context.pal.red))),
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
                    child: LayoutBuilder(builder: (context, box) => Stack(key: _stackKey, children: [
                      TerminalView(
                        s.terminal,
                        key: _tvKey,
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
                      if (sugg.isNotEmpty && s.status == SessStatus.connected) _predictions(sugg, box, light),
                      if (s.status == SessStatus.failed || s.status == SessStatus.closed)
                        Positioned(left: 12, right: 12, bottom: 12, child: _reconnectBanner()),
                    ])),
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

  void _reconnect() {
    s.passwordPrompt ??= passwordPrompt;
    s.reconnect(hostKeyPrompt);
  }

  Widget _dot() {
    final p = context.pal;
    final c = switch (s.status) {
      SessStatus.connected => p.green,
      SessStatus.connecting => p.amber,
      _ => p.red,
    };
    return Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  Widget _reconnectBanner() {
    // The banner sits inside the terminal's forced-LTR area; give it the app's direction back.
    final l = S.of(context);
    final p = context.pal;
    return Directionality(
      textDirection: l.direction,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        // Message and button share a line; a long label (e.g. Russian) wraps the
        // button onto its own line instead of squeezing the message.
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 150, maxWidth: 520),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s.status == SessStatus.failed ? Icons.error_outline : Icons.link_off, color: p.red),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(s.status == SessStatus.failed ? (s.errorIn(l) ?? l['connFailed']) : l['connClosed'],
                      style: TextStyle(color: p.text, fontSize: 13.5)),
                ),
              ]),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _reconnect,
              child: Text(l['reconnect']),
            ),
          ],
        ),
      ),
    );
  }
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
      color: active ? context.pal.accent : bg,
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
                  style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14, color: active ? Colors.white : fg)),
        ),
      ),
    );
  }
}
