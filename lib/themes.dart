import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// App chrome colours. Read them with `context.pal` so every screen follows
/// the current light/dark mode.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.green,
    required this.red,
    required this.amber,
  });

  final Color bg, surface, surface2, line, text, muted, accent, green, red, amber;

  /// The original Termius-like dark navy look.
  static const dark = Palette(
    bg: Color(0xFF10131F),
    surface: Color(0xFF181C2C),
    surface2: Color(0xFF222741),
    line: Color(0xFF2A2F4A),
    text: Color(0xFFE7EAF3),
    muted: Color(0xFF8A93AB),
    accent: Color(0xFF3D8BFF),
    green: Color(0xFF21B568),
    red: Color(0xFFEF4F5D),
    amber: Color(0xFFF2A93B),
  );

  /// Light counterpart: cool grey-blue background, white cards, same accent.
  /// Status colours are a shade deeper so they keep contrast on white.
  static const light = Palette(
    bg: Color(0xFFF3F5FA),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE9EDF5),
    line: Color(0xFFE1E5EE),
    text: Color(0xFF151A2D),
    muted: Color(0xFF5E6781),
    accent: Color(0xFF3D8BFF),
    green: Color(0xFF15985A),
    red: Color(0xFFD93A4A),
    amber: Color(0xFFC77D14),
  );

  static const hostColors = [
    Color(0xFF21B568), Color(0xFF3D8BFF), Color(0xFFA66BFF), Color(0xFFF2A93B),
    Color(0xFFEF4F5D), Color(0xFF19B8C8), Color(0xFFFF7AB6), Color(0xFF8A93AB),
  ];

  bool get isLight => bg.computeLuminance() > 0.5;

  @override
  Palette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? text,
    Color? muted,
    Color? accent,
    Color? green,
    Color? red,
    Color? amber,
  }) =>
      Palette(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        line: line ?? this.line,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        green: green ?? this.green,
        red: red ?? this.red,
        amber: amber ?? this.amber,
      );

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      line: l(line, other.line),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      green: l(green, other.green),
      red: l(red, other.red),
      amber: l(amber, other.amber),
    );
  }
}

extension PaletteX on BuildContext {
  /// The app palette for the current theme mode.
  Palette get pal => Theme.of(this).extension<Palette>() ?? Palette.dark;
}

TerminalTheme _mk({
  required Color bg,
  required Color fg,
  Color? cursor,
  Color? selection,
  List<Color>? ansi,
}) {
  final d = TerminalThemes.defaultTheme;
  final a = ansi ??
      [
        d.black, d.red, d.green, d.yellow, d.blue, d.magenta, d.cyan, d.white,
        d.brightBlack, d.brightRed, d.brightGreen, d.brightYellow, d.brightBlue, d.brightMagenta,
        d.brightCyan, d.brightWhite,
      ];
  return TerminalTheme(
    cursor: cursor ?? fg,
    selection: selection ?? fg.withValues(alpha: 0.3),
    foreground: fg,
    background: bg,
    black: a[0],
    red: a[1],
    green: a[2],
    yellow: a[3],
    blue: a[4],
    magenta: a[5],
    cyan: a[6],
    white: a[7],
    brightBlack: a[8],
    brightRed: a[9],
    brightGreen: a[10],
    brightYellow: a[11],
    brightBlue: a[12],
    brightMagenta: a[13],
    brightCyan: a[14],
    brightWhite: a[15],
    searchHitBackground: const Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: const Color(0xFF31FF26),
    searchHitForeground: const Color(0xFF000000),
  );
}

