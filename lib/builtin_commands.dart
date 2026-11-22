// Built-in, read-only command library shown under "Ready commands" in the
// Commands tab. These are never stored with the user's snippets and cannot be
// edited or deleted. Commands are kept byte-for-byte as published in each
// project's official README; only titles/descriptions are translated.
//
// Pure Dart (no Flutter imports) so tool/check_l10n.dart can verify it.

class BuiltinCommand {
  const BuiltinCommand(this.id, this.category, this.cmd, {this.confirm = false});
  final String id;

  /// One of [builtinCategories].
  final String category;
  final String cmd;

  /// Installers and reboot: ask before running.
  final bool confirm;
}

const List<String> builtinCategories = ['server', 'panels', 'tunnels'];

const List<BuiltinCommand> builtinCommands = [
  // ---- server
  BuiltinCommand('update', 'server', r'sudo apt update && sudo apt upgrade -y'),
  BuiltinCommand('fullUpgrade', 'server',
      r'sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt autoclean'),
  BuiltinCommand('reboot', 'server', r'sudo reboot', confirm: true),
  BuiltinCommand('sysinfo', 'server', r'free -h && df -h && uptime'),
  BuiltinCommand('bbr', 'server',
      r'echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf && echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf && sudo sysctl -p'),
  BuiltinCommand('ports', 'server', r'sudo ss -tulpn'),
  BuiltinCommand('tools', 'server', r'sudo apt install -y curl wget nano htop unzip socat'),
  // ---- panels
  BuiltinCommand(
      'xui', 'panels', r'bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)',
      confirm: true),
  BuiltinCommand('xuiMenu', 'panels', r'x-ui', confirm: true),
  BuiltinCommand('marzbanSqlite', 'panels',
      r'sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install',
      confirm: true),
  BuiltinCommand('marzbanMysql', 'panels',
      r'sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install --database mysql',
      confirm: true),
  BuiltinCommand('marzbanAdmin', 'panels', r'marzban cli admin create --sudo', confirm: true),
  // ---- tunnels
  BuiltinCommand('kariz', 'tunnels',
      r'bash <(curl -fsSL https://raw.githubusercontent.com/Erfan-XRay/Kariz/main/scripts/kariz.sh)',
      confirm: true),
  BuiltinCommand('karizPanel', 'tunnels', r'kariz-manager panel install', confirm: true),
  BuiltinCommand(
      'backpack', 'tunnels', r'bash <(curl -fsSL https://raw.githubusercontent.com/AminMGMT/BackPack/main/install.sh)',
      confirm: true),
  BuiltinCommand('backpackMenu', 'tunnels', r'sudo backpack', confirm: true),
];

/// Category names per language.
const Map<String, Map<String, String>> builtinCategoryNames = {
  'en': {'server': 'Server', 'panels': 'Panels', 'tunnels': 'Tunnels'},
  'fa': {'server': 'سرور', 'panels': 'پنل‌ها', 'tunnels': 'تانل‌ها'},
  'ar': {'server': 'الخادم', 'panels': 'اللوحات', 'tunnels': 'الأنفاق'},
  'tr': {'server': 'Sunucu', 'panels': 'Paneller', 'tunnels': 'Tüneller'},
  'ru': {'server': 'Сервер', 'panels': 'Панели', 'tunnels': 'Туннели'},
  'de': {'server': 'Server', 'panels': 'Panels', 'tunnels': 'Tunnel'},
  'fr': {'server': 'Serveur', 'panels': 'Panneaux', 'tunnels': 'Tunnels'},
  'es': {'server': 'Servidor', 'panels': 'Paneles', 'tunnels': 'Túneles'},
  'zh': {'server': '服务器', 'panels': '面板', 'tunnels': '隧道'},
};

