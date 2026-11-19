// End-to-end UI flows that need no SSH server (run in CI).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/common.dart';
import 'package:mterm/screens/lock_screen.dart';
import 'package:mterm/session.dart';
import 'package:mterm/store.dart';
import 'package:mterm/themes.dart';
import 'package:xterm/xterm.dart';

import 'support.dart';

const phone = Size(360, 780);

final _vScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

/// Scrolls the top-most vertical list until [f] is built and visible.
Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, 150, scrollable: _vScroll.last);
  }
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
}

/// The app is Persian, so the back button's tooltip is localized; tap it by type.
Future<void> back(WidgetTester t) async {
  await t.tap(find.byType(BackButton).last);
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String s, {bool last = false}) async {
  final f = last ? find.text(s).last : find.text(s);
  await reveal(t, f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> openHostMenu(WidgetTester t, String label, String item) async {
  final tile = find.ancestor(of: find.text(label), matching: find.byType(ListTile));
  await t.tap(find.descendant(of: tile, matching: find.byIcon(Icons.more_vert)));
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(installMocks);
  setUp(freshStore);

  group('hosts', () {
    testWidgets('add (password), persists, edit, delete with confirm', (t) async {
      await setSize(t, phone);
      await launch(t);
      expect(find.text('هنوز سروری اضافه نکرده‌اید'), findsOneWidget);

      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      expect(find.text('سرور جدید'), findsOneWidget);
      await t.enterText(fieldLabeled('نام (اختیاری)'), 'سرور تست');
      await t.enterText(fieldLabeled('آدرس سرور'), ' 10.0.0.5 ');
      await t.enterText(fieldLabeled('پورت'), '2200');
      await t.enterText(fieldLabeled('نام کاربری'), 'admin');
      await t.enterText(fieldLabeled('رمز عبور'), 'S3cret pw');
      await t.tap(find.widgetWithText(FilledButton, 'ذخیره'));
      await t.pumpAndSettle();

      expect(find.text('سرور تست'), findsOneWidget);
      expect(find.text('ssh admin@10.0.0.5:2200'), findsOneWidget);

      await reloadStore();
      expect(Store.i.hosts, hasLength(1));
      final h = Store.i.hosts.single;
      expect([h.label, h.host, h.port, h.user, h.auth], ['سرور تست', '10.0.0.5', 2200, 'admin', 'password']);
      expect((await Store.i.secret(h.id)).password, 'S3cret pw');

      // edit
      await launch(t);
      await openHostMenu(t, 'سرور تست', 'ویرایش');
      expect(find.text('ویرایش سرور'), findsOneWidget);
      expect(find.text('S3cret pw'), findsOneWidget); // secret loaded into the form
      await t.enterText(fieldLabeled('نام (اختیاری)'), 'سرور اصلی');
      await t.enterText(fieldLabeled('پورت'), '22');
      await t.tap(find.widgetWithText(FilledButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('سرور اصلی'), findsOneWidget);
      expect(find.text('ssh admin@10.0.0.5'), findsOneWidget);
      expect(Store.i.hosts, hasLength(1));
      await reloadStore();
      expect(Store.i.hosts.single.label, 'سرور اصلی');
      expect(Store.i.hosts.single.id, h.id);

      // duplicate
      await launch(t);
      await openHostMenu(t, 'سرور اصلی', 'کپی از این سرور');
      await t.tap(find.widgetWithText(FilledButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(Store.i.hosts, hasLength(2));
      expect(find.text('سرور اصلی (کپی)'), findsOneWidget);
      final dup = Store.i.hosts.firstWhere((x) => x.id != h.id);
      expect((await Store.i.secret(dup.id)).password, 'S3cret pw');

      // delete: cancel keeps it, confirm removes it and its secrets
      await openHostMenu(t, 'سرور اصلی (کپی)', 'حذف');
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'انصراف'));
      await t.pumpAndSettle();
      expect(Store.i.hosts, hasLength(2));
      await openHostMenu(t, 'سرور اصلی (کپی)', 'حذف');
      await t.tap(find.widgetWithText(TextButton, 'حذف'));
      await t.pumpAndSettle();
      expect(find.text('سرور اصلی (کپی)'), findsNothing);
      expect(Store.i.hosts, hasLength(1));
      expect(secure.keys.where((k) => k.endsWith(dup.id)), isEmpty);
      await reloadStore();
      expect(Store.i.hosts.single.id, h.id);
    });

    testWidgets('add with SSH key (pasted) + validation errors', (t) async {
      await setSize(t, phone);
      await launch(t);
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();

      // validation: empty address, empty user, bad port
      await t.enterText(fieldLabeled('نام کاربری'), '   ');
      await t.enterText(fieldLabeled('پورت'), '0');
      await t.tap(find.widgetWithText(TextButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('آدرس را وارد کنید'), findsOneWidget);
      expect(find.text('نام کاربری را وارد کنید'), findsOneWidget);
      expect(find.text('نامعتبر'), findsOneWidget);
      await t.enterText(fieldLabeled('پورت'), '70000');
      await t.tap(find.widgetWithText(TextButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('نامعتبر'), findsOneWidget);
      await t.enterText(fieldLabeled('پورت'), '');
      await t.tap(find.widgetWithText(TextButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('نامعتبر'), findsOneWidget);
      expect(Store.i.hosts, isEmpty);

      await t.enterText(fieldLabeled('آدرس سرور'), sshHost);
      await t.enterText(fieldLabeled('پورت'), '$sshPort');
      await t.enterText(fieldLabeled('نام کاربری'), sshUser);
      await t.enterText(fieldLabeled('نام (اختیاری)'), 'با کلید');

      await t.tap(find.text('کلید SSH'));
      await t.pumpAndSettle();
      // empty key is rejected
      await t.tap(find.widgetWithText(TextButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('کلید خصوصی معتبر نیست'), findsOneWidget);

      // paste with garbage in clipboard
      clipboard = 'hello';
      await reveal(t, find.text('چسباندن کلید'));
      await t.tap(find.text('چسباندن کلید'));
      await t.pumpAndSettle();
      expect(find.text('در کلیپ‌بورد کلید خصوصی پیدا نشد'), findsOneWidget);

      final key = testKey();
      clipboard = key;
      await reveal(t, find.text('چسباندن کلید'));
      await t.tap(find.text('چسباندن کلید'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('با کلید'), findsOneWidget);

      await reloadStore();
      final h = Store.i.hosts.single;
      expect(h.auth, 'key');
      expect(h.port, sshPort);
      expect((await Store.i.secret(h.id)).privateKey, key.trim());
    });

    testWidgets('search filters the host list', (t) async {
      await setSize(t, phone);
      await Store.i.upsertHost(Host(id: 'a', label: 'آلمان', host: 'de.example.com', user: 'root'), HostSecret());
      await Store.i.upsertHost(Host(id: 'b', label: 'Finland', host: '1.2.3.4', user: 'admin'), HostSecret());
      await launch(t);
      await t.enterText(find.byType(TextField).first, 'FIN');
      await t.pumpAndSettle();
      expect(find.text('Finland'), findsOneWidget);
      expect(find.text('آلمان'), findsNothing);
      await t.enterText(find.byType(TextField).first, 'de.');
      await t.pumpAndSettle();
      expect(find.text('آلمان'), findsOneWidget);
    });
  });

  group('snippets', () {
    testWidgets('add, edit, delete, persist; run with no session explains', (t) async {
      await setSize(t, phone);
      await launch(t);
      await t.tap(find.text('دستورها').last);
      await t.pumpAndSettle();
      final before = Store.i.snippets.length;

      await t.tap(find.byType(FloatingActionButton).last);
      await t.pumpAndSettle();
      expect(find.text('دستور جدید'), findsOneWidget);
      // empty -> nothing saved, sheet stays
      await t.tap(find.widgetWithText(FilledButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('دستور جدید'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'نام'), 'ری‌استارت وب');
      await t.enterText(find.widgetWithText(TextField, 'دستور'), 'systemctl restart nginx');
      await t.tap(find.widgetWithText(FilledButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('ری‌استارت وب'), findsOneWidget);
      expect(Store.i.snippets.length, before + 1);

      // edit (long press)
      await t.ensureVisible(find.text('ری‌استارت وب'));
      await t.longPress(find.text('ری‌استارت وب'));
      await t.pumpAndSettle();
      expect(find.text('ویرایش دستور'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'دستور'), 'systemctl reload nginx');
      await t.tap(find.widgetWithText(FilledButton, 'ذخیره'));
      await t.pumpAndSettle();
      expect(find.text('systemctl reload nginx'), findsOneWidget);
      expect(Store.i.snippets.length, before + 1);

      await reloadStore();
      expect(Store.i.snippets.where((s) => s.cmd == 'systemctl reload nginx'), hasLength(1));

      // run with no live session
      await launch(t);
      await t.tap(find.text('دستورها').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('ری‌استارت وب'));
      await t.tap(find.text('ری‌استارت وب'));
      await t.pump();
      expect(find.text('اول از بخش سرورها به یک سرور وصل شوید'), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 3));

      // delete
      await t.longPress(find.text('ری‌استارت وب'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'حذف'));
      await t.pumpAndSettle();
      expect(find.text('ری‌استارت وب'), findsNothing);
      await reloadStore();
      expect(Store.i.snippets.length, before);

      // deleting every snippet must not bring the defaults back
      for (final s in List.of(Store.i.snippets)) {
        await Store.i.deleteSnippet(s);
      }
      await reloadStore();
      expect(Store.i.snippets, isEmpty);
    });

    testWidgets('search filters snippets', (t) async {
      await setSize(t, phone);
      await launch(t);
      await t.tap(find.text('دستورها').last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'htop');
      await t.pumpAndSettle();
      expect(find.text('مانیتور زنده'), findsOneWidget);
      expect(find.text('پورت‌های باز'), findsNothing);
    });
  });

  group('settings', () {
    testWidgets('all settings persist and the terminal uses them', (t) async {
      await setSize(t, phone);
      await launch(t);
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      final st = Store.i.settings;

      await t.tap(find.text('Dracula'));
      await t.pumpAndSettle();
      expect(st.theme, 'Dracula');

      // font slider: drag far toward max (RTL: max is on the left)
      final slider = find.byType(Slider);
      await t.drag(slider, const Offset(-400, 0));
      await t.pumpAndSettle();
      expect(st.fontSize, 30);
      await t.drag(slider, const Offset(60, 0));
      await t.pumpAndSettle();
      final font = st.fontSize;
      expect(font, lessThan(30));
      expect(font, font.roundToDouble());

      await tapText(t, 'شکل نشانگر');
      await tapText(t, 'خط عمودی');
      expect(st.cursor, 'bar');

      await tapText(t, 'بافر ترمینال');
      await tapText(t, '۱۰۰۰۰ خط');
      expect(st.scrollback, 10000);

      await tapText(t, 'لرزش هنگام زنگ');
      expect(st.vibrate, isFalse);
      await tapText(t, 'روشن ماندن صفحه');
      expect(st.wakelock, isFalse);

      await tapText(t, 'Keep alive');
      await tapText(t, '۱۵ ثانیه');
      expect(st.keepAlive, 15);

      // key bar editor
      await tapText(t, 'شخصی‌سازی نوار کلید');
      expect(find.text('نوار کلید'), findsOneWidget);
      final escTile = find.ancestor(of: find.text('esc'), matching: find.byType(ListTile));
      await t.tap(find.descendant(of: escTile, matching: find.byIcon(Icons.remove_circle_outline)));
      await t.pumpAndSettle();
      expect(st.keys.contains('esc'), isFalse);
      await reveal(t, find.widgetWithText(ActionChip, 'pgup'));
      await t.tap(find.widgetWithText(ActionChip, 'pgup'));
      await t.pumpAndSettle();
      expect(st.keys.last, 'pgup');
      // re-adding a removed key
      await reveal(t, find.widgetWithText(ActionChip, 'esc'));
      await t.tap(find.widgetWithText(ActionChip, 'esc'));
      await t.pumpAndSettle();
      expect(st.keys.last, 'esc');
      await back(t);
      await t.pumpAndSettle();
      expect(find.text('${st.keys.length} کلید'), findsOneWidget);

      final want = st.toJson();
      await reloadStore();
      expect(Store.i.settings.toJson(), want);
      expect(Store.i.settings.keys.take(2).toList(), ['tab', 'ctrl']);

      // the terminal picks the settings up
      final h = Host(id: 'x', label: 'x', host: '127.0.0.1', port: 1, user: 'u');
      final s = Sessions.i.open(h);
      expect(s.terminal.maxLines, 10000);
      await launch(t);
      wakelockCalls = 0;
      openSession(t.element(find.byType(Scaffold).first), s);
      await t.pumpAndSettle();
      final view = t.widget<TerminalView>(find.byType(TerminalView));
      expect(view.theme, terminalThemes['Dracula']);
      expect(view.cursorType, TerminalCursorType.verticalBar);
      expect(view.textStyle.fontSize, font);
      expect(wakelockCalls, 0, reason: 'wakelock is off, must not be enabled');
      // key bar follows settings: starts with tab, ctrl; ends with pgup, esc
      final bar = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right).last;
      expect(t.getCenter(find.text('tab')).dx, lessThan(t.getCenter(find.text('ctrl')).dx));
      await t.scrollUntilVisible(find.text('esc'), 100, scrollable: bar);
      expect(find.text('pgup'), findsOneWidget);
      expect(t.getCenter(find.text('pgup')).dx, lessThan(t.getCenter(find.text('esc')).dx));
      await back(t);
      await t.pumpAndSettle();
    });

    testWidgets('font size from the terminal menu is saved', (t) async {
      await setSize(t, phone);
      final s = Sessions.i.open(Host(id: 'x', label: 'x', host: '127.0.0.1', port: 1, user: 'u'));
      await launch(t);
      openSession(t.element(find.byType(Scaffold).first), s);
      await t.pumpAndSettle();
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('بزرگ‌تر کردن فونت'));
      await t.pumpAndSettle();
      expect(Store.i.settings.fontSize, 14);
      expect(t.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize, 14);
      await reloadStore();
      expect(Store.i.settings.fontSize, 14);
    });

    testWidgets('clear known hosts', (t) async {
      await setSize(t, phone);
      await Store.i.trust('1.2.3.4', 22, 'aa');
      await Store.i.trust('5.6.7.8', 22, 'bb');
      await launch(t);
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      await reveal(t, find.text('2 سرور'));
      expect(find.text('2 سرور'), findsOneWidget);
      await tapText(t, 'پاک کردن کلیدهای شناخته‌شده');
      await t.tap(find.widgetWithText(TextButton, 'انصراف'));
      await t.pumpAndSettle();
      expect(Store.i.knownHosts, hasLength(2));
      await tapText(t, 'پاک کردن کلیدهای شناخته‌شده');
      await t.tap(find.widgetWithText(TextButton, 'پاک کن'));
      await t.pumpAndSettle();
      expect(Store.i.knownHosts, isEmpty);
      expect(find.text('0 سرور'), findsOneWidget);
      await reloadStore();
      expect(Store.i.knownHosts, isEmpty);
      // trusting a new key updates the count live
      await launch(t);
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      await Store.i.trust('9.9.9.9', 22, 'cc');
      await t.pumpAndSettle();
      await reveal(t, find.text('پاک کردن کلیدهای شناخته‌شده'));
      expect(find.text('1 سرور'), findsOneWidget);
    });
  });

  group('app lock', () {
    Future<void> pin(WidgetTester t, String p) async {
      for (final d in p.split('')) {
        await t.tap(find.text(d));
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 200));
      await t.pumpAndSettle();
    }

    testWidgets('set PIN, relaunch locked, wrong rejected, right unlocks, disable', (t) async {
      await setSize(t, phone);
      await launch(t);
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      await tapText(t, 'قفل برنامه با PIN');
      expect(find.text('یک PIN چهار رقمی انتخاب کنید'), findsOneWidget);
      await pin(t, '1234');
      expect(find.text('PIN را دوباره وارد کنید'), findsOneWidget);
      await pin(t, '9999'); // mismatch restarts
      expect(find.text('یک PIN چهار رقمی انتخاب کنید'), findsOneWidget);
      expect(find.text('اشتباه بود، دوباره امتحان کنید'), findsOneWidget);
      await pin(t, '1234');
      await pin(t, '1234');
      expect(find.byType(PinPad), findsNothing);
      expect(Store.i.settings.lockEnabled, isTrue);
      expect(Store.i.settings.pinHash, Store.hashPin('1234'));

      // biometrics not available on this device -> stays off
      await tapText(t, 'باز کردن با اثر انگشت');
      expect(Store.i.settings.biometric, isFalse);
      await t.pumpAndSettle(const Duration(seconds: 3));

      // relaunch
      await reloadStore();
      await launch(t);
      expect(find.text('رمز برنامه را وارد کنید'), findsOneWidget);
      expect(find.text('سرورها'), findsNothing);
      await pin(t, '0000');
      expect(find.text('اشتباه بود، دوباره امتحان کنید'), findsOneWidget);
      expect(find.byType(PinPad), findsOneWidget);
      // backspace right after the 4th digit cancels the check instead of failing it
      for (final d in ['1', '2', '3', '9']) {
        await t.tap(find.text(d));
        await t.pump();
      }
      await t.tap(find.byIcon(Icons.backspace_outlined));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('اشتباه بود، دوباره امتحان کنید'), findsNothing);
      await t.tap(find.text('4'));
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.byType(PinPad), findsNothing, reason: '123+4 after correcting must unlock');
      await reloadStore();
      await launch(t);
      // backspace works
      await t.tap(find.text('5'));
      await t.pump();
      await t.tap(find.byIcon(Icons.backspace_outlined));
      await t.pump();
      await pin(t, '1234');
      expect(find.byType(PinPad), findsNothing);
      expect(find.text('سرورها'), findsWidgets);

      // background for longer than lockAfter -> locked again
      Store.i.settings.lockAfter = 0;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.byType(PinPad), findsOneWidget);
      await pin(t, '1234');
      expect(find.byType(PinPad), findsNothing);

      // disable
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      await tapText(t, 'قفل برنامه با PIN');
      expect(Store.i.settings.lockEnabled, isFalse);
      await reloadStore();
      expect(Store.i.settings.pinHash, isEmpty);
      await launch(t);
      expect(find.byType(PinPad), findsNothing);
    });

    testWidgets('closing PIN setup leaves lock off', (t) async {
      await setSize(t, phone);
      await launch(t);
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      await tapText(t, 'قفل برنامه با PIN');
      await t.tap(find.byIcon(Icons.close));
      await t.pumpAndSettle();
      expect(Store.i.settings.lockEnabled, isFalse);
      expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'قفل برنامه با PIN')).value, isFalse);
    });
  });

  group('layout (RTL, no overflow)', () {
    final sizes = {
      'small 360x640': const Size(360, 640),
      'large 412x915': const Size(412, 915),
      'tablet 800x1280': const Size(800, 1280),
      'landscape 640x360': const Size(640, 360),
    };
    const longFa = 'سرور خیلی خیلی طولانی شرکت پارس آنلاین در دیتاسنتر تهران با نام بسیار بلند';

    testWidgets('empty host list + add-host form with keyboard on a small phone', (t) async {
      await setSize(t, const Size(360, 640), keyboard: 320);
      await launch(t);
      expect(find.text('هنوز سروری اضافه نکرده‌اید'), findsOneWidget);
      await t.tap(find.byType(FloatingActionButton).first);
      await t.pumpAndSettle();
      await t.enterText(fieldLabeled('آدرس سرور'), 'x');
      await t.pumpAndSettle();
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('هنوز سروری اضافه نکرده‌اید'), findsOneWidget);
    });

    for (final e in sizes.entries) {
      testWidgets('every screen fits on ${e.key}', (t) async {
        await setSize(t, e.value, dpr: e.value.width > 700 ? 1 : 3);
        final kb = e.value.height > 500 ? 300.0 : 170.0; // soft keyboard height
        await loadFonts();
        // let the "system fonts changed" message arrive and relayout before the screens are built
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
        await Store.i.upsertHost(
            Host(id: 'a', label: longFa, host: 'very-long-subdomain.example-hosting-provider.com', port: 65535,
                user: 'administrator_account'),
            HostSecret(password: 'x'));
        await Store.i.upsertSnippet(Snippet(id: 'l', name: longFa, cmd: 'docker compose -f /opt/stack/docker-compose.production.yml up -d --force-recreate'));
        final s = Sessions.i.open(Store.i.hosts.first);
        s.error = longFa;
        s.status = SessStatus.failed;
        await launch(t);
        expect(find.text('نشست‌های باز'), findsOneWidget);

        await t.tap(find.text('دستورها').last);
        await t.pumpAndSettle();
        await t.tap(find.byType(FloatingActionButton).last);
        await t.pumpAndSettle();
        t.view.viewInsets = FakeViewPadding(bottom: kb * t.view.devicePixelRatio);
        await t.pumpAndSettle();
        t.view.resetViewInsets();
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();

        await t.tap(find.text('تنظیمات').last);
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, -2000));
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, 2000));
        await t.pumpAndSettle();
        await tapText(t, 'بافر ترمینال');
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        await tapText(t, 'شخصی‌سازی نوار کلید');
        await back(t);
        await t.pumpAndSettle();
        await tapText(t, 'قفل برنامه با PIN');
        expect(find.byType(PinPad), findsOneWidget);
        await t.tap(find.byIcon(Icons.close));
        await t.pumpAndSettle();

        // host edit, both auth modes, with keyboard up
        await t.tap(find.text('سرورها').last);
        await t.pumpAndSettle();
        await t.tap(find.byType(FloatingActionButton).first);
        await t.pumpAndSettle();
        t.view.viewInsets = FakeViewPadding(bottom: kb * t.view.devicePixelRatio);
        await t.pumpAndSettle();
        await reveal(t, find.text('کلید SSH'));
        await t.tap(find.text('کلید SSH'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(TextButton, 'ذخیره'));
        await t.pumpAndSettle();
        await back(t);
        await t.pumpAndSettle();

        // terminal with failed banner, keyboard up
        await t.tap(find.text(longFa).first);
        await t.pumpAndSettle();
        expect(find.byType(TerminalView), findsOneWidget);
        expect(find.text('اتصال دوباره'), findsOneWidget);
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('دستورها'));
        await t.pumpAndSettle();
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        // host key dialogs
        final changed = hostKeyPrompt('ssh-ed25519', List.filled(32, 'ab').join(':'), 'old');
        await t.pumpAndSettle();
        expect(find.text('کلید سرور عوض شده!'), findsOneWidget);
        await t.tap(find.text('رد کردن'));
        await t.pumpAndSettle();
        expect(await changed, isFalse);
        await back(t);
        await t.pumpAndSettle();

        // lock screen
        Store.i.settings
          ..lockEnabled = true
          ..pinHash = Store.hashPin('1111');
        await launch(t);
        expect(find.byType(PinPad), findsOneWidget);
        Store.i.settings
          ..lockEnabled = false
          ..pinHash = '';
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      });
    }
  });
}
