import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../store.dart';
import '../themes.dart';
import 'common.dart';
import 'lock_screen.dart';
import 'terminal_screen.dart';

const appVersion = '1.0.0';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  AppSettings get st => Store.i.settings;
  void _save() => Store.i.saveSettings();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('تنظیمات')),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 40), children: [
          Section(title: 'ترمینال', children: [
            _themePicker(),
            ListTile(
              title: const Text('اندازه فونت'),
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
              trailing: Text('${st.fontSize.round()}', style: const TextStyle(color: C.muted)),
            ),
            _choice<String>(context, 'شکل نشانگر', st.cursor, const {'block': 'بلوک', 'underline': 'زیرخط', 'bar': 'خط عمودی'},
                (v) => st.cursor = v),
            _choice<int>(context, 'بافر ترمینال', st.scrollback,
                const {1000: '۱۰۰۰ خط', 5000: '۵۰۰۰ خط', 10000: '۱۰۰۰۰ خط', 20000: '۲۰۰۰۰ خط'}, (v) => st.scrollback = v,
                note: 'برای نشست‌های جدید'),
            ListTile(
              title: const Text('شخصی‌سازی نوار کلید'),
              subtitle: Text('${st.keys.length} کلید', style: const TextStyle(color: C.muted)),
              trailing: const Icon(Icons.chevron_left, color: C.muted),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KeysEditor())),
            ),
            SwitchListTile(
              title: const Text('لرزش هنگام زنگ'),
              value: st.vibrate,
              onChanged: (v) {
                st.vibrate = v;
                _save();
              },
            ),
            SwitchListTile(
              title: const Text('روشن ماندن صفحه'),
              subtitle: const Text('وقتی ترمینال باز است', style: TextStyle(color: C.muted)),
              value: st.wakelock,
              onChanged: (v) {
                st.wakelock = v;
                _save();
              },
            ),
          ]),
          Section(title: 'اتصال', children: [
            _choice<int>(context, 'Keep alive', st.keepAlive,
                const {0: 'خاموش', 15: '۱۵ ثانیه', 30: '۳۰ ثانیه', 60: '۶۰ ثانیه'}, (v) => st.keepAlive = v,
                note: 'جلوی قطع شدن اتصال بیکار را می‌گیرد'),
            ListTile(
              title: const Text('پاک کردن کلیدهای شناخته‌شده'),
              subtitle: Text('${Store.i.knownHosts.length} سرور', style: const TextStyle(color: C.muted)),
              onTap: () async {
                if (await confirm(context, 'کلیدهای سرور', 'اثر انگشت همه سرورها پاک شود؟ در اتصال بعدی دوباره پرسیده می‌شود.',
                    ok: 'پاک کن', danger: true)) {
                  await Store.i.clearKnownHosts();
                  _save();
                }
              },
            ),
          ]),
          Section(title: 'امنیت', children: [
            SwitchListTile(
              title: const Text('قفل برنامه با PIN'),
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
                title: const Text('باز کردن با اثر انگشت'),
                value: st.biometric,
                onChanged: (v) async {
                  if (v) {
                    try {
                      final auth = LocalAuthentication();
                      final can = await auth.canCheckBiometrics && await auth.isDeviceSupported();
                      if (!can) {
                        if (context.mounted) toast(context, 'اثر انگشت روی این گوشی فعال نیست');
                        return;
                      }
                      final ok = await auth.authenticate(
                          localizedReason: 'تأیید اثر انگشت',
                          options: AuthenticationOptions(biometricOnly: !Platform.isWindows));
                      if (!ok) return;
                    } catch (_) {
                      if (context.mounted) toast(context, 'اثر انگشت در دسترس نیست');
                      return;
                    }
                  }
                  st.biometric = v;
                  _save();
                },
              ),
              _choice<int>(context, 'قفل خودکار بعد از', st.lockAfter,
                  const {0: 'فوری', 60: '۱ دقیقه', 300: '۵ دقیقه', 900: '۱۵ دقیقه'}, (v) => st.lockAfter = v),
            ],
          ]),
          Section(title: 'درباره', children: [
            const ListTile(
              title: Text('MTerm'),
              subtitle: Text('ترمینال SSH سبک و سریع برای اندروید', style: TextStyle(color: C.muted)),
              trailing: Text('v$appVersion', style: TextStyle(color: C.muted)),
            ),
            ListTile(
              title: const Text('مجوزهای نرم‌افزارهای متن‌باز'),
              trailing: const Icon(Icons.chevron_left, color: C.muted),
              onTap: () => showLicensePage(context: context, applicationName: 'MTerm', applicationVersion: appVersion),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _themePicker() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('رنگ‌بندی'),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in terminalThemes.entries)
                GestureDetector(
                  onTap: () {
                    st.theme = e.key;
                    _save();
                  },
                  child: Container(
                    width: 92,
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: e.value.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: st.theme == e.key ? C.accent : C.line, width: st.theme == e.key ? 2.5 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('\$ ls', textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.clip,
                          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: e.value.foreground)),
                      const Spacer(),
                      Text(e.key, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: e.value.foreground.withValues(alpha: 0.8))),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      );

  Widget _choice<T>(BuildContext context, String title, T value, Map<T, String> options, void Function(T) set,
      {String? note}) {
    return ListTile(
      title: Text(title),
      subtitle: note == null ? null : Text(note, style: const TextStyle(color: C.muted, fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(options[value] ?? '$value', style: const TextStyle(color: C.muted)),
        const Icon(Icons.chevron_left, color: C.muted),
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
                  trailing: e.key == value ? const Icon(Icons.check, color: C.accent) : null,
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
        return Scaffold(
          appBar: AppBar(title: const Text('نوار کلید'), actions: [
            TextButton(
              onPressed: () {
                st.keys = List.of(AppSettings.defaultKeys);
                Store.i.saveSettings();
              },
              child: const Text('پیش‌فرض'),
            ),
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('کلیدهای فعال (برای جابه‌جایی بکشید):', style: TextStyle(color: C.muted)),
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
                      tileColor: C.surface,
                      title: Text(k, style: const TextStyle(fontFamily: 'JetBrainsMono')),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: C.red),
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
            const Text('افزودن کلید:', style: TextStyle(color: C.muted)),
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