/// [title, one-line description] per command id, per language.
const Map<String, Map<String, List<String>>> builtinText = {
  'en': {
    'update': ['Update server (Ubuntu/Debian)', 'Refreshes package lists and installs available updates.'],
    'fullUpgrade': ['Full upgrade + cleanup', 'Full upgrade, then removes unused packages and cached files.'],
    'reboot': ['Reboot', 'Restarts the server; the connection will drop.'],
    'sysinfo': ['System info (RAM/disk/uptime)', 'Shows memory, disk usage and how long the server has been up.'],
    'bbr': ['Enable BBR', 'Turns on Google BBR congestion control for faster connections.'],
    'ports': ['Open ports in use', 'Lists listening ports and the programs using them.'],
    'tools': ['Install basic tools', 'Installs curl, wget, nano, htop, unzip and socat.'],
    'xui': ['3X-UI (Sanaei)', 'Installs or updates the 3X-UI panel.'],
    'xuiMenu': ['3X-UI management menu', 'Opens the 3X-UI menu (start, stop, settings, logs).'],
    'marzbanSqlite': ['Marzban (SQLite)', 'Installs Marzban with the default SQLite database.'],
    'marzbanMysql': ['Marzban (MySQL)', 'Installs Marzban with a MySQL database.'],
    'marzbanAdmin': ['Marzban: create sudo admin', 'Creates a full-access admin account for the Marzban panel.'],
    'kariz': ['Kariz install / menu', 'Installs Kariz or opens its tunnel management menu.'],
    'karizPanel': ['Kariz web panel install', 'Installs the Kariz web management panel.'],
    'backpack': ['BackPack install', 'Installs BackPack; run it on both servers.'],
    'backpackMenu': ['BackPack menu', 'Opens the BackPack tunnel menu.'],
  },
  'fa': {
    'update': [
      'آپدیت سرور (\u2066Ubuntu/Debian\u2069)',
      'فهرست بسته‌ها را تازه می‌کند و به‌روزرسانی‌ها را نصب می‌کند.'
    ],
    'fullUpgrade': ['ارتقای کامل + پاک‌سازی', 'ارتقای کامل سیستم و حذف بسته‌ها و فایل‌های اضافی.'],
    'reboot': ['ری‌استارت سرور', 'سرور را دوباره راه‌اندازی می‌کند؛ اتصال قطع می‌شود.'],
    'sysinfo': ['اطلاعات سیستم (رم/دیسک/آپتایم)', 'مصرف رم و دیسک و مدت روشن بودن سرور را نشان می‌دهد.'],
    'bbr': ['فعال‌سازی BBR', 'الگوریتم BBR گوگل را برای اتصال سریع‌تر روشن می‌کند.'],
    'ports': ['پورت‌های باز در حال استفاده', 'پورت‌های در حال شنود و برنامه‌های آن‌ها را نشان می‌دهد.'],
    'tools': ['نصب ابزارهای پایه', 'curl، wget، nano، htop، unzip و socat را نصب می‌کند.'],
    'xui': ['3X-UI (ثنایی)', 'پنل 3X-UI را نصب یا به‌روز می‌کند.'],
    'xuiMenu': ['منوی مدیریت 3X-UI', 'منوی 3X-UI را باز می‌کند (شروع، توقف، تنظیمات، لاگ).'],
    'marzbanSqlite': ['مرزبان (SQLite)', 'مرزبان را با دیتابیس پیش‌فرض SQLite نصب می‌کند.'],
    'marzbanMysql': ['مرزبان (MySQL)', 'مرزبان را با دیتابیس MySQL نصب می‌کند.'],
    'marzbanAdmin': ['مرزبان: ساخت ادمین sudo', 'یک ادمین با دسترسی کامل برای پنل مرزبان می‌سازد.'],
    'kariz': ['کاریز: نصب / منو', 'کاریز را نصب می‌کند یا منوی مدیریت تانل را باز می‌کند.'],
    'karizPanel': ['نصب پنل وب کاریز', 'پنل مدیریت تحت وب کاریز را نصب می‌کند.'],
    'backpack': ['نصب بک‌پک', 'بک‌پک را نصب می‌کند؛ روی هر دو سرور اجرا کنید.'],
    'backpackMenu': ['منوی بک‌پک', 'منوی مدیریت تانل بک‌پک را باز می‌کند.'],
  },
  'ar': {
    'update': ['تحديث الخادم (\u2066Ubuntu/Debian\u2069)', 'يحدّث قوائم الحزم ويثبّت التحديثات المتاحة.'],
    'fullUpgrade': ['ترقية كاملة + تنظيف', 'ترقية كاملة للنظام ثم حذف الحزم والملفات غير المستخدمة.'],
    'reboot': ['إعادة التشغيل', 'يعيد تشغيل الخادم؛ سينقطع الاتصال.'],
    'sysinfo': ['معلومات النظام (الذاكرة/القرص/مدة التشغيل)', 'يعرض استخدام الذاكرة والقرص ومدة تشغيل الخادم.'],
    'bbr': ['تفعيل BBR', 'يفعّل خوارزمية BBR من Google لاتصال أسرع.'],
    'ports': ['المنافذ المفتوحة المستخدمة', 'يعرض المنافذ المستمعة والبرامج التي تستخدمها.'],
    'tools': ['تثبيت الأدوات الأساسية', 'يثبّت curl وwget وnano وhtop وunzip وsocat.'],
    'xui': ['3X-UI (Sanaei)', 'يثبّت لوحة 3X-UI أو يحدّثها.'],
    'xuiMenu': ['قائمة إدارة 3X-UI', 'يفتح قائمة 3X-UI (تشغيل، إيقاف، إعدادات، سجلات).'],
    'marzbanSqlite': ['Marzban (SQLite)', 'يثبّت Marzban مع قاعدة بيانات SQLite الافتراضية.'],
    'marzbanMysql': ['Marzban (MySQL)', 'يثبّت Marzban مع قاعدة بيانات MySQL.'],
    'marzbanAdmin': ['Marzban: إنشاء مشرف sudo', 'ينشئ حساب مشرف بصلاحيات كاملة للوحة Marzban.'],
    'kariz': ['Kariz: تثبيت / قائمة', 'يثبّت Kariz أو يفتح قائمة إدارة الأنفاق.'],
    'karizPanel': ['تثبيت لوحة Kariz على الويب', 'يثبّت لوحة الإدارة على الويب لـ Kariz.'],
    'backpack': ['تثبيت BackPack', 'يثبّت BackPack؛ شغّله على كلا الخادمين.'],
    'backpackMenu': ['قائمة BackPack', 'يفتح قائمة أنفاق BackPack.'],
  },
  'tr': {
    'update': ['Sunucuyu güncelle (Ubuntu/Debian)', 'Paket listelerini yeniler ve mevcut güncellemeleri kurar.'],
    'fullUpgrade': [
      'Tam yükseltme + temizlik',
      'Tam yükseltme yapar, ardından kullanılmayan paketleri ve önbelleği siler.'
    ],
    'reboot': ['Yeniden başlat', 'Sunucuyu yeniden başlatır; bağlantı kopar.'],
    'sysinfo': [
      'Sistem bilgisi (RAM/disk/çalışma süresi)',
      'Bellek ve disk kullanımını, sunucunun ne kadar süredir açık olduğunu gösterir.'
    ],
    'bbr': ["BBR'yi etkinleştir", 'Daha hızlı bağlantı için Google BBR tıkanıklık kontrolünü açar.'],
    'ports': ['Kullanımdaki açık portlar', 'Dinlenen portları ve bunları kullanan programları listeler.'],
    'tools': ['Temel araçları kur', 'curl, wget, nano, htop, unzip ve socat kurar.'],
    'xui': ['3X-UI (Sanaei)', '3X-UI panelini kurar veya günceller.'],
    'xuiMenu': ['3X-UI yönetim menüsü', '3X-UI menüsünü açar (başlat, durdur, ayarlar, günlükler).'],
    'marzbanSqlite': ['Marzban (SQLite)', "Marzban'ı varsayılan SQLite veritabanıyla kurar."],
    'marzbanMysql': ['Marzban (MySQL)', "Marzban'ı MySQL veritabanıyla kurar."],
    'marzbanAdmin': [
      'Marzban: sudo yönetici oluştur',
      'Marzban paneli için tam yetkili bir yönetici hesabı oluşturur.'
    ],
    'kariz': ['Kariz kurulum / menü', "Kariz'i kurar veya tünel yönetim menüsünü açar."],
    'karizPanel': ['Kariz web paneli kurulumu', 'Kariz web yönetim panelini kurar.'],
    'backpack': ['BackPack kurulumu', "BackPack'i kurar; her iki sunucuda da çalıştırın."],
    'backpackMenu': ['BackPack menüsü', 'BackPack tünel menüsünü açar.'],
  },
  'ru': {
    'update': ['Обновить сервер (Ubuntu/Debian)', 'Обновляет списки пакетов и устанавливает доступные обновления.'],
    'fullUpgrade': [
      'Полное обновление + очистка',
      'Полное обновление системы, затем удаление ненужных пакетов и кэша.'
    ],
    'reboot': ['Перезагрузка', 'Перезагружает сервер; соединение прервётся.'],
    'sysinfo': [
      'Сведения о системе (RAM/диск/аптайм)',
      'Показывает использование памяти и диска и время работы сервера.'
    ],
    'bbr': ['Включить BBR', 'Включает управление перегрузкой Google BBR для более быстрых соединений.'],
    'ports': ['Открытые порты', 'Показывает прослушиваемые порты и использующие их программы.'],
    'tools': ['Установить базовые утилиты', 'Устанавливает curl, wget, nano, htop, unzip и socat.'],
    'xui': ['3X-UI (Sanaei)', 'Устанавливает или обновляет панель 3X-UI.'],
    'xuiMenu': ['Меню управления 3X-UI', 'Открывает меню 3X-UI (запуск, остановка, настройки, логи).'],
    'marzbanSqlite': ['Marzban (SQLite)', 'Устанавливает Marzban с базой данных SQLite по умолчанию.'],
    'marzbanMysql': ['Marzban (MySQL)', 'Устанавливает Marzban с базой данных MySQL.'],
    'marzbanAdmin': ['Marzban: создать sudo-админа', 'Создаёт администратора с полным доступом к панели Marzban.'],
    'kariz': ['Kariz: установка / меню', 'Устанавливает Kariz или открывает меню управления туннелями.'],
    'karizPanel': ['Установка веб-панели Kariz', 'Устанавливает веб-панель управления Kariz.'],
    'backpack': ['Установка BackPack', 'Устанавливает BackPack; запустите на обоих серверах.'],
    'backpackMenu': ['Меню BackPack', 'Открывает меню туннелей BackPack.'],
  },
  'de': {
    'update': [
      'Server aktualisieren (Ubuntu/Debian)',
      'Aktualisiert die Paketlisten und installiert verfügbare Updates.'
    ],
    'fullUpgrade': [
      'Vollständiges Upgrade + Aufräumen',
      'Vollständiges Upgrade, danach werden ungenutzte Pakete und Cache entfernt.'
    ],
    'reboot': ['Neustart', 'Startet den Server neu; die Verbindung wird getrennt.'],
    'sysinfo': [
      'Systeminfo (RAM/Festplatte/Laufzeit)',
      'Zeigt Speicher- und Festplattennutzung sowie die Laufzeit des Servers.'
    ],
    'bbr': ['BBR aktivieren', 'Aktiviert Googles BBR-Staukontrolle für schnellere Verbindungen.'],
    'ports': ['Offene Ports', 'Listet lauschende Ports und die zugehörigen Programme auf.'],
    'tools': ['Basis-Tools installieren', 'Installiert curl, wget, nano, htop, unzip und socat.'],
    'xui': ['3X-UI (Sanaei)', 'Installiert oder aktualisiert das 3X-UI-Panel.'],
    'xuiMenu': ['3X-UI-Verwaltungsmenü', 'Öffnet das 3X-UI-Menü (Start, Stopp, Einstellungen, Logs).'],
    'marzbanSqlite': ['Marzban (SQLite)', 'Installiert Marzban mit der Standard-SQLite-Datenbank.'],
    'marzbanMysql': ['Marzban (MySQL)', 'Installiert Marzban mit einer MySQL-Datenbank.'],
    'marzbanAdmin': [
      'Marzban: sudo-Admin anlegen',
      'Legt ein Admin-Konto mit vollen Rechten für das Marzban-Panel an.'
    ],
    'kariz': ['Kariz installieren / Menü', 'Installiert Kariz oder öffnet das Tunnel-Verwaltungsmenü.'],
    'karizPanel': ['Kariz-Webpanel installieren', 'Installiert das Web-Verwaltungspanel von Kariz.'],
    'backpack': ['BackPack installieren', 'Installiert BackPack; auf beiden Servern ausführen.'],
    'backpackMenu': ['BackPack-Menü', 'Öffnet das Tunnel-Menü von BackPack.'],
  },
  'fr': {
    'update': [
      'Mettre à jour le serveur (Ubuntu/Debian)',
      'Actualise la liste des paquets et installe les mises à jour disponibles.'
    ],
    'fullUpgrade': [
      'Mise à niveau complète + nettoyage',
      'Mise à niveau complète, puis suppression des paquets inutiles et du cache.'
    ],
    'reboot': ['Redémarrer', 'Redémarre le serveur ; la connexion sera coupée.'],
    'sysinfo': [
      'Infos système (RAM/disque/uptime)',
      'Affiche la mémoire, l’espace disque et la durée de fonctionnement du serveur.'
    ],
    'bbr': ['Activer BBR', 'Active le contrôle de congestion BBR de Google pour des connexions plus rapides.'],
    'ports': ['Ports ouverts utilisés', 'Liste les ports en écoute et les programmes qui les utilisent.'],
    'tools': ['Installer les outils de base', 'Installe curl, wget, nano, htop, unzip et socat.'],
    'xui': ['3X-UI (Sanaei)', 'Installe ou met à jour le panneau 3X-UI.'],
    'xuiMenu': ['Menu de gestion 3X-UI', 'Ouvre le menu 3X-UI (démarrer, arrêter, réglages, journaux).'],
    'marzbanSqlite': ['Marzban (SQLite)', 'Installe Marzban avec la base SQLite par défaut.'],
    'marzbanMysql': ['Marzban (MySQL)', 'Installe Marzban avec une base de données MySQL.'],
    'marzbanAdmin': [
      'Marzban : créer un admin sudo',
      'Crée un compte administrateur avec tous les droits pour Marzban.'
    ],
    'kariz': ['Kariz : installation / menu', 'Installe Kariz ou ouvre son menu de gestion des tunnels.'],
    'karizPanel': ['Installer le panneau web Kariz', 'Installe le panneau d’administration web de Kariz.'],
    'backpack': ['Installer BackPack', 'Installe BackPack ; à lancer sur les deux serveurs.'],
    'backpackMenu': ['Menu BackPack', 'Ouvre le menu des tunnels BackPack.'],
  },
  'es': {
    'update': [
      'Actualizar servidor (Ubuntu/Debian)',
      'Actualiza la lista de paquetes e instala las actualizaciones disponibles.'
    ],
    'fullUpgrade': [
      'Actualización completa + limpieza',
      'Actualización completa y luego elimina paquetes sin uso y la caché.'
    ],
    'reboot': ['Reiniciar', 'Reinicia el servidor; la conexión se cortará.'],
    'sysinfo': [
      'Info del sistema (RAM/disco/uptime)',
      'Muestra el uso de memoria y disco y el tiempo que lleva encendido el servidor.'
    ],
    'bbr': ['Activar BBR', 'Activa el control de congestión BBR de Google para conexiones más rápidas.'],
    'ports': ['Puertos abiertos en uso', 'Lista los puertos en escucha y los programas que los usan.'],
    'tools': ['Instalar herramientas básicas', 'Instala curl, wget, nano, htop, unzip y socat.'],
    'xui': ['3X-UI (Sanaei)', 'Instala o actualiza el panel 3X-UI.'],
    'xuiMenu': ['Menú de gestión de 3X-UI', 'Abre el menú de 3X-UI (iniciar, detener, ajustes, registros).'],
    'marzbanSqlite': ['Marzban (SQLite)', 'Instala Marzban con la base de datos SQLite predeterminada.'],
    'marzbanMysql': ['Marzban (MySQL)', 'Instala Marzban con una base de datos MySQL.'],
    'marzbanAdmin': [
      'Marzban: crear admin sudo',
      'Crea una cuenta de administrador con acceso total al panel Marzban.'
    ],
    'kariz': ['Kariz: instalar / menú', 'Instala Kariz o abre su menú de gestión de túneles.'],
    'karizPanel': ['Instalar panel web de Kariz', 'Instala el panel de administración web de Kariz.'],
    'backpack': ['Instalar BackPack', 'Instala BackPack; ejecútalo en ambos servidores.'],
    'backpackMenu': ['Menú de BackPack', 'Abre el menú de túneles de BackPack.'],
  },
  'zh': {
    'update': ['更新服务器 (Ubuntu/Debian)', '刷新软件包列表并安装可用更新。'],
    'fullUpgrade': ['完整升级 + 清理', '完整升级系统，然后删除无用的软件包和缓存。'],
    'reboot': ['重启', '重启服务器，连接将会断开。'],
    'sysinfo': ['系统信息（内存/磁盘/运行时间）', '显示内存、磁盘使用情况和服务器运行时间。'],
    'bbr': ['启用 BBR', '开启 Google BBR 拥塞控制，让连接更快。'],
    'ports': ['正在使用的端口', '列出正在监听的端口及使用它们的程序。'],
    'tools': ['安装基础工具', '安装 curl、wget、nano、htop、unzip 和 socat。'],
    'xui': ['3X-UI (Sanaei)', '安装或更新 3X-UI 面板。'],
    'xuiMenu': ['3X-UI 管理菜单', '打开 3X-UI 菜单（启动、停止、设置、日志）。'],
    'marzbanSqlite': ['Marzban (SQLite)', '使用默认的 SQLite 数据库安装 Marzban。'],
    'marzbanMysql': ['Marzban (MySQL)', '使用 MySQL 数据库安装 Marzban。'],
    'marzbanAdmin': ['Marzban：创建 sudo 管理员', '为 Marzban 面板创建拥有全部权限的管理员账号。'],
    'kariz': ['Kariz 安装 / 菜单', '安装 Kariz 或打开其隧道管理菜单。'],
    'karizPanel': ['安装 Kariz 网页面板', '安装 Kariz 的网页管理面板。'],
    'backpack': ['安装 BackPack', '安装 BackPack；需在两台服务器上都运行。'],
    'backpackMenu': ['BackPack 菜单', '打开 BackPack 隧道菜单。'],
  },
};

/// Localized title of [c], falling back to English.
String builtinTitle(String lang, BuiltinCommand c) => (builtinText[lang]?[c.id] ?? builtinText['en']![c.id]!)[0];

/// Localized one-line description of [c], falling back to English.
String builtinDesc(String lang, BuiltinCommand c) => (builtinText[lang]?[c.id] ?? builtinText['en']![c.id]!)[1];

String builtinCategory(String lang, String cat) =>
    builtinCategoryNames[lang]?[cat] ?? builtinCategoryNames['en']![cat]!;
