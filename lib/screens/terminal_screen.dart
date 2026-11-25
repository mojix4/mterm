import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../keys.dart';
import '../l10n.dart';
import '../models.dart';
import '../session.dart';
import '../term_search.dart';
import '../store.dart';
import '../themes.dart';
import 'common.dart';
import 'files_screen.dart';
import 'host_edit_screen.dart' show ForwardRuleDialog;
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

/// Windows / Linux / macOS (hardware keyboard, wide windows).
bool get isDesktop => const {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}
    .contains(defaultTargetPlatform);

/// Width from which the terminal can show two sessions side by side.
const splitMinWidth = 900.0;

/// Terminal keyboard shortcuts. Desktop adds Ctrl+Shift+V paste to xterm's
/// Ctrl+V paste and Ctrl+Shift+C copy; mobile keeps xterm's defaults.
Map<ShortcutActivator, Intent> terminalShortcuts() => {
      ...defaultTerminalShortcuts,
      if (isDesktop)
        const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
            const PasteTextIntent(SelectionChangedCause.keyboard),
    };

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
  final scroll = ScrollController();
  late double fontSize = Store.i.settings.fontSize;

  // search in output
  bool searching = false;
  final searchText = TextEditingController();
  final searchFocus = FocusNode();
  List<TermMatch> matches = [];
  int matchIndex = -1;
  final List<TerminalHighlight> _marks = [];

  // split view (desktop / wide screens)
  bool split = false;
  TermSession? other;

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
    _clearMarks();
    controller.dispose();
    focus.dispose();
    scroll.dispose();
    searchText.dispose();
    searchFocus.dispose();
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
              if (MediaQuery.sizeOf(context).width >= splitMinWidth)
                IconButton(
                  key: const ValueKey('split-toggle'),
                  tooltip: l['splitView'],
                  isSelected: split,
                  icon: const Icon(Icons.vertical_split_outlined),
                  selectedIcon: const Icon(Icons.vertical_split),
                  onPressed: _toggleSplit,
                ),
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
                    case 'search':
                      _openSearch();
                    case 'files':
                      openFiles(context, s.host, session: s);
                    case 'forwards':
                      _forwardsSheet();
                    case 'installKey':
                      _installKey();
                    case 'close':
                      Sessions.i.close(s);
                      Navigator.of(context).pop();
                  }
                },
                itemBuilder: (_) => [
                  if (s.transient) PopupMenuItem(value: 'saveServer', child: Text(l['saveServer'])),
                  PopupMenuItem(value: 'search', child: Text(l['searchOutput'])),
                  PopupMenuItem(value: 'files', child: Text(l['navFiles'])),
                  if (!s.transient) PopupMenuItem(value: 'forwards', child: Text(l['portForwarding'])),
                  if (!s.transient && s.status == SessStatus.connected)
                    PopupMenuItem(value: 'installKey', child: Text(l['installKey'])),
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
              if (searching) _searchBar(barBg, fg),
              Expanded(
                child: _withSplit(Directionality(
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
                        scrollController: scroll,
                        shortcuts: terminalShortcuts(),
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
                ), theme, light),
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

  // ---- search in output
  void _openSearch() {
    setState(() => searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => searchFocus.requestFocus());
    if (searchText.text.isNotEmpty) _runSearch(searchText.text);
  }

  void _closeSearch() {
    _clearMarks();
    setState(() {
      searching = false;
      matches = [];
      matchIndex = -1;
    });
    focus.requestFocus();
  }

  void _clearMarks() {
    for (final m in _marks) {
      m.dispose();
    }
    _marks.clear();
  }

  void _runSearch(String q) {
    final found = findInBuffer(s.terminal.buffer, q);
    setState(() {
      matches = found;
      // start from the newest match (bottom), like most terminals
      matchIndex = found.isEmpty ? -1 : found.length - 1;
    });
    _showMatch();
  }

  void _step(int d) {
    if (matches.isEmpty) return;
    setState(() => matchIndex = (matchIndex + d) % matches.length);
    _showMatch();
  }

  void _showMatch() {
    _clearMarks();
    if (matches.isEmpty) return;
    final b = s.terminal.buffer;
    final cur = matches[matchIndex];
    // highlight what is near the current match (the whole list could be huge)
    for (final m in matches) {
      if ((m.y - cur.y).abs() > 200) continue;
      if (m.y >= b.lines.length) continue;
      final current = m == cur;
      _marks.add(controller.highlight(
        p1: b.createAnchor(m.x, m.y),
        p2: b.createAnchor(m.x + m.length, m.y),
        color: current ? const Color(0xCCFF9800) : const Color(0x66FFEB3B),
      ));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(cur.y));
  }

  void _scrollTo(int y) {
    if (!scroll.hasClients) return;
    final tv = _tvKey.currentState;
    if (tv == null) return;
    final lh = tv.renderTerminal.lineHeight;
    final pos = scroll.position;
    final target = (y * lh - pos.viewportDimension / 2 + lh).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    scroll.jumpTo(target.toDouble());
  }

  Widget _searchBar(Color bg, Color fg) {
    final l = S.of(context);
    final count = matches.isEmpty ? '0/0' : '${matchIndex + 1}/${matches.length}';
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('term-search'),
            controller: searchText,
            focusNode: searchFocus,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            style: TextStyle(color: fg, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: l['searchOutputHint'],
              prefixIcon: Icon(Icons.search, color: fg.withValues(alpha: 0.6), size: 20),
            ),
            onChanged: _runSearch,
            onSubmitted: (_) {
              _step(-1);
              searchFocus.requestFocus();
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(count, key: const ValueKey('term-search-count'), style: TextStyle(color: fg, fontSize: 12.5)),
        IconButton(
            key: const ValueKey('term-search-prev'),
            tooltip: l['previous'],
            color: fg,
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: matches.isEmpty ? null : () => _step(-1)),
        IconButton(
            key: const ValueKey('term-search-next'),
            tooltip: l['next'],
            color: fg,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: matches.isEmpty ? null : () => _step(1)),
        IconButton(tooltip: l['close'], color: fg, icon: const Icon(Icons.close), onPressed: _closeSearch),
      ]),
    );
  }

  // ---- split view
  Widget _withSplit(Widget main, TerminalTheme theme, bool light) {
    final o = other;
    if (!split || o == null || !Sessions.i.list.contains(o) || MediaQuery.sizeOf(context).width < splitMinWidth) {
      return main;
    }
    return Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
      Expanded(child: main),
      Container(width: 2, color: light ? const Color(0x22000000) : const Color(0x33FFFFFF)),
      Expanded(
        child: SplitPane(
          key: ValueKey(o),
          session: o,
          theme: theme,
          fontSize: fontSize,
          onClose: () => setState(() => split = false),
        ),
      ),
    ]));
  }

  Future<void> _toggleSplit() async {
    if (split) {
      setState(() => split = false);
      return;
    }
    final l = S.of(context);
    final p = context.pal;
    final open = Sessions.i.list.where((x) => x != s).toList();
    final pick = await showDialog<Object>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(l['splitPick']),
        children: [
          for (final x in open)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, x),
              child: Row(children: [
                Icon(Icons.terminal, color: x.status == SessStatus.connected ? p.green : p.muted, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(x.host.name)),
              ]),
            ),
          if (open.isNotEmpty) const Divider(),
          for (final h in Store.i.hosts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, h),
              child: Row(children: [
                Icon(Icons.add, color: p.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(h.name)),
              ]),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    TermSession o;
    if (pick is TermSession) {
      o = pick;
    } else {
      o = Sessions.i.open(pick as Host)..passwordPrompt = passwordPrompt;
      o.connect(hostKeyPrompt);
    }
    setState(() {
      other = o;
      split = true;
    });
  }

  // ---- port forwarding
  void _forwardsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => ListenableBuilder(
        listenable: Listenable.merge([s, s.forwards, Store.i]),
        builder: (c, _) {
          final l = S.of(c);
          final p = c.pal;
          final live = s.status == SessStatus.connected;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Text(l['portForwarding'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Text(l['fwdSheetHint'], style: TextStyle(color: p.muted, fontSize: 12.5)),
                ),
                if (s.host.forwards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l['noRules'], textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                  ),
                for (final r in s.host.forwards)
                  SwitchListTile(
                    key: ValueKey('fwd-${r.id}'),
                    secondary: Icon(r.isDynamic ? Icons.public : Icons.swap_horiz, color: p.accent),
                    title: Align(alignment: AlignmentDirectional.centerStart, child: Ltr(r.summary)),
                    subtitle: Text(
                      s.forwards.errors[r.id] != null
                          ? l.f('fwdError', {'msg': s.forwards.errors[r.id]!})
                          : s.forwards.isRunning(r)
                              ? l.f('fwdActive', {'addr': '127.0.0.1:${s.forwards.boundPort(r)}'})
                              : l['fwdStopped'],
                      style: TextStyle(
                          color: s.forwards.errors[r.id] != null
                              ? p.red
                              : s.forwards.isRunning(r)
                                  ? p.green
                                  : p.muted,
                          fontSize: 12.5),
                    ),
                    value: s.forwards.isRunning(r),
                    onChanged: !live
                        ? null
                        : (v) {
                            if (v) {
                              s.startForward(r);
                            } else {
                              s.forwards.stop(r);
                            }
                          },
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('sheet-add-forward'),
                    icon: const Icon(Icons.add),
                    label: Text(l['addRule']),
                    onPressed: () async {
                      final r = await showDialog<ForwardRule>(context: c, builder: (_) => const ForwardRuleDialog());
                      if (r == null) return;
                      s.host.forwards.add(r);
                      await Store.i.updateHost(s.host);
                      if (r.autoStart) await s.startForward(r);
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---- install public key
  Future<void> _installKey() async {
    final l = S.of(context);
    final h = s.host;
    final sec = await Store.i.secret(h.id);
    String? line;
    String? newPem;
    if (sec.privateKey.trim().isNotEmpty) {
      line = publicKeyFromPrivate(sec.privateKey, passphrase: sec.passphrase);
    }
    if (!mounted) return;
    final body = line != null ? l['installKeyBody'] : l['installKeyNewBody'];
    if (!await confirm(context, l['installKey'], body, ok: l['install'])) return;
    if (line == null) {
      final g = generateEd25519(comment: 'mterm@${h.user}');
      line = g.publicLine;
      newPem = g.privatePem;
    }
    bool added;
    try {
      added = await s.installPublicKey(line);
    } catch (e) {
      if (mounted) toast(context, l.f('opFailed', {'msg': '$e'}));
      return;
    }
    if (newPem != null) await Store.i.saveKey(h.id, newPem.trim());
    if (!mounted) return;
    toast(context, added ? l['keyInstalled'] : l['keyAlreadyInstalled']);
    if (h.auth != 'key' && await confirm(context, l['useKeyTitle'], l['useKeyBody'], ok: l['useKey'])) {
      h.auth = 'key';
      await Store.i.updateHost(h);
    }
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

/// Second terminal shown next to the main one on wide screens.
class SplitPane extends StatefulWidget {
  const SplitPane({super.key, required this.session, required this.theme, required this.fontSize, required this.onClose});
  final TermSession session;
  final TerminalTheme theme;
  final double fontSize;
  final VoidCallback onClose;
  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  final controller = TerminalController();
  final focus = FocusNode();

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final st = Store.i.settings;
    final l = S.of(context);
    final light = widget.theme.background.computeLuminance() > 0.5;
    final fg = light ? const Color(0xFF24292F) : const Color(0xFFE6EBF7);
    final p = context.pal;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(children: [
        Container(
          height: 34,
          color: light ? const Color(0xFFF0F2F6) : Color.lerp(widget.theme.background, Colors.white, 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (s.status) {
                  SessStatus.connected => p.green,
                  SessStatus.connecting => p.amber,
                  _ => p.red,
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.host.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13)),
            ),
            if (s.status == SessStatus.failed || s.status == SessStatus.closed)
              TextButton(
                onPressed: () {
                  s.passwordPrompt ??= passwordPrompt;
                  s.reconnect(hostKeyPrompt);
                },
                child: Text(l['reconnect']),
              ),
            IconButton(
              key: const ValueKey('split-close'),
              tooltip: l['close'],
              iconSize: 18,
              color: fg,
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
            ),
          ]),
        ),
        Expanded(
          child: TerminalView(
            s.terminal,
            controller: controller,
            focusNode: focus,
            theme: widget.theme,
            shortcuts: terminalShortcuts(),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            cursorType: switch (st.cursor) {
              'underline' => TerminalCursorType.underline,
              'bar' => TerminalCursorType.verticalBar,
              _ => TerminalCursorType.block,
            },
            textStyle: TerminalStyle(
              fontSize: widget.fontSize,
              fontFamily: 'JetBrainsMono',
              fontFamilyFallback: const ['monospace', 'Vazirmatn', 'Noto Color Emoji'],
            ),
          ),
        ),
      ]),
    );
  }
}
