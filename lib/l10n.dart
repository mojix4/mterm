// Localization layer: a plain map lookup, no codegen.
//
//   final s = S.of(context);
//   Text(s['save']);
//   Text(s.f('nLines', {'n': s.num(5000)}));
//
// Strings live in lib/l10n/<code>.dart; en.dart is the reference key set and
// the fallback for anything missing.
import 'dart:ui' show Locale, PlatformDispatcher, TextDirection;

import 'package:flutter/widgets.dart' show BuildContext, Localizations;

import 'l10n/strings.dart';
import 'store.dart';

export 'l10n/strings.dart' show languageCodes, languageNames, rtlLanguages;

/// Turns the language setting ('system' or a code) into a supported code.
/// 'system' picks the first supported language among the device's preferred
/// locales and falls back to English.
String resolveLanguage(String setting, List<Locale> device) {
  if (languageCodes.contains(setting)) return setting;
  for (final l in device) {
    if (languageCodes.contains(l.languageCode)) return l.languageCode;
  }
  return 'en';
}

class S {
  S._(this.code) : _m = allStrings[code]!;
  final String code;
  final Map<String, String> _m;
  static final Map<String, S> _cache = {};
  static final Map<String, String> _en = allStrings['en']!;

  static S forCode(String code) {
    final c = languageCodes.contains(code) ? code : 'en';
    return _cache.putIfAbsent(c, () => S._(c));
  }

  /// Strings for the locale the widget tree is showing.
  static S of(BuildContext context) => forCode(Localizations.localeOf(context).languageCode);

  /// Strings for the language currently chosen in Settings, for code that has
  /// no BuildContext (connection errors, default snippets).
  static S get current => forCode(resolveLanguage(Store.i.settings.language, PlatformDispatcher.instance.locales));

  bool get isRtl => rtlLanguages.contains(code);
  TextDirection get direction => isRtl ? TextDirection.rtl : TextDirection.ltr;

  String operator [](String key) => _m[key] ?? _en[key] ?? key;

  /// Looks up [key] and fills `{name}` placeholders from [args].
  String f(String key, Map<String, Object> args) {
    var s = this[key];
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// Formats [n] with the language's own digits (Persian digits in fa).
  String num(int n) {
    if (code != 'fa') return '$n';
    const d = '۰۱۲۳۴۵۶۷۸۹';
    return '$n'.split('').map((c) {
      final i = c.codeUnitAt(0) - 48;
      return i >= 0 && i <= 9 ? d[i] : c;
    }).join();
  }
}
