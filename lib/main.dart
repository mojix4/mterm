import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n.dart';
import 'screens/hosts_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/snippets_screen.dart';
import 'store.dart';
import 'themes.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.i.init();
  runApp(const MTermApp());
}

ThemeMode themeModeOf(String v) => switch (v) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

/// Rebuilds on every settings change (theme, language) and on device locale
/// changes, so both switch live without a restart.
class MTermApp extends StatefulWidget {
  const MTermApp({super.key});
  @override
  State<MTermApp> createState() => _MTermAppState();
}

class _MTermAppState extends State<MTermApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (Store.i.settings.language == 'system') setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final st = Store.i.settings;
        final lang = resolveLanguage(st.language, WidgetsBinding.instance.platformDispatcher.locales);
        final rtlFont = rtlLanguages.contains(lang);
        return MaterialApp(
          title: 'MTerm',
          debugShowCheckedModeBanner: false,
          navigatorKey: navKey,
          theme: appTheme(mode: Brightness.light, rtlFont: rtlFont),
          darkTheme: appTheme(mode: Brightness.dark, rtlFont: rtlFont),
          themeMode: themeModeOf(st.appTheme),
          locale: Locale(lang),
          supportedLocales: [for (final c in languageCodes) Locale(c)],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            // Status/navigation bar icons follow the active light/dark mode.
            final light = Theme.of(context).brightness == Brightness.light;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: context.pal.surface,
                systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
              ),
              child: LockGate(child: child ?? const SizedBox()),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: IndexedStack(index: tab, children: const [HostsScreen(), SnippetsScreen(), SettingsScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.dns_outlined), selectedIcon: const Icon(Icons.dns), label: s['navHosts']),
          NavigationDestination(
              icon: const Icon(Icons.bolt_outlined), selectedIcon: const Icon(Icons.bolt), label: s['navSnippets']),
          NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: s['navSettings']),
        ],
      ),
    );
  }
}