final Map<String, TerminalTheme> terminalThemes = {
  'Termius': _mk(bg: const Color(0xFF141729), fg: const Color(0xFF21B568), selection: const Color(0x663D8BFF)),
  'Ocean': _mk(bg: const Color(0xFF0F1424), fg: const Color(0xFFD6DEEB), cursor: const Color(0xFF7FDBCA)),
  'Dracula': _mk(bg: const Color(0xFF282A36), fg: const Color(0xFFF8F8F2), ansi: const [
    Color(0xFF21222C), Color(0xFFFF5555), Color(0xFF50FA7B), Color(0xFFF1FA8C),
    Color(0xFFBD93F9), Color(0xFFFF79C6), Color(0xFF8BE9FD), Color(0xFFF8F8F2),
    Color(0xFF6272A4), Color(0xFFFF6E6E), Color(0xFF69FF94), Color(0xFFFFFFA5),
    Color(0xFFD6ACFF), Color(0xFFFF92DF), Color(0xFFA4FFFF), Color(0xFFFFFFFF),
  ]),
  'Solarized': _mk(bg: const Color(0xFF002B36), fg: const Color(0xFF93A1A1)),
  'Monokai': _mk(bg: const Color(0xFF272822), fg: const Color(0xFFF8F8F2)),
  'Light': _mk(bg: const Color(0xFFFFFFFF), fg: const Color(0xFF24292F), ansi: const [
    Color(0xFF24292F), Color(0xFFCF222E), Color(0xFF116329), Color(0xFF9A6700),
    Color(0xFF0550AE), Color(0xFF8250DF), Color(0xFF1B7C83), Color(0xFF6E7781),
    Color(0xFF57606A), Color(0xFFA40E26), Color(0xFF1A7F37), Color(0xFF7D4E00),
    Color(0xFF218BFF), Color(0xFFA475F9), Color(0xFF3192AA), Color(0xFF8C959F),
  ]),
};

/// Name of the terminal colour scheme that follows the app theme.
const autoTerminalTheme = 'Auto';

/// The terminal colours to use for the [name] setting in the given app mode.
/// 'Auto' is Termius navy in dark mode and the Light scheme in light mode.
TerminalTheme terminalThemeFor(String name, Brightness mode) {
  if (name == autoTerminalTheme || !terminalThemes.containsKey(name)) {
    return terminalThemes[mode == Brightness.light ? 'Light' : 'Termius']!;
  }
  return terminalThemes[name]!;
}

/// App theme for [mode]. [rtlFont] uses Vazirmatn (fa/ar); other languages use
/// the platform font, with Vazirmatn only as a fallback for Persian/Arabic text
/// such as server names. CJK falls back to the platform's own fonts.
ThemeData appTheme({Brightness mode = Brightness.dark, bool rtlFont = true}) {
  final p = mode == Brightness.light ? Palette.light : Palette.dark;
  final light = mode == Brightness.light;
  final String? font = rtlFont ? 'Vazirmatn' : null;
  final fallback = rtlFont ? null : const ['Vazirmatn'];
  TextStyle ts({double? size, FontWeight? weight, Color? color}) => TextStyle(
      fontFamily: font, fontFamilyFallback: fallback, fontSize: size, fontWeight: weight, color: color);
  final overlay = (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: p.surface,
    systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
  );
  final scheme = light
      ? ColorScheme.light(
          primary: p.accent,
          secondary: p.green,
          surface: p.surface,
          onSurface: p.text,
          error: p.red,
          outline: p.line,
          surfaceContainerHighest: p.surface2,
        )
      : ColorScheme.dark(
          primary: p.accent,
          secondary: p.green,
          surface: p.surface,
          error: p.red,
        );
  final base = ThemeData(
    useMaterial3: true,
    brightness: mode,
    fontFamily: font,
    fontFamilyFallback: fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: overlay,
      titleTextStyle: ts(size: 22, weight: FontWeight.w700, color: p.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.accent.withValues(alpha: light ? 0.14 : 0.18),
      labelTextStyle: WidgetStateProperty.all(ts(size: 12, color: p.text)),
      height: 64,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: TextStyle(color: p.muted),
      hintStyle: TextStyle(color: p.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: ts(size: 16, weight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(color: p.surface, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: light ? const Color(0xFF242A40) : p.surface2,
      contentTextStyle: ts(color: light ? Colors.white : p.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
  );
}
