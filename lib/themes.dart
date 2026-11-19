import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// App chrome colours (Termius-like dark navy).
class C {
  static const bg = Color(0xFF10131F);
  static const surface = Color(0xFF181C2C);
  static const surface2 = Color(0xFF222741);
  static const line = Color(0xFF2A2F4A);
  static const text = Color(0xFFE7EAF3);
  static const muted = Color(0xFF8A93AB);
  static const accent = Color(0xFF3D8BFF);
  static const green = Color(0xFF21B568);
  static const red = Color(0xFFEF4F5D);
  static const amber = Color(0xFFF2A93B);

  static const hostColors = [
    Color(0xFF21B568), Color(0xFF3D8BFF), Color(0xFFA66BFF), Color(0xFFF2A93B),
    Color(0xFFEF4F5D), Color(0xFF19B8C8), Color(0xFFFF7AB6), Color(0xFF8A93AB),
  ];
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

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Vazirmatn',
    colorScheme: const ColorScheme.dark(
      primary: C.accent,
      secondary: C.green,
      surface: C.surface,
      error: C.red,
    ),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Vazirmatn', fontSize: 22, fontWeight: FontWeight.w700, color: C.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: C.accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'Vazirmatn', fontSize: 12)),
      height: 64,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: C.muted),
      hintStyle: const TextStyle(color: C.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surface2,
      contentTextStyle: const TextStyle(fontFamily: 'Vazirmatn', color: C.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: C.line, space: 1, thickness: 1),
  );
}
