package io.github.abiedadam0077.novacraft.ui

/** In-code AR/EN string tables (RTL handled by layout direction). */
object Strings {
    private val ar = mapOf(
        "app" to "NOVA CRAFT", "home" to "الرئيسية", "servers" to "السيرفرات", "console" to "الكونسول", "files" to "الملفات", "settings" to "الإعدادات",
        "welcome_title" to "سيرفر Minecraft الخاص بك، من هاتفك", "welcome_body" to "اربط GitHub مرة واحدة، أنشئ سيرفر Java أو Bedrock، وشغّله عبر GitHub Actions مع اتصال Playit.gg. بلا كلمات مرور محفوظة وبلا أسرار داخل التطبيق.",
        "get_started" to "ابدأ", "connect_github" to "ربط GitHub", "device_instructions" to "سنعرض لك كوداً قصيراً. افتح صفحة GitHub وأدخله هناك — لن نطلب كلمة مرورك أبداً.",
        "show_code" to "عرض كود الربط", "open_github" to "فتح github.com/login/device", "waiting" to "بانتظار تأكيدك في المتصفح…", "copy_code" to "نسخ الكود",
        "cancel" to "إلغاء", "retry" to "إعادة المحاولة", "save" to "حفظ", "delete" to "حذف", "back" to "رجوع", "next" to "التالي", "create" to "إنشاء",
        "install_app" to "تثبيت تطبيق NOVA CRAFT على GitHub", "install_body" to "بعد تسجيل الدخول، ثبّت التطبيق واختر المستودعات المسموحة. التطبيق لا يصل إلا للمستودعات التي تختارها.",
        "my_servers" to "سيرفراتي", "new_server" to "سيرفر جديد", "no_servers" to "لا توجد سيرفرات بعد. أنشئ أول سيرفر من المعالج.",
        "start" to "تشغيل", "stop" to "إيقاف", "restart" to "إعادة تشغيل", "backup_now" to "نسخة احتياطية الآن", "online" to "متصل", "offline" to "متوقف", "unknown" to "غير معروف",
        "repo_private" to "خاص (موصى به)", "repo_public" to "عام", "public_warning" to "تحذير: أي شخص يستطيع رؤية ملفات هذا المستودع ونسخ العالم. لن تُرفع أي أسرار أو Tokens إليه أبداً — الأسرار تبقى في GitHub Secrets المشفرة.",
        "server_name" to "اسم السيرفر", "edition" to "الإصدار", "mc_version" to "إصدار Minecraft", "software" to "برمجية السيرفر", "repo" to "المستودع",
        "create_new_repo" to "إنشاء مستودع جديد", "use_existing_repo" to "استخدام مستودع موجود", "review" to "مراجعة وإنشاء", "provisioning" to "جارٍ تجهيز السيرفر…",
        "players" to "اللاعبون", "ping" to "الـPing", "actions" to "GitHub Actions", "network" to "الشبكة وPlayit", "backups" to "النسخ الاحتياطية", "worlds" to "العوالم",
        "mods_plugins" to "المودات والبلاغينات", "server_settings" to "إعدادات السيرفر", "account" to "الحساب والأمان", "language" to "اللغة", "appearance" to "المظهر",
        "logout" to "تسجيل الخروج وفك الربط", "connected" to "متصل", "expired" to "منتهٍ", "disconnected" to "غير متصل",
        "send_command" to "إرسال أمر", "command_hint" to "مثال: say Hello أو list", "danger_confirm" to "هذا أمر حساس وقد يوقف السيرفر أو يغيّر الصلاحيات. تأكيد الإرسال؟",
        "confirm" to "تأكيد", "search" to "بحث", "upload" to "رفع ملف", "download" to "تنزيل", "edit" to "تحرير", "restore" to "استعادة",
        "address" to "عنوان الاتصال", "copy" to "نسخ", "playit_secret" to "Playit SECRET_KEY", "playit_body" to "أنشئ Agent من لوحة Playit.gg والصق مفتاحه هنا مرة واحدة. يُحفظ مشفراً كـGitHub Secret ولا يبقى على هاتفك.",
        "set_secret" to "حفظ كـSecret مشفر", "secret_set" to "تم حفظ الـSecret", "open_playit" to "فتح لوحة Playit",
        "generic_error" to "حدث خطأ", "offline_msg" to "لا اتصال بالشبكة أو انتهت الجلسة. أعد المحاولة.", "empty" to "لا بيانات لعرضها",
        "stop_confirm" to "إيقاف السيرفر؟ سيتم حفظ العالم وأخذ نسخة احتياطية قبل الإيقاف.", "delete_confirm" to "تأكيد الحذف؟ لا يمكن التراجع.",
        "pick_image" to "اختيار صورة من الجهاز", "remove_image" to "حذف الصورة", "max_players" to "أقصى لاعبين", "gamemode" to "وضع اللعبة", "difficulty" to "الصعوبة",
        "view_distance" to "مسافة الرؤية", "motd" to "رسالة السيرفر (MOTD)", "seed" to "البذرة (Seed)", "memory" to "الذاكرة (MB)", "summary" to "الملخص",
        "checking" to "جارٍ التحقق…", "refresh" to "تحديث", "last_backup" to "آخر نسخة", "uptime" to "بيانات الـRunner", "logs_polling" to "تحديث دوري (Polling) — ليست بثاً حياً",
        "privacy" to "الخصوصية", "privacy_body" to "لا نجمع إلا رموز GitHub المشفرة على جهازك وإعدادات التطبيق. لا كلمات مرور، لا Client Secret، لا Private Key داخل التطبيق.",
        "about" to "حول التطبيق", "workflow_status" to "حالة التشغيل", "force_stop" to "إيقاف قسري (إلغاء الـRun)", "select_server_first" to "اختر سيرفراً أولاً من قائمة السيرفرات",
        "tunnel_hint" to "العنوان الثابت يظهر في لوحة Playit داخل صفحة الـTunnel بعد إنشائه. انسخه هنا ليتحقق التطبيق منه بـPing حقيقي.",
        "restore_confirm" to "الاستعادة تستبدل العالم الحالي. سيأخذ الـWorkflow لقطة أمان قبل الاستبدال عند التشغيل التالي.", "snapshot" to "لقطة (Snapshot)"
    )
    private val en = mapOf(
        "app" to "NOVA CRAFT", "home" to "Home", "servers" to "Servers", "console" to "Console", "files" to "Files", "settings" to "Settings",
        "welcome_title" to "Your Minecraft server, from your phone", "welcome_body" to "Connect GitHub once, create a Java or Bedrock server, run it on GitHub Actions with a Playit.gg connection. No passwords stored, no secrets inside the app.",
        "get_started" to "Get started", "connect_github" to "Connect GitHub", "device_instructions" to "We will show you a short code. Open the GitHub page and enter it there — we never ask for your password.",
        "show_code" to "Show linking code", "open_github" to "Open github.com/login/device", "waiting" to "Waiting for you to confirm in the browser…", "copy_code" to "Copy code",
        "cancel" to "Cancel", "retry" to "Retry", "save" to "Save", "delete" to "Delete", "back" to "Back", "next" to "Next", "create" to "Create",
        "install_app" to "Install the NOVA CRAFT app on GitHub", "install_body" to "After sign-in, install the app and pick allowed repositories. The app only reaches repositories you select.",
        "my_servers" to "My Servers", "new_server" to "New Server", "no_servers" to "No servers yet. Create your first server with the wizard.",
        "start" to "Start", "stop" to "Stop", "restart" to "Restart", "backup_now" to "Backup now", "online" to "Online", "offline" to "Offline", "unknown" to "Unknown",
        "repo_private" to "Private (recommended)", "repo_public" to "Public", "public_warning" to "Warning: anyone can see this repository and world backups. Secrets/tokens are never uploaded — they stay in encrypted GitHub Secrets.",
        "server_name" to "Server name", "edition" to "Edition", "mc_version" to "Minecraft version", "software" to "Server software", "repo" to "Repository",
        "create_new_repo" to "Create a new repository", "use_existing_repo" to "Use an existing repository", "review" to "Review & Create", "provisioning" to "Provisioning your server…",
        "players" to "Players", "ping" to "Ping", "actions" to "GitHub Actions", "network" to "Network & Playit", "backups" to "Backups", "worlds" to "Worlds",
        "mods_plugins" to "Mods & Plugins", "server_settings" to "Server Settings", "account" to "Account & Security", "language" to "Language", "appearance" to "Appearance",
        "logout" to "Sign out & unlink", "connected" to "Connected", "expired" to "Expired", "disconnected" to "Disconnected",
        "send_command" to "Send command", "command_hint" to "e.g. say Hello or list", "danger_confirm" to "This is a sensitive command and may stop the server or change permissions. Send it?",
        "confirm" to "Confirm", "search" to "Search", "upload" to "Upload file", "download" to "Download", "edit" to "Edit", "restore" to "Restore",
        "address" to "Connection address", "copy" to "Copy", "playit_secret" to "Playit SECRET_KEY", "playit_body" to "Create an Agent in the Playit.gg dashboard and paste its key here once. It is stored encrypted as a GitHub Secret and not kept on your phone.",
        "set_secret" to "Save as encrypted Secret", "secret_set" to "Secret saved", "open_playit" to "Open Playit dashboard",
        "generic_error" to "Something went wrong", "offline_msg" to "No network or the session expired. Try again.", "empty" to "Nothing to show",
        "stop_confirm" to "Stop the server? The world will be saved and backed up first.", "delete_confirm" to "Confirm deletion? This cannot be undone.",
        "pick_image" to "Pick image from device", "remove_image" to "Remove image", "max_players" to "Max players", "gamemode" to "Game mode", "difficulty" to "Difficulty",
        "view_distance" to "View distance", "motd" to "MOTD", "seed" to "Seed", "memory" to "Memory (MB)", "summary" to "Summary",
        "checking" to "Checking…", "refresh" to "Refresh", "last_backup" to "Last backup", "uptime" to "Runner data", "logs_polling" to "Polling updates — not a live stream",
        "privacy" to "Privacy", "privacy_body" to "We only keep encrypted GitHub tokens on your device plus app settings. No passwords, no client secret, no private key inside the app.",
        "about" to "About", "workflow_status" to "Run status", "force_stop" to "Force stop (cancel run)", "select_server_first" to "Select a server first from the Servers list",
        "tunnel_hint" to "The static address appears in your Playit dashboard on the Tunnel page. Paste it here so the app can verify it with a real ping.",
        "restore_confirm" to "Restore replaces the current world. The workflow takes a safety snapshot before replacing on the next run.", "snapshot" to "Snapshot"
    )
    fun t(lang: String, key: String): String = (if (lang == "en") en else ar)[key] ?: en[key] ?: key
}
