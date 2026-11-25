import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../store.dart';
import '../themes.dart';
import '../updater.dart';
import 'common.dart';
import 'data_screens.dart';
import 'lock_screen.dart';
import 'terminal_screen.dart';


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  AppSettings get st => Store.i.settings;
  void _save() => Store.i.saveSettings();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final s = S.of(context);
        final p = context.pal;
        return Scaffold(
          appBar: AppBar(title: Text(s['navSettings'])),
          body: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 40), children: [
            Section(title: s['appearance'], children: [
              _choice<String>(
                  context,
                  s['theme'],
                  st.appTheme,
                  {'system': s['themeSystem'], 'dark': s['themeDark'], 'light': s['themeLight']},
                  (v) => st.appTheme = v),
              _choice<String>(
                  context,
                  s['language'],
                  st.language,
                  {'system': s['systemDefault'], for (final c in languageCodes) c: languageNames[c]!},
                  (v) => st.language = v),
            ]),
            Section(title: s['terminal'], children: [
              _themePicker(context),
              ListTile(
                title: Text(s['fontSize']),
                subtitle: Slider(
                  value: st.fontSize,
                  min: 8,
                  max: 30,
                  divisions: 22,
                  label: st.fontSize.round().toString(),
                  onChanged: (v) {
                    st.fontSize = v.roundToDouble();
                    _save();
                  },
                ),
                trailing: Text('${st.fontSize.round()}', style: TextStyle(color: p.muted)),
              ),
              _choice<String>(
                  context,
                  s['cursorShape'],
                  st.cursor,
                  {'block': s['cursorBlock'], 'underline': s['cursorUnderline'], 'bar': s['cursorBar']},
                  (v) => st.cursor = v),
              _choice<int>(
                  context,
                  s['scrollback'],
                  st.scrollback,
                  {
                    for (final n in const [1000, 5000, 10000, 20000]) n: s.f('nLines', {'n': s.num(n)})
                  },
                  (v) => st.scrollback = v,
                  note: s['forNewSessions']),
              ListTile(
                title: Text(s['customizeKeys']),
                subtitle: Text(s.f('nKeys', {'n': st.keys.length}), style: TextStyle(color: p.muted)),
                trailing: Icon(Icons.chevron_right, color: p.muted),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KeysEditor())),
              ),
              SwitchListTile(
                title: Text(s['vibrateOnBell']),
                value: st.vibrate,
                onChanged: (v) {
                  st.vibrate = v;
                  _save();
                },
              ),
              SwitchListTile(
                key: const ValueKey('log-sessions'),
                title: Text(s['logSessions']),
                subtitle: Text(s['logSessionsHint'], style: TextStyle(color: p.muted)),
                value: st.logSessions,
                onChanged: (v) {
                  st.logSessions = v;
                  _save();
                },
              ),
              ListTile(
                key: const ValueKey('view-logs'),
                title: Text(s['sessionLogs']),
                trailing: Icon(Icons.chevron_right, color: p.muted),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogsScreen())),
              ),
              SwitchListTile(
                title: Text(s['keepScreenOn']),
                subtitle: Text(s['whileTerminalOpen'], style: TextStyle(color: p.muted)),
                value: st.wakelock,
                onChanged: (v) {
                  st.wakelock = v;
                  _save();
                },
              ),
            ]),
            Section(title: s['connection'], children: [
              _choice<int>(
                  context,
                  s['keepAlive'],
                  st.keepAlive,
                  {
                    0: s['off'],
                    for (final n in const [15, 30, 60]) n: s.f('nSeconds', {'n': s.num(n)})
                  },
                  (v) => st.keepAlive = v,
                  note: s['keepAliveNote']),
              ListTile(
                title: Text(s['clearKnownHosts']),
                subtitle: Text(s.f('nServers', {'n': Store.i.knownHosts.length}), style: TextStyle(color: p.muted)),
                onTap: () async {
                  if (await confirm(context, s['knownHostsTitle'], s['knownHostsBody'],
                      ok: s['clearIt'], danger: true)) {
                    await Store.i.clearKnownHosts();
                    _save();
                  }
                },
              ),
            ]),
            Section(title: s['backup'], children: [
              ListTile(
                key: const ValueKey('export-backup'),
                leading: const Icon(Icons.backup_outlined),
                title: Text(s['exportBackup']),
                subtitle: Text(s['exportBackupHint'], style: TextStyle(color: p.muted)),
                onTap: () => exportBackup(context),
              ),
              ListTile(
                key: const ValueKey('import-backup'),
                leading: const Icon(Icons.settings_backup_restore),
                title: Text(s['importBackup']),
                subtitle: Text(s['importBackupHint'], style: TextStyle(color: p.muted)),
                onTap: () => importBackup(context),
              ),
              ListTile(
                key: const ValueKey('clear-history'),
                leading: const Icon(Icons.history_toggle_off),
                title: Text(s['clearHistory']),
                subtitle: Text(s.f('nCommands', {'n': s.num(Store.i.history.length)}), style: TextStyle(color: p.muted)),
                onTap: () async {
                  if (await confirm(context, s['clearHistory'], s['clearHistoryBody'], ok: s['clearIt'], danger: true)) {
                    await Store.i.clearHistory();
                    if (context.mounted) toast(context, s['historyCleared']);
                  }
                },
              ),
            ]),
            Section(title: s['security'], children: [
              SwitchListTile(
                title: Text(s['pinLock']),
                value: st.lockEnabled && st.pinHash.isNotEmpty,
                onChanged: (v) async {
                  if (v) {
                    final pin = await Navigator.of(context).push<String>(
                        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PinPad(setMode: true)));
                    if (pin == null) return;
                    st.pinHash = Store.hashPin(pin);
                    st.lockEnabled = true;
                  } else {
                    st.lockEnabled = false;
                    st.pinHash = '';
                    st.biometric = false;
                  }
                  _save();
                },
              ),
              if (st.lockEnabled) ...[
                SwitchListTile(
                  title: Text(s['bioUnlock']),
                  value: st.biometric,
                  onChanged: (v) async {
                    if (v) {
                      try {
                        final auth = LocalAuthentication();
                        final can = await auth.canCheckBiometrics && await auth.isDeviceSupported();
                        if (!can) {
                          if (context.mounted) toast(context, s['bioNotEnabled']);
                          return;
                        }
                        final ok = await auth.authenticate(
                            localizedReason: s['bioConfirm'],
                            options: AuthenticationOptions(biometricOnly: !Platform.isWindows));
                        if (!ok) return;
                      } catch (_) {
                        if (context.mounted) toast(context, s['bioUnavailable']);
                        return;
                      }
                    }
                    st.biometric = v;
                    _save();
                  },
                ),
                _choice<int>(
                    context,
                    s['autoLockAfter'],
                    st.lockAfter,
                    {
                      0: s['immediately'],
                      for (final n in const [1, 5, 15]) n * 60: s.f('nMinutes', {'n': s.num(n)})
                    },
                    (v) => st.lockAfter = v),
              ],
            ]),
            Section(title: s['about'], children: [
              ListTile(
                title: const Text('MTerm'),
                subtitle: Text(s['appTagline'], style: TextStyle(color: p.muted)),
                trailing: Text('v$appVersion', style: TextStyle(color: p.muted)),
              ),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: Text(s['checkUpdate']),
                subtitle: Text(s['checkUpdateHint'], style: TextStyle(color: p.muted)),
                trailing: Icon(Icons.chevron_right, color: p.muted),
                onTap: () => checkForUpdate(context),
              ),
              ListTile(
                title: Text(s['licenses']),
                trailing: Icon(Icons.chevron_right, color: p.muted),
                onTap: () =>
                    showLicensePage(context: context, applicationName: 'MTerm', applicationVersion: appVersion),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Widget _themePicker(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final mode = Theme.of(context).brightness;
    final names = [autoTerminalTheme, ...terminalThemes.keys];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s['colorScheme']),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final name in names)
              Builder(builder: (_) {
                final t = terminalThemeFor(name, mode);
                final selected =
                    st.theme == name || (name == autoTerminalTheme && !terminalThemes.containsKey(st.theme));
                return GestureDetector(
                  onTap: () {
                    st.theme = name;
                    _save();
                  },
                  child: Container(
                    width: 92,
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? p.accent : p.line, width: selected ? 2.5 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('\$ ls',
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: t.foreground)),
                      const Spacer(),
                      Text(name == autoTerminalTheme ? s['themeAuto'] : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: t.foreground.withValues(alpha: 0.8))),
                    ]),
                  ),
                );
              }),
          ]),
        ),
      ]),
    );
  }

  Widget _choice<T>(BuildContext context, String title, T value, Map<T, String> options, void Function(T) set,
      {String? note}) {
    final p = context.pal;
    return ListTile(
      title: Text(title),
      subtitle: note == null ? null : Text(note, style: TextStyle(color: p.muted, fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(options[value] ?? '$value', style: TextStyle(color: p.muted)),
        Icon(Icons.chevron_right, color: p.muted),
      ]),
      onTap: () async {
        final r = await showModalBottomSheet<T>(
          context: context,
          builder: (c) => SafeArea(
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final e in options.entries)
                ListTile(
                  title: Text(e.value),
                  trailing: e.key == value ? Icon(Icons.check, color: p.accent) : null,
                  onTap: () => Navigator.pop(c, e.key),
                ),
              const SizedBox(height: 8),
            ])),
          ),
        );
        if (r != null) {
          set(r);
          _save();
        }
      },
    );
  }
}

