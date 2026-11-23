// End-to-end UI flows that need no SSH server (run in CI).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mterm/builtin_commands.dart';
import 'package:mterm/l10n.dart';
import 'package:mterm/main.dart';
import 'package:mterm/models.dart';
import 'package:mterm/screens/common.dart';
import 'package:mterm/screens/lock_screen.dart';
import 'package:mterm/screens/quick_connect.dart';
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

/// Scrolls [f] to the middle of its list (clear of the floating action button).
Future<void> center(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  Scrollable.ensureVisible(t.element(f), alignment: 0.4);
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

      await t.tap(find.byKey(const ValueKey('fab-add-host')));
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
      await t.tap(find.byKey(const ValueKey('fab-add-host')));
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
      await center(t, find.text('ری‌استارت وب'));
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
      await center(t, find.text('ری‌استارت وب'));
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

      // the colour-scheme strip scrolls horizontally ('Auto' comes first)
      final strip = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection != AxisDirection.down).first;
      await t.scrollUntilVisible(find.text('Dracula'), 80, scrollable: strip);
      await t.pumpAndSettle();
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
      await t.tap(find.byKey(const ValueKey('fab-add-host')));
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
        await t.tap(find.byKey(const ValueKey('fab-add-host')));
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

  group('appearance & language', () {
    testWidgets('language switches live, with the right direction, and persists', (t) async {
      await setSize(t, phone);
      await launch(t);
      expect(Directionality.of(t.element(find.byType(HomeShell))), TextDirection.rtl);
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      await tapText(t, 'زبان');
      await tapText(t, 'English', last: true);
      expect(Store.i.settings.language, 'en');
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Servers'), findsWidgets);
      expect(find.text('Appearance'), findsOneWidget);
      expect(Directionality.of(t.element(find.byType(HomeShell))), TextDirection.ltr);

      await tapText(t, 'Language');
      await tapText(t, 'Deutsch', last: true);
      expect(find.text('Einstellungen'), findsWidgets);

      await tapText(t, 'Sprache');
      await tapText(t, 'العربية', last: true);
      expect(find.text('الإعدادات'), findsWidgets);
      expect(Directionality.of(t.element(find.byType(HomeShell))), TextDirection.rtl);

      await reloadStore();
      expect(Store.i.settings.language, 'ar');

      // "System" follows the device (en_US in tests)
      await tapText(t, 'اللغة');
      await tapText(t, 'لغة النظام', last: true);
      expect(Store.i.settings.language, 'system');
      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets('theme switches live between dark and light', (t) async {
      await setSize(t, phone);
      await launch(t);
      Brightness b() => Theme.of(t.element(find.byType(HomeShell))).brightness;
      await t.tap(find.text('تنظیمات').last);
      await t.pumpAndSettle();
      await tapText(t, 'پوسته');
      await tapText(t, 'تیره');
      expect(Store.i.settings.appTheme, 'dark');
      expect(b(), Brightness.dark);
      expect(t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
      await tapText(t, 'پوسته');
      await tapText(t, 'روشن', last: true);
      expect(b(), Brightness.light);
      expect(Theme.of(t.element(find.byType(HomeShell))).scaffoldBackgroundColor, Palette.light.bg);
      await reloadStore();
      expect(Store.i.settings.appTheme, 'light');
      // the terminal's Auto scheme follows the app mode
      expect(terminalThemeFor('Auto', Brightness.light), terminalThemes['Light']);
      expect(terminalThemeFor('Auto', Brightness.dark), terminalThemes['Termius']);
    });
  });

  group('ready commands', () {
    Future<void> openReady(WidgetTester t) async {
      await t.tap(find.text('دستورها').last);
      await t.pumpAndSettle();
      await t.tap(find.text('دستورهای آماده'));
      await t.pumpAndSettle();
    }

    testWidgets('grouped, copy and save to my commands; not deletable', (t) async {
      await setSize(t, phone);
      await launch(t);
      await openReady(t);
      expect(find.text('سرور'), findsWidgets);
      expect(find.text(builtinCommands.first.cmd), findsOneWidget);
      final before = Store.i.snippets.length;

      final bbr = builtinCommands.firstWhere((c) => c.id == 'bbr');
      await reveal(t, find.byKey(const ValueKey('builtin-bbr')));
      await t.tap(find.byKey(const ValueKey('builtin-bbr')));
      await t.pumpAndSettle();
      await t.tap(find.text('کپی'));
      await t.pumpAndSettle();
      expect(clipboard, bbr.cmd);

      await t.tap(find.byKey(const ValueKey('builtin-bbr')));
      await t.pumpAndSettle();
      await t.tap(find.text('ذخیره در دستورهای من'));
      await t.pumpAndSettle();
      expect(Store.i.snippets.length, before + 1);
      expect(Store.i.snippets.last.cmd, bbr.cmd);
      expect(Store.i.snippets.last.name, 'فعال‌سازی BBR');

      // long-press only shows the same actions: no editor, no delete for built-ins
      await t.longPress(find.byKey(const ValueKey('builtin-bbr')));
      await t.pumpAndSettle();
      expect(find.text('ویرایش دستور'), findsNothing);
      expect(find.text('حذف'), findsNothing);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      // search covers the library (back at the top of the list)
      final list = find.ancestor(of: find.byKey(const ValueKey('builtin-bbr')), matching: find.byType(Scrollable));
      await t.drag(list.first, const Offset(0, 3000));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'marzban');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('builtin-marzbanMysql')), findsOneWidget);
      expect(find.byKey(const ValueKey('builtin-update')), findsNothing);
    });

    testWidgets('installers and reboot ask before running', (t) async {
      await setSize(t, phone);
      final h = Host(id: 'x', label: 'لوکال', host: '127.0.0.1', port: 1, user: 'u');
      final s = Sessions.i.open(h);
      s.status = SessStatus.connected; // fake a live session (no shell: run() writes nothing)
      await launch(t);
      await openReady(t);
      await reveal(t, find.byKey(const ValueKey('builtin-reboot')));
      await t.tap(find.byKey(const ValueKey('builtin-reboot')));
      await t.pumpAndSettle();
      await t.tap(find.text('اجرا'));
      await t.pumpAndSettle();
      expect(find.text('این دستور اجرا شود؟'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'انصراف'));
      await t.pumpAndSettle();
      expect(find.byType(TerminalView), findsNothing);
      expect(s.typed, isEmpty);

      await t.tap(find.byKey(const ValueKey('builtin-reboot')));
      await t.pumpAndSettle();
      await t.tap(find.text('اجرا'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'اجرا'));
      await t.pumpAndSettle();
      expect(find.byType(TerminalView), findsOneWidget);
      expect(s.typed.first, 'sudo reboot');
      await back(t);

      // a harmless server command runs without asking
      await reveal(t, find.byKey(const ValueKey('builtin-sysinfo')));
      await t.tap(find.byKey(const ValueKey('builtin-sysinfo')));
      await t.pumpAndSettle();
      await t.tap(find.text('اجرا'));
      await t.pumpAndSettle();
      expect(find.text('این دستور اجرا شود؟'), findsNothing);
      expect(s.typed.first, 'free -h && df -h && uptime');
      await back(t);
      s.status = SessStatus.closed;
    });
  });

  group('password prompt', () {
    testWidgets('remember is on by default; returns what was typed', (t) async {
      await setSize(t, phone);
      await launch(t);
      final h = Host(id: 'p', label: 'p', host: '10.0.0.1', user: 'root');
      var r = passwordPrompt(h, wrong: true);
      await t.pumpAndSettle();
      expect(find.text('رمز سرور'), findsOneWidget);
      expect(find.text('رمز اشتباه بود، دوباره وارد کنید'), findsOneWidget);
      expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
      await t.enterText(find.byKey(const ValueKey('pw-field')), 'n3w-pass');
      await t.tap(find.widgetWithText(TextButton, 'اتصال'));
      await t.pumpAndSettle();
      final a = await r;
      expect(a?.password, 'n3w-pass');
      expect(a?.remember, isTrue);

      r = passwordPrompt(h);
      await t.pumpAndSettle();
      expect(find.text('رمز اشتباه بود، دوباره وارد کنید'), findsNothing);
      await t.enterText(find.byKey(const ValueKey('pw-field')), 'once');
      await t.tap(find.text('رمز را به خاطر بسپار'));
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      final b = await r;
      expect(b?.password, 'once');
      expect(b?.remember, isFalse);

      r = passwordPrompt(h);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'انصراف'));
      await t.pumpAndSettle();
      expect(await r, isNull);
    });

    test('savePassword replaces the stored password under the same key', () async {
      await Store.i.upsertHost(Host(id: 'q', label: 'q', host: 'h', user: 'u'), HostSecret(password: 'old'));
      expect(secure['pw_q'], 'old');
      await Store.i.savePassword('q', 'new');
      expect(secure['pw_q'], 'new');
      expect((await Store.i.secret('q')).password, 'new');
    });
  });

  group('layout in every language (no overflow)', () {
    for (final lang in ['en', 'ar', 'tr', 'ru', 'de', 'fr', 'es', 'zh']) {
      testWidgets('main screens fit on a small phone in $lang', (t) async {
        await setSize(t, const Size(360, 640));
        Store.i.settings
          ..language = lang
          ..appTheme = lang.hashCode.isEven ? 'light' : 'dark';
        await Store.i.saveSettings();
        await Store.i.upsertHost(Host(id: 'a', label: 'srv', host: 'example.com', user: 'root'), HostSecret());
        final s = Sessions.i.open(Store.i.hosts.first);
        s
          ..status = SessStatus.failed
          ..errorKey = 'errUnreachable'
          ..errorArg = 'Network is unreachable';
        await launch(t);
        final nav = find.byType(NavigationDestination);
        await t.tap(nav.at(1));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.auto_awesome).first); // "Ready commands" segment
        await t.pumpAndSettle();
        final lib = find.descendant(of: find.byKey(const ValueKey('snippets-list')), matching: find.byType(Scrollable));
        await t.scrollUntilVisible(find.byKey(const ValueKey('builtin-backpackMenu')), 200, scrollable: lib.first);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('builtin-backpackMenu')));
        await t.pumpAndSettle();
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        await t.tap(nav.at(2));
        await t.pumpAndSettle();
        await t.drag(_vScroll.last, const Offset(0, -3000));
        await t.pumpAndSettle();
        await t.tap(nav.at(0));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('fab-add-host')));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.key));
        await t.pumpAndSettle();
        await back(t);
        await t.tap(find.text('srv').first); // the open (failed) session
        await t.pumpAndSettle();
        expect(find.byType(TerminalView), findsOneWidget);
        await back(t);
        final pw = passwordPrompt(Store.i.hosts.first, wrong: true);
        await t.pumpAndSettle();
        await t.tap(find.byType(TextButton).first);
        await t.pumpAndSettle();
        expect(await pw, isNull);
      });
    }
  });

  group('quick connect', () {
    Future<void> openForm(WidgetTester t, {String via = 'quick-connect'}) async {
      await t.tap(find.byKey(ValueKey(via)));
      await t.pumpAndSettle();
      expect(find.byType(QuickConnectDialog), findsOneWidget);
    }

    testWidgets('opens from app bar, FAB and empty list; validates like the host form', (t) async {
      await setSize(t, phone);
      await launch(t);
      expect(find.byTooltip('اتصال سریع'), findsWidgets);

      await openForm(t, via: 'empty-quick-connect');
      expect(find.text('اتصال سریع'), findsWidgets);
      await t.tap(find.text('انصراف'));
      await t.pumpAndSettle();
      expect(find.byType(QuickConnectDialog), findsNothing);
      await openForm(t, via: 'fab-quick-connect');
      await t.tap(find.text('انصراف'));
      await t.pumpAndSettle();
      await openForm(t);

      // defaults: port 22, user root, password hidden
      expect(t.widget<TextFormField>(find.byKey(const ValueKey('qc-port'))).controller!.text, '22');
      expect(t.widget<TextFormField>(find.byKey(const ValueKey('qc-user'))).controller!.text, 'root');
      EditableText pwField() =>
          t.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('qc-password')), matching: find.byType(EditableText)));
      expect(pwField().obscureText, isTrue);
      await t.tap(find.byKey(const ValueKey('qc-show-pw')));
      await t.pump();
      expect(pwField().obscureText, isFalse);

      // empty address, bad port, empty user: errors, nothing opens
      await t.enterText(find.byKey(const ValueKey('qc-port')), '70000');
      await t.enterText(find.byKey(const ValueKey('qc-user')), ' ');
      await t.tap(find.byKey(const ValueKey('qc-connect')));
      await t.pumpAndSettle();
      expect(find.text('آدرس را وارد کنید'), findsOneWidget);
      expect(find.text('نامعتبر'), findsOneWidget);
      expect(find.text('نام کاربری را وارد کنید'), findsOneWidget);
      expect(Sessions.i.list, isEmpty);
      await t.enterText(find.byKey(const ValueKey('qc-port')), '0');
      await t.tap(find.byKey(const ValueKey('qc-connect')));
      await t.pumpAndSettle();
      expect(find.text('نامعتبر'), findsOneWidget);
      expect(find.byType(QuickConnectDialog), findsOneWidget);
    });

    testWidgets('connects without saving anything (refused port)', (t) async {
      await setSize(t, phone);
      await launch(t);
      await openForm(t);
      await t.enterText(find.byKey(const ValueKey('qc-host')), ' 127.0.0.1 ');
      await t.enterText(find.byKey(const ValueKey('qc-port')), '1');
      await t.enterText(find.byKey(const ValueKey('qc-user')), 'admin');
      await t.enterText(find.byKey(const ValueKey('qc-password')), 'pw-1');
      await t.tap(find.byKey(const ValueKey('qc-connect')));
      await t.pump();
      final s = Sessions.i.list.single;
      expect(s.transient, isTrue);
      expect(s.host.host, '127.0.0.1');
      expect(s.host.port, 1);
      expect(s.host.user, 'admin');
      await waitFor(t, () => s.status == SessStatus.failed, reason: 'refused');
      await t.pumpAndSettle();
      expect(find.byType(TerminalView), findsOneWidget);
      expect(Store.i.hosts, isEmpty);
      expect(secure.keys.where((k) => k.startsWith('pw_')), isEmpty);
      expect(find.text('این سرور ذخیره شود؟'), findsNothing, reason: 'only offered after a login');
      await back(t);
      // shown under open sessions only
      expect(find.text('127.0.0.1'), findsOneWidget);
      await closeAll(t);
    });

    testWidgets('after login: Save stores host + password, it shows in the list', (t) async {
      await setSize(t, phone);
      await launch(t);
      final h = Host(id: 'qc1', label: '', host: '10.1.2.3', port: 2200, user: 'root');
      final s = Sessions.i.open(h, transient: true, password: 'typed-pw');
      openSession(navKey.currentContext!, s);
      await t.pumpAndSettle();
      expect(find.text('این سرور ذخیره شود؟'), findsNothing);
      // menu offers saving while the session is transient
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      expect(find.text('ذخیرهٔ این سرور'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      s.debugSetStatus(SessStatus.connected);
      await t.pumpAndSettle();
      expect(find.text('این سرور ذخیره شود؟'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('save-server-yes')));
      await t.pumpAndSettle();
      expect(find.text('سرور ذخیره شد'), findsOneWidget);
      expect(s.transient, isFalse);
      expect(Store.i.hosts.single.label, '10.1.2.3');
      expect(Store.i.hosts.single.port, 2200);
      expect(secure['pw_qc1'], 'typed-pw');
      // offered only once, menu item gone
      s.debugSetStatus(SessStatus.connected);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.text('این سرور ذخیره شود؟'), findsNothing);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      expect(find.text('ذخیرهٔ این سرور'), findsNothing);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await back(t);
      expect(find.text('10.1.2.3'), findsNWidgets(2)); // open session + saved host
      // survives a relaunch
      await reloadStore();
      expect(Store.i.hosts.single.host, '10.1.2.3');
      expect((await Store.i.secret('qc1')).password, 'typed-pw');
      await closeAll(t);
    });

    testWidgets('Not now saves nothing; Save from the menu later still works', (t) async {
      await setSize(t, phone);
      await launch(t);
      final s = Sessions.i.open(Host(id: 'qc2', label: '', host: '10.9.9.9', user: 'root'), transient: true);
      openSession(navKey.currentContext!, s);
      await t.pumpAndSettle();
      s.debugSetStatus(SessStatus.connected);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('save-server-later')));
      await t.pumpAndSettle();
      expect(find.text('این سرور ذخیره شود؟'), findsNothing);
      expect(Store.i.hosts, isEmpty);
      expect(secure, isEmpty);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('ذخیرهٔ این سرور'));
      await t.pumpAndSettle();
      expect(Store.i.hosts.single.label, '10.9.9.9');
      expect(secure['pw_qc2'], '', reason: 'no password was typed');
      await t.pump(const Duration(seconds: 3));
      await closeAll(t);
    });

    for (final lang in languageCodes) {
      testWidgets('form and save prompt fit a small phone with keyboard in $lang', (t) async {
        await setSize(t, const Size(360, 640), keyboard: 300);
        Store.i.settings.language = lang;
        await Store.i.saveSettings();
        await loadFonts();
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await launch(t);
        expect(Directionality.of(t.element(find.byKey(const ValueKey('quick-connect')))),
            rtlLanguages.contains(lang) ? TextDirection.rtl : TextDirection.ltr);
        await openForm(t);
        await t.enterText(find.byKey(const ValueKey('qc-port')), '');
        await t.enterText(find.byKey(const ValueKey('qc-user')), '');
        await t.tap(find.byKey(const ValueKey('qc-connect')));
        await t.pumpAndSettle();
        expect(find.byType(QuickConnectDialog), findsOneWidget);
        await t.tap(find.byType(TextButton).first); // cancel
        await t.pumpAndSettle();
        t.view.resetViewInsets();
        final s = Sessions.i.open(Host(id: 'q$lang', label: '', host: '203.0.113.200', user: 'root'), transient: true);
        openSession(navKey.currentContext!, s);
        await t.pumpAndSettle();
        s.debugSetStatus(SessStatus.connected);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('save-server-snack')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('save-server-later')));
        await t.pumpAndSettle();
        await closeAll(t);
      });
    }
  });
}
