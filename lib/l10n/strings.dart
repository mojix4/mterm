// Pure-Dart table of every UI string, by language code. No Flutter imports, so
// tool/check_l10n.dart can load it with plain `dart run`.
import 'ar.dart';
import 'de.dart';
import 'en.dart';
import 'es.dart';
import 'fa.dart';
import 'fr.dart';
import 'ru.dart';
import 'tr.dart';
import 'zh.dart';

/// Supported UI languages, in the order shown in Settings.
const List<String> languageCodes = ['fa', 'en', 'ar', 'tr', 'ru', 'de', 'fr', 'es', 'zh'];

/// Each language in its own name (never translated).
const Map<String, String> languageNames = {
  'fa': 'فارسی',
  'en': 'English',
  'ar': 'العربية',
  'tr': 'Türkçe',
  'ru': 'Русский',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'zh': '中文',
};

const Set<String> rtlLanguages = {'fa', 'ar'};

const Map<String, Map<String, String>> allStrings = {
  'fa': fa,
  'en': en,
  'ar': ar,
  'tr': tr,
  'ru': ru,
  'de': de,
  'fr': fr,
  'es': es,
  'zh': zh,
};