class KeysEditor extends StatelessWidget {
  const KeysEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final st = Store.i.settings;
        final s = S.of(context);
        final p = context.pal;
        return Scaffold(
          appBar: AppBar(title: Text(s['keyBar']), actions: [
            TextButton(
              onPressed: () {
                st.keys = List.of(AppSettings.defaultKeys);
                Store.i.saveSettings();
              },
              child: Text(s['defaults']),
            ),
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text(s['activeKeys'], style: TextStyle(color: p.muted)),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.ltr,
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorderItem: (a, b) {
                  final k = st.keys.removeAt(a);
                  st.keys.insert(b, k);
                  Store.i.saveSettings();
                },
                children: [
                  for (final k in st.keys)
                    ListTile(
                      key: ValueKey(k),
                      tileColor: p.surface,
                      title: Text(k, style: const TextStyle(fontFamily: 'JetBrainsMono')),
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle_outline, color: p.red),
                        onPressed: () {
                          st.keys.remove(k);
                          Store.i.saveSettings();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(s['addKey'], style: TextStyle(color: p.muted)),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in allBarKeys.where((k) => !st.keys.contains(k)))
                  ActionChip(
                    label: Text(k, style: const TextStyle(fontFamily: 'JetBrainsMono')),
                    onPressed: () {
                      st.keys.add(k);
                      Store.i.saveSettings();
                    },
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

Future<void> checkForUpdate(BuildContext context) async {
  final s = S.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 16),
        Expanded(child: Text(s['checkingUpdate'])),
      ]),
    ),
  );
  UpdateInfo? info;
  try {
    info = await fetchLatest();
  } catch (_) {}
  if (!context.mounted) return;
  Navigator.of(context).pop();
  if (info == null) {
    final open = await confirm(context, s['checkUpdate'], s['updateFailed'], ok: s['openDownloadPage']);
    if (open) launchUrl(Uri.parse(releasesPage), mode: LaunchMode.externalApplication);
    return;
  }
  if (compareVersions(info.version, appVersion) <= 0) {
    toast(context, s.f('upToDate', {'v': appVersion}));
    return;
  }
  final go = await confirm(context, s.f('updateAvailable', {'v': info.version}),
      s.f('updateBody', {'cur': appVersion}), ok: s['download']);
  if (go) launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
}
